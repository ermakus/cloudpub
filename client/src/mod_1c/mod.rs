use crate::commands::{CommandResult, Commands};
use crate::config::{ClientConfig, Platform};
use crate::shell::{download, find, get_cache_dir, unzip, SubProcess};
use anyhow::{bail, Context, Result};
use common::protocol::ServerEndpoint;
use lazy_static::lazy_static;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::broadcast;
use xml::escape::escape_str_attribute;

#[cfg(target_os = "windows")]
const APACHE_EXE: &str = "httpd.exe";
#[cfg(unix)]
const APACHE_EXE: &str = "httpd";

#[cfg(target_os = "windows")]
const WSAP_MODULE: &str = "wsap24.dll";

#[cfg(all(unix, debug_assertions))]
const WSAP_MODULE: &str = "wsap24t.so";

#[cfg(all(unix, not(debug_assertions)))]
const WSAP_MODULE: &str = "wsap24.so";

pub const APACHE_SUBDIR: &str = "apache";
pub const DOWNLOAD_SUBDIR: &str = "download";
pub const PUBLISH_SUBDIR: &str = "1c";

const APACHE_CONFIG: &str = include_str!("httpd.conf");
const DEFAULT_VRD: &str = include_str!("default.vrd");

#[derive(Clone)]
pub struct EnvConfig {
    pub home_1c: PathBuf,
    #[cfg(target_os = "windows")]
    pub redist: String,
    pub apache: String,
}

lazy_static! {
    static ref ENV_CONFIG: HashMap<Platform, EnvConfig> = {
        let mut m = HashMap::new();
        #[cfg(target_os = "windows")]
        m.insert(
            Platform::X64,
            EnvConfig {
                home_1c: PathBuf::from("C:\\Program Files\\1cv8\\"),
                redist: "vc_redist.x64.exe".to_string(),
                apache: "httpd-2.4.61-240703-win64-VS17.zip".to_string(),
            },
        );
        #[cfg(target_os = "windows")]
        m.insert(
            Platform::X32,
            EnvConfig {
                home_1c: PathBuf::from("C:\\Program Files (x86)\\1cv8"),
                redist: "vc_redist.x86.exe".to_string(),
                apache: "httpd-2.4.61-240703-win32-vs17.zip".to_string(),
            },
        );
        #[cfg(target_os = "linux")]
        m.insert(
            Platform::X64,
            EnvConfig {
                home_1c: PathBuf::from("/opt/1C"),
                apache: "httpd-2.4.62-linux.zip".to_string(),
            },
        );
        m
    };
}

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

    let cache_dir = get_cache_dir(DOWNLOAD_SUBDIR)?;
    let apache_dir = get_cache_dir(APACHE_SUBDIR)?;

    let mut touch = apache_dir.clone();
    touch.push("installed.txt");

    if touch.exists() {
        return Ok(());
    }

    let mut apache = cache_dir.clone();
    apache.push(env.apache.clone());

    download(
        "Загрузка веб сервера",
        config.clone(),
        format!("{}download/{}", config.read().server, env.apache).as_str(),
        &apache,
        command_rx.resubscribe(),
        result_tx.clone(),
    )
    .await
    .context("Ошибка загрузки веб сервера")?;

    unzip(
        "Распаковка веб-сервера",
        &apache,
        &apache_dir,
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

    // Touch file to mark success
    std::fs::write(touch, "Delete to reinstall").context("Ошибка создания файла метки")?;

    Ok(())
}

pub async fn publish(
    endpoint: &ServerEndpoint,
    config: Arc<RwLock<ClientConfig>>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<SubProcess> {
    let apache_dir = get_cache_dir(APACHE_SUBDIR)?;
    let publish_dir = get_cache_dir(PUBLISH_SUBDIR)?.join(endpoint.guid.to_string());
    std::fs::create_dir_all(publish_dir.clone()).context("Can't create publish dir")?;

    let mut apache_cfg = publish_dir.clone();
    apache_cfg.push("httpd.conf");

    let mut default_vrd = publish_dir.clone();
    default_vrd.push("default.vrd");

    let env = check_enviroment(config.clone())?;

    let wsap_error = format!(
        "Модуль {} на найден в {}. Проверьте настройки и убедитесь что у вас установлены модули расширения веб-сервера для 1С", WSAP_MODULE, &env.home_1c.to_str().unwrap());

    let wsap = if let Some(wsap) =
        find(&env.home_1c, &PathBuf::from(WSAP_MODULE)).context(wsap_error.clone())?
    {
        wsap
    } else {
        bail!(wsap_error);
    };

    let apache_config = APACHE_CONFIG.replace("[[PUBLISH_DIR]]", publish_dir.to_str().unwrap());
    let apache_config = apache_config.replace("[[WSAP_MODULE]]", &wsap.to_str().unwrap());
    let apache_config = apache_config.replace("[[SRVROOT]]", &apache_dir.to_str().unwrap());
    let apache_config = apache_config.replace("[[PORT]]", &endpoint.client.local_port.to_string());

    #[cfg(unix)]
    let apache_config = apache_config.replace("[[IS_LINUX]]", "");

    #[cfg(not(unix))]
    let apache_config = apache_config.replace("[[IS_LINUX]]", "#");

    std::fs::write(&apache_cfg, apache_config).context("Ошибка записи httpd.conf")?;

    let apache_cfg = apache_cfg.to_str().unwrap().to_string();
    let apache_exe = apache_dir.join("bin").join(APACHE_EXE);

    // if local_addr is existing path and folder, append File= else use as is
    let ib = if std::path::Path::new(&endpoint.client.local_addr).exists() {
        format!("File=\"{}\"", endpoint.client.local_addr)
    } else {
        endpoint.client.local_addr.clone()
    };

    let vrd_config = DEFAULT_VRD.replace("[[IB]]", &escape_str_attribute(&ib).into_owned());
    std::fs::write(&default_vrd, vrd_config).context("Ошибка записи default.vrd")?;

    // Set exec mode for apache_exe
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&apache_exe, std::fs::Permissions::from_mode(0o755))
            .context("Ошибка установки прав на исполнение")?;
    }

    let server = SubProcess::new(
        apache_exe,
        vec!["-X".to_string(), "-f".to_string(), apache_cfg],
        None,
        result_tx,
    );
    Ok(server)
}
