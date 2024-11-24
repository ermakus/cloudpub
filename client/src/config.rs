use anyhow::{bail, Context, Result};
use common::constants::{DEFAULT_HEARTBEAT_TIMEOUT_SECS, DEFAULT_SERVER};
use serde::{Deserialize, Serialize};
use std::fmt::{Debug, Display, Formatter};

pub use common::config::{MaskedString, Protocol, TransportConfig};
use common::protocol::{Access, ClientEndpoint, ServerEndpoint};
use lazy_static::lazy_static;
use std::collections::HashMap;
use std::fs::{self, create_dir_all};
use std::path::PathBuf;
use toml;
use tracing::debug;
use url::Url;
use uuid::Uuid;

#[derive(Clone, Default, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Platform {
    #[default]
    X64,
    X32,
}

#[derive(Clone)]
pub struct EnvConfig {
    pub home_1c: PathBuf,
    #[cfg(target_os = "windows")]
    pub redist: String,
    pub httpd: String,
    pub httpd_dir: String,
}

impl Default for EnvConfig {
    fn default() -> Self {
        #[cfg(target_pointer_width = "64")]
        return ENV_CONFIG.get(&Platform::X64).unwrap().clone();
        #[cfg(target_pointer_width = "32")]
        return ENV_CONFIG.get(&Platform::X32).unwrap().clone();
    }
}

lazy_static! {
    pub static ref ENV_CONFIG: HashMap<Platform, EnvConfig> = {
        let mut m = HashMap::new();
        #[cfg(target_os = "windows")]
        m.insert(
            Platform::X64,
            EnvConfig {
                home_1c: PathBuf::from("C:\\Program Files\\1cv8\\"),
                redist: "vc_redist.x64.exe".to_string(),
                httpd: "httpd-2.4.61-240703-win64-VS17.zip".to_string(),
                httpd_dir: "httpd-x64".to_string(),
            },
        );
        #[cfg(target_os = "windows")]
        m.insert(
            Platform::X32,
            EnvConfig {
                home_1c: PathBuf::from("C:\\Program Files (x86)\\1cv8"),
                redist: "vc_redist.x86.exe".to_string(),
                httpd: "httpd-2.4.61-240703-win32-vs17.zip".to_string(),
                httpd_dir: "httpd-x32".to_string(),
            },
        );
        #[cfg(target_os = "linux")]
        m.insert(
            Platform::X64,
            EnvConfig {
                home_1c: PathBuf::from("/opt/1C"),
                httpd: "httpd-2.4.62-linux.zip".to_string(),
                httpd_dir: "httpd-x64".to_string(),
            },
        );
        #[cfg(target_os = "macos")]
        m.insert(
            Platform::X64,
            EnvConfig {
                home_1c: PathBuf::from("/Applications/1C"),
                httpd: "httpd-2.4.62-macos.zip".to_string(),
                httpd_dir: "httpd-x64".to_string(),
            },
        );
        m
    };
}

impl Display for Platform {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        match self {
            Platform::X64 => write!(f, "x64"),
            Platform::X32 => write!(f, "x32"),
        }
    }
}

impl std::str::FromStr for Platform {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        match s {
            "x64" => Ok(Platform::X64),
            "x32" => Ok(Platform::X32),
            _ => bail!("Invalid platform: {}", s),
        }
    }
}

/// All Option are optional in configuration but must be Some value in runtime
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, Default)]
pub struct ClientServiceConfig {
    pub local_proto: Protocol,
    pub local_port: u16,
    pub local_addr: String,
    pub nodelay: Option<bool>,
    pub access: Vec<Access>,
}

impl Display for ClientServiceConfig {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        write!(
            f,
            "{}://{}:{}",
            self.local_proto, self.local_addr, self.local_port
        )
    }
}

impl Into<ClientEndpoint> for ClientServiceConfig {
    fn into(self) -> ClientEndpoint {
        ClientEndpoint {
            local_proto: self.local_proto,
            local_addr: self.local_addr,
            local_port: self.local_port,
            nodelay: self.nodelay,
            description: None,
            access: Vec::new(),
        }
    }
}

// Version 1.21.3 of the Minecraft server
fn get_minecraft_jar() -> String {
    "https://piston-data.mojang.com/v1/objects/45810d238246d90e811d896f87b14695b7fb6839/server.jar"
        .to_string()
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq, Clone)]
pub struct ClientConfig {
    // This fields are not persistent
    #[serde(skip)]
    config_path: PathBuf,
    #[serde(skip)]
    pub readonly: bool,
    #[serde(skip)]
    pub gui: bool,
    // Next fields are persistent
    pub agent_id: String,
    pub server: Url,
    pub token: Option<MaskedString>,
    pub heartbeat_timeout: u64,
    pub one_c_home: Option<String>,
    pub one_c_platform: Option<Platform>,
    pub one_c_publish_dir: Option<String>,
    #[serde(default = "get_minecraft_jar")]
    pub minecraft_jar: String,
    pub transport: TransportConfig,
    #[serde(skip_serializing_if = "Vec::is_empty", default = "Vec::new")]
    pub services: Vec<ServerEndpoint>,
}

impl ClientConfig {
    pub fn from_str(s: &str) -> Result<Self> {
        let config: Self = toml::from_str(s).context("Failed to parse the config")?;
        Ok(config)
    }

    pub fn from_file(path: &PathBuf, readonly: bool, gui: bool) -> Result<Self> {
        let s: String = fs::read_to_string(path)
            .with_context(|| format!("Failed to read the config {:?}", path))?;
        let mut cfg = Self::from_str(&s).with_context(|| {
            "Configuration is invalid. Please refer to the configuration specification."
        })?;

        cfg.config_path = path.clone();
        cfg.readonly = readonly;
        cfg.gui = gui;
        Ok(cfg)
    }

    pub fn get_config_dir(user_dir: bool) -> Result<PathBuf> {
        let dir = if user_dir {
            let mut dir = dirs::config_dir().context("Can't get config_dir")?;
            dir.push("cloudpub");
            dir
        } else {
            if cfg!(target_family = "unix") {
                PathBuf::from("./etc/cloudpub")
            } else {
                PathBuf::from(
                    "C:\\Windows\\system32\\config\\systemprofile\\AppData\\Local\\cloudpub",
                )
            }
        };
        if !dir.exists() {
            create_dir_all(&dir).context("Can't create config dir")?;
        }
        debug!("Config dir: {:?}", dir);
        Ok(dir)
    }

    pub fn save(&self) -> Result<()> {
        if self.readonly {
            debug!("Skipping saving the config in readonly mode");
        } else {
            let s = toml::to_string_pretty(self).context("Failed to serialize the config")?;
            fs::write(&self.config_path, s).context("Failed to write the config")?;
        }
        Ok(())
    }

    pub fn load(cfg_name: &str, user_dir: bool, readonly: bool, gui: bool) -> Result<Self> {
        let mut config_path = Self::get_config_dir(user_dir)?;
        config_path.push(cfg_name);
        if !config_path.exists() {
            let default_config = Self::default();
            let s = toml::to_string_pretty(&default_config)
                .context("Failed to serialize the default config")?;
            fs::write(&config_path, s).context("Failed to write the default config")?;
        }

        Self::from_file(&config_path, readonly, gui)
    }

    pub fn set(&mut self, key: &str, value: &str) -> Result<()> {
        match key {
            "server" => self.server = value.parse().context("Invalid server URL")?,
            "token" => self.token = Some(MaskedString::from(value)),
            "heartbeat_timeout" => {
                self.heartbeat_timeout = value.parse().context("Invalid heartbeat_timeout")?
            }
            "1c_home" => {
                if value.is_empty() {
                    self.one_c_home = None
                } else {
                    self.one_c_home = Some(value.to_string())
                }
            }
            "1c_platform" => {
                if value.is_empty() {
                    self.one_c_platform = None
                } else {
                    self.one_c_platform = Some(value.parse().context("Invalid platform")?)
                }
            }
            "1c_publish_dir" => {
                if value.is_empty() {
                    self.one_c_publish_dir = None
                } else {
                    self.one_c_publish_dir = Some(value.to_string())
                }
            }
            "minecraft_jar" => self.minecraft_jar = value.to_string(),
            _ => bail!("Unknown key: {}", key),
        }
        self.save()?;
        Ok(())
    }

    pub fn get(&self, key: &str) -> Result<String> {
        match key {
            "server" => Ok(self.server.to_string()),
            "token" => Ok(self
                .token
                .as_ref()
                .map_or("".to_string(), |t| t.to_string())),
            "heartbeat_timeout" => Ok(self.heartbeat_timeout.to_string()),
            "1c_home" => Ok(self.one_c_home.clone().unwrap_or_default()),
            "1c_platform" => Ok(self
                .one_c_platform
                .as_ref()
                .map(|p| p.to_string())
                .unwrap_or_default()),
            "1c_publish_dir" => Ok(self.one_c_publish_dir.clone().unwrap_or_default()),
            "minecraft_jar" => Ok(self.minecraft_jar.clone()),
            _ => bail!("Unknown key: {}", key),
        }
    }

    pub fn validate(&self) -> Result<()> {
        if self.token.is_none() {
            bail!("Token is not set");
        }
        TransportConfig::validate(&self.transport, false)?;
        Ok(())
    }
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            agent_id: Uuid::new_v4().to_string(),
            config_path: PathBuf::new(),
            server: DEFAULT_SERVER.parse().unwrap(),
            token: None,
            heartbeat_timeout: DEFAULT_HEARTBEAT_TIMEOUT_SECS,
            one_c_home: None,
            one_c_platform: None,
            one_c_publish_dir: None,
            transport: TransportConfig::default(),
            services: Vec::new(),
            readonly: false,
            gui: false,
            minecraft_jar: get_minecraft_jar(),
        }
    }
}
