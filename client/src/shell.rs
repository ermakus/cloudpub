use crate::config::ClientConfig;
use anyhow::{bail, Context, Result};
use std::cmp::min;
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;

use crate::commands::{CommandResult, Commands, ProgressInfo};
use common::protocol::ErrorKind;
use common::transport::rustls::load_roots;
use futures::stream::StreamExt;
use parking_lot::RwLock;
use reqwest::{Certificate, ClientBuilder};
use runas::Command as ElevatedCommand;
use std::io;
use std::path::Path;
use std::process::Stdio;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::broadcast;
use tracing::{debug, error, info, warn};
use walkdir::WalkDir;
use zip::read::ZipArchive;

pub struct SubProcess {
    shutdown_tx: broadcast::Sender<Commands>,
}

impl SubProcess {
    pub fn new(
        command: PathBuf,
        args: Vec<String>,
        result_tx: broadcast::Sender<CommandResult>,
    ) -> Self {
        let (shutdown_tx, shutdown_rx) = broadcast::channel(1);
        tokio::spawn(async move {
            if let Err(err) = execute(command, args, shutdown_rx).await {
                error!("Failed to execute command: {:?}", err);
                result_tx
                    .send(CommandResult::Error(
                        ErrorKind::ExecuteFailed,
                        err.to_string(),
                    ))
                    .ok();
            }
        });
        Self { shutdown_tx }
    }

    pub fn stop(&mut self) {
        self.shutdown_tx.send(Commands::Break).ok();
    }
}

impl Drop for SubProcess {
    fn drop(&mut self) {
        self.stop();
    }
}

#[allow(dead_code)]
pub fn elevated_execute(command: &Path, args: &[&str]) -> Result<()> {
    info!("Executing evelated command: {:?} {:?}", command, args);

    ElevatedCommand::new(command)
        .args(args)
        .status()
        .context(format!(
            "Failed to execute command: {:?} {:?}",
            command, args
        ))?;
    Ok(())
}

#[allow(dead_code)]
pub fn pause() {
    dbg!("Pausing! Press enter to continue...");

    let mut buffer = String::new();

    std::io::stdin()
        .read_line(&mut buffer)
        .expect("Failed to read line");
}

#[allow(dead_code)]
pub async fn execute_with_progress(
    message: &str,
    command: PathBuf,
    args: Vec<String>,
    shutdown_rx: broadcast::Receiver<Commands>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<()> {
    const TEMPLATE: &str = "[{elapsed_precise}] {bar:40.cyan/blue} {pos}/{len} исполнено";

    result_tx
        .send(CommandResult::Progress(ProgressInfo {
            message: message.to_string(),
            template: TEMPLATE.to_string(),
            current: 0,
            total: 1,
        }))
        .ok();

    let res = execute(command, args, shutdown_rx).await;

    result_tx
        .send(CommandResult::Progress(ProgressInfo {
            message: message.to_string(),
            template: TEMPLATE.to_string(),
            current: 1,
            total: 1,
        }))
        .ok();

    res
}

pub async fn execute(
    command: PathBuf,
    args: Vec<String>,
    mut shutdown_rx: broadcast::Receiver<Commands>,
) -> Result<()> {
    info!(
        "Executing command: {} {}",
        command.to_str().unwrap(),
        args.join(" ")
    );

    #[cfg(windows)]
    let mut child = Command::new(command.clone())
        .args(args.clone())
        .kill_on_drop(true)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .creation_flags(0x08000000)
        .spawn()
        .context(format!(
            "Failed to execute command: {:?} {:?}",
            command, args
        ))?;

    #[cfg(not(windows))]
    let mut child = Command::new(command.clone())
        .args(args.clone())
        .kill_on_drop(true)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context(format!(
            "Failed to execute command: {:?} {:?}",
            command, args
        ))?;

    let stdout = child.stdout.take().context("Failed to get stdout")?;
    let stderr = child.stderr.take().context("Failed to get stderr")?;

    let stdout_reader = BufReader::new(stdout).lines();
    let stderr_reader = BufReader::new(stderr).lines();

    tokio::spawn(async move {
        tokio::pin!(stdout_reader);
        tokio::pin!(stderr_reader);
        loop {
            tokio::select! {
                line = stdout_reader.next_line() => match line {
                    Ok(Some(line)) => info!("STDOUT: {}", line),
                    Err(e) => {
                        bail!("Error reading stdout: {}", e);
                    },
                    Ok(None) => {
                        info!("STDOUT EOF");
                        break;
                    }
                },
                line = stderr_reader.next_line() => match line {
                    Ok(Some(line)) => warn!("STDERR: {}", line),
                    Err(e) => {
                        bail!("Error reading stderr: {}", e);
                    },
                    Ok(None) => {
                        info!("STDERR EOF");
                        break;
                    }
                },
            }
        }
        Ok(())
    });

    tokio::select! {
        status = child.wait() => {
            let status = status.context("Failed to wait on child")?;
            if !status.success() {
                bail!("Command failed: {:?}", status);
            }
        }

        cmd = shutdown_rx.recv() => match cmd {
            Ok(Commands::Break) => {
                info!("Received break command, killing child process");
                child.kill().await.ok();
            }
            Err(e) => {
                info!("Command channel error, killing child process: {:?}", e);
                child.kill().await.ok();
            }
            _ => {}
        }
    }

    info!("Command executed successfully");

    Ok(())
}

pub fn unzip(
    message: &str,
    zip_file_path: &Path,
    extract_dir: &Path,
    skip: usize,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<()> {
    info!("Unzipping {:?} to {:?}", zip_file_path, extract_dir);
    let file = File::open(zip_file_path)?;
    let mut archive = ZipArchive::new(file)?;

    std::fs::create_dir_all(extract_dir)
        .context(format!("Failed to create dir '{:?}'", extract_dir))?;

    const TEMPLATE: &str = "[{elapsed_precise}] {bar:40.cyan/blue} {pos}/{len} файлов ({eta})";

    let mut progress = ProgressInfo {
        message: message.to_string(),
        template: TEMPLATE.to_string(),
        total: archive.len() as u64,
        current: 0,
    };

    result_tx
        .send(CommandResult::Progress(progress.clone()))
        .ok();

    for i in 0..archive.len() {
        let mut file = archive
            .by_index(i)
            .context("Failed to get file from archive")?;
        let file_name = Path::new(file.name())
            .components()
            .skip(skip)
            .collect::<PathBuf>();
        let target_path = Path::new(extract_dir).join(file_name);
        if target_path == extract_dir {
            continue;
        }
        debug!("Extracting {:?}", target_path);
        if file.is_dir() {
            std::fs::create_dir_all(target_path.clone())
                .context(format!("unzip failed to create dir '{:?}'", target_path))?;
        } else {
            let mut output_file = File::create(target_path.clone())
                .context(format!("unzip failed to create file '{:?}'", target_path))?;
            io::copy(&mut file, &mut output_file).context("unzip failed to copy file")?;
        }

        progress.current = (i + 1) as u64;
        result_tx
            .send(CommandResult::Progress(progress.clone()))
            .ok();
    }

    Ok(())
}

pub async fn download(
    message: &str,
    config: Arc<RwLock<ClientConfig>>,
    url: &str,
    path: &Path,
    mut command_rx: broadcast::Receiver<Commands>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<()> {
    info!("Downloading {} to {:?}", url, path);

    let mut client = ClientBuilder::default();

    if let Some(tls) = &config.read().transport.tls {
        let roots = load_roots(tls).context("Failed to load client config")?;
        for cert in roots {
            client = client.add_root_certificate(Certificate::from_der(&cert)?);
        }
    }

    let client = client.build().context("Failed to create reqwest client")?;
    // Reqwest setup
    let res = client
        .get(url)
        .send()
        .await
        .context(format!("Failed to GET from '{}'", &url))?;

    // Indicatif setup
    let total_size = res
        .content_length()
        .context(format!("Failed to get content length from '{}'", &url))?;

    if let Ok(file) = File::open(&path) {
        if file
            .metadata()
            .context(format!("Failed to get metadata from '{:?}'", path))?
            .len()
            == total_size
        {
            return Ok(());
        }
    }

    const TEMPLATE: &str = "[{elapsed_precise}] {bar:40.cyan/blue} {pos}/{len} байт ({eta})";

    let mut progress = ProgressInfo {
        message: message.to_string(),
        template: TEMPLATE.to_string(),
        total: total_size,
        current: 0,
    };

    result_tx
        .send(CommandResult::Progress(progress.clone()))
        .ok();

    // download chunks
    let mut file = File::create(path).context(format!("Failed to create file '{:?}'", path))?;
    let mut stream = res.bytes_stream();

    loop {
        tokio::select! {
            cmd = command_rx.recv() => {
                match cmd {
                    Ok(Commands::Break) => {
                        info!("Download cancelled");
                        progress.total = total_size;
                        result_tx.send(CommandResult::Progress(progress.clone())).ok();
                        bail!("Download cancelled");
                    }
                    Err(err) => {
                        error!("Command channel error: {:?}", err);
                        progress.total = total_size;
                        result_tx.send(CommandResult::Progress(progress.clone())).ok();
                        bail!(err);
                    }
                    _ => {}
                }
            }

            item = stream.next() => {
                if let Some(item) =  item {
                let chunk = item.context("Failed to get chunk")?;
                    file.write_all(&chunk)
                        .context("Error while writing to file")?;
                    progress.current = min(progress.current + (chunk.len() as u64), total_size);
                    result_tx.send(CommandResult::Progress(progress.clone())).ok();
                } else {
                    break;
                }
            }
        }
    }

    progress.current = total_size;
    result_tx
        .send(CommandResult::Progress(progress.clone()))
        .ok();
    return Ok(());
}

pub fn compare_filenames(path1: &Path, path2: &Path) -> bool {
    if let (Some(file_name1), Some(file_name2)) = (path1.file_name(), path2.file_name()) {
        let filename1 = file_name1.to_string_lossy();
        let filename2 = file_name2.to_string_lossy();
        #[cfg(windows)]
        return filename1.eq_ignore_ascii_case(&filename2);
        #[cfg(not(windows))]
        filename1.eq(&filename2)
    } else {
        false
    }
}

pub fn find(dir: &Path, file: &Path) -> Result<Option<PathBuf>> {
    info!("Searching for {:?} in {:?}", file, dir);
    for entry in WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
        if compare_filenames(entry.path(), file) {
            return Ok(Some(entry.path().to_path_buf()));
        }
    }
    Ok(None)
}
