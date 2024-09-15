use crate::commands::{EnvArgs, EnvPlatform, PublishArgs};
use crate::config::{ClientConfig, EnvConfig};
use crate::shell::{download, execute, find, unzip};
use anyhow::{bail, Context, Result};
use dirs::cache_dir;
use lazy_static::lazy_static;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::fs::remove_dir_all;
use std::path::PathBuf;
use std::sync::Arc;

lazy_static! {
    static ref ENV_CONFIG: HashMap<EnvPlatform, EnvConfig> = {
        let mut m = HashMap::new();
        m.insert(
            EnvPlatform::X64,
            EnvConfig {
                home_1c: PathBuf::from("C:\\Program Files\\1cv8\\"),
                redist: "vc_redist.x64.exe".to_string(),
                apache: "httpd-2.4.61-240703-win64-VS17.zip".to_string(),
            },
        );
        m.insert(
            EnvPlatform::X86,
            EnvConfig {
                home_1c: PathBuf::from("C:\\Program Files (x86)\\1cv8"),
                redist: "vc_redist.x86.exe".to_string(),
                apache: "httpd-2.4.61-240703-win32-vs17.zip".to_string(),
            },
        );
        m
    };
}

const APACHE_CONFIG: &str = include_str!("httpd.conf");

fn detect_platform() -> Option<EnvConfig> {
    for patform in ENV_CONFIG.iter() {
        if std::path::Path::new(&patform.1.home_1c).exists() {
            return Some((*patform.1).clone());
        }
    }
    None
}

fn check_enviroment(args: &EnvArgs) -> Result<EnvConfig> {
    let config = if let Some(platform) = args.platform.as_ref() {
        ENV_CONFIG.get(&platform).map(|x| x.clone())
    } else {
        detect_platform()
    };

    let mut config = if let Some(config) = config {
        config
    } else {
        bail!("Can't detect 1C platform, please set explicitly with --platform option");
    };

    if let Some(home) = args.home.as_ref() {
        config.home_1c = home.clone();
    }

    if !std::path::Path::new(&config.home_1c).exists() {
        bail!(
            "1C home directory ({:?}) not found, please set explicitly with --home option",
            config.home_1c
        );
    }
    Ok(config)
}

fn get_cache_dir() -> Result<PathBuf> {
    let mut cache_dir = cache_dir().context("Can't get cache dir")?;
    cache_dir.push("cloudpub");
    cache_dir.push("download");
    std::fs::create_dir_all(cache_dir.clone()).context("Can't create cache dir")?;
    Ok(cache_dir)
}

fn get_publish_dir() -> Result<PathBuf> {
    let mut publish_dir = dirs::data_dir().context("Can't get data dir")?;
    publish_dir.push("cloudpub");
    publish_dir.push("1C");
    Ok(publish_dir)
}

pub async fn setup(args: EnvArgs, config: Arc<RwLock<ClientConfig>>) -> Result<()> {
    let env = check_enviroment(&args)?;

    let cache_dir = get_cache_dir()?;

    let mut redist = cache_dir.clone();
    redist.push(env.redist.clone());

    let httpd = env.httpd();

    execute(&httpd, &["-k", "stop"]).await.ok();
    execute(&httpd, &["-k", "uninstall"]).await.ok();

    download(
        config.clone(),
        format!("{}/download/{}", config.read().server, env.redist).as_str(),
        &redist,
    )
    .await
    .context("Failed to download VC_redist")?;

    let mut apache = cache_dir.clone();
    apache.push(env.apache.clone());

    download(
        config.clone(),
        format!("{}/download/{}", config.read().server, env.apache).as_str(),
        &apache,
    )
    .await
    .context("Failed to download Apache")?;

    unzip(&apache, &env.home_apache(), 1).context("Failed to extract Apache")?;

    let mut httpd_conf = env.home_apache().clone();
    httpd_conf.push("conf");
    httpd_conf.push("httpd.conf");

    let apache_config = APACHE_CONFIG.replace(
        "[[PUBLISH_DIR]]",
        get_publish_dir()?.to_str().context("Invalid publish dir")?,
    );
    std::fs::write(&httpd_conf, apache_config).context("Failed to write httpd.conf")?;

    execute(&redist, &["/install", "/quiet", "/norestart"])
        .await
        .context("Failed to install VC_redist")?;

    execute(&httpd, &["-k", "install"])
        .await
        .context("Failed to install Apache")?;

    execute(&httpd, &["-k", "start"])
        .await
        .context("Failed to start Apache")?;

    config.write().env1c = Some(env);
    config.write().save().context("Failed to save config")?;

    Ok(())
}

pub async fn cleanup(config: Arc<RwLock<ClientConfig>>) -> Result<()> {
    let env = config
        .read()
        .env1c
        .as_ref()
        .context("1C enviroment not found")?
        .clone();

    let httpd = env.httpd();

    execute(&httpd, &["-k", "stop"])
        .await
        .context("Failed to stop Apache")?;

    execute(&httpd, &["-k", "uninstall"])
        .await
        .context("Failed to uninstall Apache")?;

    let cache_dir = get_cache_dir()?;
    let publish_dir = get_publish_dir()?;

    remove_dir_all(&"C:\\Program Files\\Apache Software Foundation").ok();
    remove_dir_all(&cache_dir).ok();
    remove_dir_all(&publish_dir).ok();

    Ok(())
}

pub async fn publish(args: &PublishArgs, config: Arc<RwLock<ClientConfig>>) -> Result<()> {
    let publish_dir = get_publish_dir()?;
    let env = config
        .read()
        .env1c
        .as_ref()
        .context("1C enviroment not found")?
        .clone();

    let webinst = if let Some(webinst) =
        find(&env.home_1c, &PathBuf::from("webinst.exe")).context("webinst not found")?
    {
        webinst
    } else {
        bail!("webinst not found");
    };

    let args = [
        "-publish",
        "-apache24",
        "-wsdir",
        "1c",
        "-connstr",
        &args.address,
        "-dir",
        publish_dir.to_str().unwrap(),
    ]
    .to_vec();

    execute(&webinst, &args)
        .await
        .context("Failed to publish 1C")?;

    let httpd = env.httpd();

    execute(&httpd, &["-k", "restart"])
        .await
        .context("Failed to restart Apache")?;

    Ok(())
}
