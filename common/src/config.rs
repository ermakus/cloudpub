use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::fmt::{Debug, Formatter};
use std::ops::Deref;
use url::Url;

use crate::constants::{DEFAULT_KEEPALIVE_INTERVAL, DEFAULT_KEEPALIVE_SECS, DEFAULT_NODELAY};

pub use crate::protocol::ServiceType;

/// String with Debug implementation that emits "MASKED"
/// Used to mask sensitive strings when logging
#[derive(Serialize, Deserialize, Default, PartialEq, Eq, Clone)]
pub struct MaskedString(String);

impl Debug for MaskedString {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::result::Result<(), std::fmt::Error> {
        if self.0.is_empty() {
            return f.write_str("EMPTY");
        } else {
            f.write_str("MASKED")
        }
    }
}

impl Deref for MaskedString {
    type Target = str;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl From<&str> for MaskedString {
    fn from(s: &str) -> MaskedString {
        MaskedString(String::from(s))
    }
}

#[derive(Debug, Serialize, Deserialize, Copy, Clone, PartialEq, Eq, Default)]
pub enum TransportType {
    #[serde(rename = "websocket")]
    #[default]
    Websocket,
    #[serde(rename = "tcp")]
    Tcp,
    #[cfg(feature = "rustls")]
    #[serde(rename = "tls")]
    Tls,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct TlsConfig {
    pub hostname: Option<String>,
    pub trusted_root: Option<String>,
    pub pkcs12: Option<String>,
    pub pkcs12_password: Option<MaskedString>,
    pub danger_ignore_certificate_verification: Option<bool>,
}

impl Default for TlsConfig {
    fn default() -> Self {
        Self {
            hostname: None,
            trusted_root: None,
            pkcs12: None,
            pkcs12_password: None,
            danger_ignore_certificate_verification: None,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct WebsocketConfig {
    pub tls: bool,
}

impl Default for WebsocketConfig {
    fn default() -> Self {
        Self { tls: true }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct TcpConfig {
    pub nodelay: bool,
    pub keepalive_secs: u64,
    pub keepalive_interval: u64,
    pub proxy: Option<Url>,
}

impl Default for TcpConfig {
    fn default() -> Self {
        Self {
            nodelay: DEFAULT_NODELAY,
            keepalive_secs: DEFAULT_KEEPALIVE_SECS,
            keepalive_interval: DEFAULT_KEEPALIVE_INTERVAL,
            proxy: None,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq, Clone)]
#[serde(deny_unknown_fields)]
pub struct TransportConfig {
    #[serde(rename = "type")]
    pub transport_type: TransportType,
    pub tcp: TcpConfig,
    pub tls: Option<TlsConfig>,
    pub websocket: Option<WebsocketConfig>,
}

impl Default for TransportConfig {
    fn default() -> Self {
        Self {
            transport_type: TransportType::Websocket,
            tcp: TcpConfig::default(),
            tls: TlsConfig::default().into(),
            websocket: WebsocketConfig::default().into(),
        }
    }
}

impl TransportConfig {
    pub fn validate(config: &TransportConfig, is_server: bool) -> Result<()> {
        config
            .tcp
            .proxy
            .as_ref()
            .map_or(Ok(()), |u| match u.scheme() {
                "socks5" => Ok(()),
                "http" => Ok(()),
                _ => Err(anyhow!(format!("Unknown proxy scheme: {}", u.scheme()))),
            })?;
        match config.transport_type {
            TransportType::Tcp => Ok(()),
            #[cfg(feature = "rustls")]
            TransportType::Tls => {
                let tls_config = config
                    .tls
                    .as_ref()
                    .ok_or_else(|| anyhow!("Missing TLS configuration"))?;
                if is_server {
                    tls_config
                        .pkcs12
                        .as_ref()
                        .and(tls_config.pkcs12_password.as_ref())
                        .ok_or_else(|| anyhow!("Missing `pkcs12` or `pkcs12_password`"))?;
                }
                Ok(())
            }
            TransportType::Websocket => Ok(()),
        }
    }
}
