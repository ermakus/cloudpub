use crate::config::ClientConfig;
use crate::shell::{download, get_cache_dir, SubProcess};
use anyhow::{bail, Context, Result};
use common::protocol::message::Message;
use common::protocol::ServerEndpoint;
use common::utils::free_port_for_bind;
use parking_lot::RwLock;
use regex::Regex;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::info;

#[cfg(unix)]
use crate::shell::execute;

#[cfg(target_os = "windows")]
use crate::shell::unzip;

#[cfg(target_os = "windows")]
const JDK_URL: &str =
    "https://download.java.net/openjdk/jdk23/ri/openjdk-23+37_windows-x64_bin.zip";

#[cfg(target_os = "linux")]
const JDK_URL: &str =
    "https://download.java.net/openjdk/jdk23/ri/openjdk-23+37_linux-x64_bin.tar.gz";

#[cfg(target_os = "macos")]
const JDK_URL: &str = "https://download.java.net/java/GA/jdk23/3c5b90190c68498b986a97f276efd28a/37/GPL/openjdk-23_macos-x64_bin.tar.gz";

// Minecraft server 1.21.4
const MINECRAFT_SERVER_URL: &str =
    "https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar";

const MINECRAFT_SERVER_CFG: &str = include_str!("server.properties");

pub const JDK_SUBDIR: &str = "jdk";
pub const DOWNLOAD_SUBDIR: &str = "download";

#[cfg(not(target_os = "macos"))]
fn get_java() -> Result<PathBuf> {
    Ok(get_cache_dir(JDK_SUBDIR)?.join("bin").join("java"))
}

#[cfg(target_os = "macos")]
fn get_java() -> Result<PathBuf> {
    Ok(get_cache_dir(JDK_SUBDIR)?
        .join("Home")
        .join("bin")
        .join("java"))
}

pub async fn setup(
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Message>,
    result_tx: broadcast::Sender<Message>,
) -> Result<()> {
    info!("Setup minecraft server");

    let download_dir = get_cache_dir(DOWNLOAD_SUBDIR)?;
    let jdk_dir = get_cache_dir(JDK_SUBDIR)?;
    let jdk_filename = JDK_URL.split('/').last().unwrap();
    let jdk_file = download_dir.join(jdk_filename);

    let minecraft_file = download_dir.join("server.jar");

    let mut touch = jdk_dir.clone();
    touch.push("installed.txt");

    if touch.exists() {
        return Ok(());
    }

    download(
        "Загрузка JDK",
        config.clone(),
        JDK_URL,
        &jdk_file,
        command_rx.resubscribe(),
        result_tx.clone(),
    )
    .await
    .context("Ошибка загрузки веб сервера")?;

    #[cfg(unix)]
    execute(
        "tar".into(),
        vec![
            "xvf".to_string(),
            jdk_file.to_str().unwrap().to_string(),
            "-C".to_string(),
            jdk_dir.to_str().unwrap().to_string(),
            #[cfg(target_os = "macos")]
            "--strip-components=3".to_string(),
            #[cfg(not(target_os = "macos"))]
            "--strip-components=1".to_string(),
        ],
        None,
        Default::default(),
        Some(("Установка JDK".to_string(), result_tx.clone(), 450)),
        command_rx.resubscribe(),
    )
    .await?;

    #[cfg(target_os = "windows")]
    unzip("Распаковка JDK", &jdk_file, &jdk_dir, 1, result_tx.clone())
        .context("Ошибка распаковки JDK")?;

    let minecraft_jar = config
        .read()
        .minecraft_server
        .clone()
        .unwrap_or(MINECRAFT_SERVER_URL.to_string());

    let maybe_path = PathBuf::from(&minecraft_jar);

    if maybe_path.is_file() {
        std::fs::copy(&minecraft_jar, &minecraft_file)
            .with_context(|| format!("Ошибка копирования сервера Minecraft: {}", minecraft_jar))?;
    } else if maybe_path.is_dir() {
        bail!(
            "Неверный путь к JAR файлу сервера Minecraft: {} (директория)",
            minecraft_jar
        );
    } else if minecraft_jar.starts_with("http") {
        download(
            "Загрузка сервера Minecraft",
            config.clone(),
            &minecraft_jar,
            &minecraft_file,
            command_rx.resubscribe(),
            result_tx.clone(),
        )
        .await
        .with_context(|| format!("Ошибка загрузки сервера Minecraft: {}", minecraft_jar))?;
    } else {
        bail!(
            "Неверный путь или URL к серверу Minecraft: {}",
            minecraft_jar
        );
    }
    std::fs::write(touch, "Delete to reinstall").context("Ошибка создания файла метки")?;

    Ok(())
}

pub async fn publish(
    endpoint: &mut ServerEndpoint,
    config: Arc<RwLock<ClientConfig>>,
    result_tx: broadcast::Sender<Message>,
) -> Result<SubProcess> {
    free_port_for_bind(endpoint).await?;
    let minecraft_dir: PathBuf = endpoint.client.as_ref().unwrap().local_addr.clone().into();
    std::fs::create_dir_all(&minecraft_dir).context("Ошибка создания директории сервера")?;

    let download_dir = get_cache_dir(DOWNLOAD_SUBDIR)?;
    let minecraft_file = download_dir.join("server.jar");

    let mut server_cfg = minecraft_dir.clone();
    server_cfg.push("server.properties");

    let mut eula = minecraft_dir.clone();
    eula.push("eula.txt");

    if !server_cfg.exists() {
        std::fs::write(&server_cfg, MINECRAFT_SERVER_CFG)
            .context("Ошибка создания server.properties")?;
        std::fs::write(eula, "eula=true").context("Ошибка создания файла eula.txt")?;
    }

    let re = Regex::new(r"server\-port\s*=\s*\d+").unwrap();

    let server_config =
        std::fs::read_to_string(&server_cfg).context("Ошибка чтения server.properties")?;

    // Read the server config file and replace 'server-port=XXXX' with the new port
    let server_config = re.replace_all(&server_config, |_caps: &regex::Captures| {
        let new_port = endpoint.client.as_ref().unwrap().local_port.to_string();
        format!("server-port={}", new_port)
    });

    std::fs::write(&server_cfg, server_config.to_string())
        .context("Ошибка записи server.properties")?;

    // Use custom Java options if provided, otherwise use defaults
    let java_opts = config
        .read()
        .minecraft_java_opts
        .clone()
        .unwrap_or("-Xmx2048M -Xms2048M".to_string());

    // Split the Java options string into individual arguments
    let mut args: Vec<String> = java_opts
        .split_whitespace()
        .map(|s| s.to_string())
        .collect();

    // Add the jar file argument
    args.push("-jar".to_string());
    args.push(minecraft_file.to_str().unwrap().to_string());

    if !config.read().gui {
        args.push("nogui".to_string());
    }

    let server = SubProcess::new(
        get_java().context("Ошибка получения пути к java")?,
        args,
        Some(minecraft_dir),
        Default::default(),
        result_tx,
    );
    Ok(server)
}
