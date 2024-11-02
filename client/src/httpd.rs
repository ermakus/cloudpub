use crate::commands::{CommandResult, Commands};
use crate::config::{ClientConfig, EnvConfig};
use crate::shell::{download, get_cache_dir, unzip, SubProcess, DOWNLOAD_SUBDIR};
use anyhow::{Context, Result};
use common::protocol::ServerEndpoint;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::broadcast;

#[cfg(target_os = "windows")]
pub const HTTPD_EXE: &str = "httpd.exe";
#[cfg(unix)]
pub const HTTPD_EXE: &str = "httpd";

pub async fn setup_httpd(
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Commands>,
    result_tx: broadcast::Sender<CommandResult>,
    env: EnvConfig,
) -> Result<()> {
    let cache_dir = get_cache_dir(DOWNLOAD_SUBDIR)?;
    let httpd_dir = get_cache_dir(&env.httpd_dir)?;

    let mut touch = httpd_dir.clone();
    touch.push("installed.txt");

    if touch.exists() {
        return Ok(());
    }

    let mut httpd = cache_dir.clone();
    httpd.push(env.httpd.clone());

    download(
        "Загрузка веб сервера",
        config.clone(),
        format!("{}download/{}", config.read().server, env.httpd).as_str(),
        &httpd,
        command_rx.resubscribe(),
        result_tx.clone(),
    )
    .await
    .context("Ошибка загрузки веб сервера")?;

    unzip(
        "Распаковка веб-сервера",
        &httpd,
        &httpd_dir,
        1,
        result_tx.clone(),
    )
    .context("Ошибка распаковки веб сервера")?;

    #[cfg(target_os = "windows")]
    {
        use crate::shell::execute;
        let mut redist = cache_dir.clone();
        redist.push(env.redist.clone());

        download(
            "Загрузка компонентов VC++",
            config.clone(),
            format!("{}download/{}", config.read().server, env.redist).as_str(),
            &redist,
            command_rx.resubscribe(),
            result_tx.clone(),
        )
        .await
        .context("Ошибка загрузки компонентов VC++")?;

        execute(
            redist,
            vec![
                "/install".to_string(),
                "/quiet".to_string(),
                "/norestart".to_string(),
            ],
            None,
            Default::default(),
            Some((
                "Установка компонентов VC++".to_string(),
                result_tx.clone(),
                2,
            )),
            command_rx.resubscribe(),
        )
        .await
        .context("Ошибка установки компонентов VC++")?;
    }
    // Set exec mode for httpd_exe
    #[cfg(unix)]
    {
        let httpd_exe = httpd_dir.join("bin").join(HTTPD_EXE);
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&httpd_exe, std::fs::Permissions::from_mode(0o755))
            .context("Ошибка установки прав на исполнение")?;
    }

    // Touch file to mark success
    std::fs::write(touch, "Delete to reinstall").context("Ошибка создания файла метки")?;

    Ok(())
}

pub async fn start_httpd(
    endpoint: &ServerEndpoint,
    config_template: &str,
    config_subdir: &str,
    publish_dir: &str,
    env: EnvConfig,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<SubProcess> {
    let httpd_dir = get_cache_dir(&env.httpd_dir)?;
    let configs_dir = get_cache_dir(config_subdir)?;

    let mut httpd_cfg = configs_dir.clone();
    httpd_cfg.push(format!("{}.conf", endpoint.guid));

    let httpd_config = config_template.replace("[[PUBLISH_DIR]]", &publish_dir);
    let httpd_config = httpd_config.replace("[[SRVROOT]]", &httpd_dir.to_str().unwrap());
    let httpd_config = httpd_config.replace("[[PORT]]", &endpoint.client.local_port.to_string());

    #[cfg(unix)]
    let httpd_config = httpd_config.replace("[[IS_LINUX]]", "");

    #[cfg(not(unix))]
    let httpd_config = httpd_config.replace("[[IS_LINUX]]", "#");

    std::fs::write(&httpd_cfg, httpd_config).context("Ошибка записи httpd.conf")?;

    let httpd_cfg = httpd_cfg.to_str().unwrap().to_string();
    let httpd_exe = httpd_dir.join("bin").join(HTTPD_EXE);

    #[allow(unused_mut)]
    let mut envs = HashMap::<String, String>::new();

    #[cfg(target_os = "macos")]
    envs.insert(
        "DYLD_LIBRARY_PATH".to_string(),
        httpd_dir.join("lib").to_str().unwrap().to_string(),
    );

    let server = SubProcess::new(
        httpd_exe,
        vec!["-X".to_string(), "-f".to_string(), httpd_cfg],
        None,
        envs,
        result_tx,
    );
    Ok(server)
}