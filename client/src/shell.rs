use crate::config::ClientConfig;
use anyhow::{bail, Context, Result};
use std::cmp::min;
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;

use common::transport::rustls::load_roots;
use futures::stream::StreamExt;
use indicatif::{ProgressBar, ProgressStyle};
use parking_lot::RwLock;
use reqwest::{Certificate, ClientBuilder};
use runas::Command as ElevatedCommand;
use std::io;
use std::path::Path;
use std::process::Stdio;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tracing::{debug, info, warn};
use walkdir::WalkDir;
use zip::read::ZipArchive;

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

pub async fn execute(command: &Path, args: &[&str]) -> Result<()> {
    info!("Executing command: {:?} {:?}", command, args);

    let mut child = Command::new(command)
        .args(args)
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

    tokio::pin!(stdout_reader);
    tokio::pin!(stderr_reader);

    loop {
        tokio::select! {
            line = stdout_reader.next_line() => match line {
                Ok(Some(line)) => info!("STDOUT: {}", line),
                Err(e) => {
                    bail!("Error reading stdout: {}", e);
                },
                Ok(None) => break,
            },
            line = stderr_reader.next_line() => match line {
                Ok(Some(line)) => warn!("STDERR: {}", line),
                Err(e) => {
                    bail!("Error reading stderr: {}", e);
                },
                Ok(None) => break,
            }
        }
    }

    let status = child.wait().await.context("Failed to wait on child")?;
    if !status.success() {
        bail!("Command failed: {:?}", status);
    }

    Ok(())
}

pub fn unzip(zip_file_path: &Path, extract_dir: &Path, skip: usize) -> Result<()> {
    info!("Unzipping {:?} to {:?}", zip_file_path, extract_dir);
    let file = File::open(zip_file_path)?;
    let mut archive = ZipArchive::new(file)?;

    std::fs::create_dir_all(extract_dir)
        .context(format!("Failed to create dir '{:?}'", extract_dir))?;

    let progress_bar = ProgressBar::new(archive.len() as u64);
    progress_bar.set_style(
        ProgressStyle::default_bar().template(
            "[{elapsed_precise}] {bar:40.cyan/blue} {pos}/{len} files extracted ({eta})",
        )?,
    );

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

        progress_bar.inc(1);
    }

    progress_bar.finish();

    Ok(())
}

pub async fn download(config: Arc<RwLock<ClientConfig>>, url: &str, path: &Path) -> Result<()> {
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

    let pb = ProgressBar::new(total_size);
    pb.set_style(
        ProgressStyle::default_bar().template(
            "[{elapsed_precise}] {bar:40.cyan/blue} {pos}/{len} bytes download ({eta})",
        )?,
    );
    pb.set_message(format!("Downloading {} to {:?}", url, path));

    if let Ok(file) = File::open(&path) {
        if file
            .metadata()
            .context(format!("Failed to get metadata from '{:?}'", path))?
            .len()
            == total_size
        {
            pb.finish_with_message(format!("File already downloaded"));
            return Ok(());
        }
    }

    // download chunks
    let mut file = File::create(path).context(format!("Failed to create file '{:?}'", path))?;
    let mut downloaded: u64 = 0;
    let mut stream = res.bytes_stream();

    while let Some(item) = stream.next().await {
        let chunk = item.context("Failed to get chunk")?;
        file.write_all(&chunk)
            .context("Error while writing to file")?;
        let new = min(downloaded + (chunk.len() as u64), total_size);
        downloaded = new;
        pb.set_position(new);
    }

    pb.finish_with_message(format!("File downloaded"));
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
