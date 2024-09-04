use anyhow::{bail, Context, Result};
use common::constants::{
    DEFAULT_CLIENT_RETRY_INTERVAL_SECS, DEFAULT_HEARTBEAT_TIMEOUT_SECS, DEFAULT_SERVER,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt::{Debug, Display, Formatter};

use common::config::{MaskedString, ServiceType, TransportConfig};
use common::protocol::ClientEndpoint;
use std::fs::{self, create_dir_all};
use std::path::PathBuf;
use toml;
use tracing::debug;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct EnvConfig {
    pub home_1c: PathBuf,
    pub home_apache: PathBuf,
    pub redist: String,
    pub apache: String,
}

impl EnvConfig {
    pub fn httpd(&self) -> PathBuf {
        let mut httpd = self.home_apache.clone();
        httpd.push("bin");
        httpd.push("httpd.exe");
        httpd
    }
}

/// All Option are optional in configuration but must be Some value in runtime
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, Default)]
#[serde(deny_unknown_fields)]
pub struct ClientServiceConfig {
    #[serde(rename = "type")]
    pub service_type: ServiceType,
    pub local_addr: String,
    pub nodelay: Option<bool>,
}

impl Display for ClientServiceConfig {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        write!(f, "{}://{}", self.service_type, self.local_addr)
    }
}

impl Into<ClientEndpoint> for ClientServiceConfig {
    fn into(self) -> ClientEndpoint {
        ClientEndpoint {
            service_type: self.service_type,
            local_addr: self.local_addr,
            nodelay: self.nodelay,
            name: None,
            retry_interval: None,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq, Clone)]
#[serde(deny_unknown_fields)]
pub struct ClientConfig {
    #[serde(skip)]
    config_path: PathBuf,
    pub agent_id: String,
    pub remote_addr: String,
    pub token: Option<MaskedString>,
    pub heartbeat_timeout: u64,
    pub retry_interval: u64,
    pub transport: TransportConfig,
    pub services: HashMap<String, ClientServiceConfig>,
    pub env1c: Option<EnvConfig>,
}

impl ClientConfig {
    pub fn from_str(s: &str) -> Result<Self> {
        let mut config: Self = toml::from_str(s).context("Failed to parse the config")?;
        Self::validate(&mut config)?;
        Ok(config)
    }

    pub fn from_file(path: &PathBuf) -> Result<Self> {
        let s: String = fs::read_to_string(path)
            .with_context(|| format!("Failed to read the config {:?}", path))?;
        let mut cfg = Self::from_str(&s).with_context(|| {
            "Configuration is invalid. Please refer to the configuration specification."
        })?;

        cfg.config_path = path.clone();
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
        let s = toml::to_string_pretty(self).context("Failed to serialize the config")?;
        fs::write(&self.config_path, s).context("Failed to write the config")?;
        Ok(())
    }

    pub fn load(cfg_name: &str, user_dir: bool) -> Result<Self> {
        let mut config_path = Self::get_config_dir(user_dir)?;
        config_path.push(cfg_name);
        if !config_path.exists() {
            let default_config = Self::default();
            let s = toml::to_string_pretty(&default_config)
                .context("Failed to serialize the default config")?;
            fs::write(&config_path, s).context("Failed to write the default config")?;
        }

        Self::from_file(&config_path)
    }

    pub fn validate(config: &mut ClientConfig) -> Result<()> {
        TransportConfig::validate(&config.transport, false)?;
        Ok(())
    }

    pub fn set(&mut self, key: &str, value: &str) -> Result<()> {
        match key {
            "remote_addr" => self.remote_addr = value.to_string(),
            "token" => self.token = Some(MaskedString::from(value)),
            "heartbeat_timeout" => {
                self.heartbeat_timeout = value.parse().context("Invalid heartbeat_timeout")?
            }
            "retry_interval" => {
                self.retry_interval = value.parse().context("Invalid retry_interval")?
            }
            _ => bail!("Unknown key: {}", key),
        }
        self.save()?;
        Ok(())
    }
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            agent_id: Uuid::new_v4().to_string(),
            config_path: PathBuf::new(),
            remote_addr: DEFAULT_SERVER.to_string(),
            token: None,
            heartbeat_timeout: DEFAULT_HEARTBEAT_TIMEOUT_SECS,
            retry_interval: DEFAULT_CLIENT_RETRY_INTERVAL_SECS,
            transport: TransportConfig::default(),
            services: HashMap::new(),
            env1c: None,
        }
    }
}
