use crate::commands::{CommandResult, Commands};
use crate::config::{ClientConfig, EnvConfig, ENV_CONFIG};
use crate::httpd::{setup_httpd, start_httpd};
use crate::shell::{find, get_cache_dir, SubProcess};
use anyhow::{bail, Context, Result};
use common::protocol::ServerEndpoint;
use parking_lot::RwLock;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::broadcast;
use xml::escape::escape_str_attribute;

#[cfg(target_os = "windows")]
const WSAP_MODULE: &str = "wsap24.dll";

#[cfg(all(unix, debug_assertions))]
const WSAP_MODULE: &str = "wsap24t.so";

#[cfg(all(unix, not(debug_assertions)))]
const WSAP_MODULE: &str = "wsap24.so";

pub const ONEC_SUBDIR: &str = "1c";
const ONEC_CONFIG: &str = include_str!("httpd.conf");
const DEFAULT_VRD: &str = include_str!("default.vrd");

fn detect_platform() -> Option<EnvConfig> {
    for patform in ENV_CONFIG.iter() {
        if std::path::Path::new(&patform.1.home_1c).exists() {
            return Some((*patform.1).clone());
        }
    }
    None
}

fn check_enviroment(config: Arc<RwLock<ClientConfig>>) -> Result<EnvConfig> {
    let env = if let Some(platform) = config.read().one_c_platform.as_ref() {
        ENV_CONFIG.get(&platform).cloned()
    } else {
        detect_platform()
    };

    let mut env = if let Some(env) = env {
        env
    } else {
        bail!("Платформа 1C не найдена, укажите ее битность (x32/x64) и путь в настройках");
    };

    if let Some(one_c_home) = &config.read().one_c_home {
        env.home_1c = PathBuf::from(one_c_home);
    }

    if !std::path::Path::new(&env.home_1c).exists() {
        bail!(
            "Путь до платформы 1C ({}) не найден, укажите его в настройках",
            env.home_1c.to_str().unwrap()
        );
    }
    Ok(env)
}

pub async fn setup(
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Commands>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<()> {
    let env = check_enviroment(config.clone())?;
    setup_httpd(config, command_rx, result_tx, env).await
}

pub async fn publish(
    endpoint: &ServerEndpoint,
    config: Arc<RwLock<ClientConfig>>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<SubProcess> {
    let env = check_enviroment(config.clone())?;

    let publish_dir = get_cache_dir(ONEC_SUBDIR)?.join(endpoint.guid.to_string());
    std::fs::create_dir_all(publish_dir.clone()).context("Can't create publish dir")?;

    let mut default_vrd = publish_dir.clone();
    default_vrd.push("default.vrd");

    let wsap_error = format!(
        "Модуль {} на найден в {}. Проверьте настройки и убедитесь что у вас установлены модули расширения веб-сервера для 1С", WSAP_MODULE, &env.home_1c.to_str().unwrap());

    let wsap = if let Some(wsap) =
        find(&env.home_1c, &PathBuf::from(WSAP_MODULE)).context(wsap_error.clone())?
    {
        wsap
    } else {
        bail!(wsap_error);
    };

    // if local_addr is existing path and folder, append File= else use as is
    let ib = if std::path::Path::new(&endpoint.client.local_addr).exists() {
        format!("File=\"{}\"", endpoint.client.local_addr)
    } else {
        endpoint.client.local_addr.clone()
    };

    let vrd_config = DEFAULT_VRD.replace("[[IB]]", &escape_str_attribute(&ib).into_owned());

    if !default_vrd.exists() {
        std::fs::write(&default_vrd, vrd_config).context("Ошибка записи default.vrd")?;
    }

    let httpd_config = ONEC_CONFIG.replace("[[WSAP_MODULE]]", &wsap.to_str().unwrap());
    start_httpd(
        endpoint,
        &httpd_config,
        ONEC_SUBDIR,
        publish_dir.to_str().unwrap(),
        env,
        result_tx,
    )
    .await
}
