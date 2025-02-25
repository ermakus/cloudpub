use anyhow::{bail, Context, Result};
use clap::builder::TypedValueParser;
use clap::{Args, Subcommand};
use common::config::MaskedString;
use common::protocol::{
    Auth, ClientEndpoint, ErrorKind, Protocol, Role, ServerEndpoint, UpgradeInfo, ACL,
};
use serde::{Deserialize, Serialize};
use std::net::ToSocketAddrs;
use std::str::FromStr;

const ROLE_SEP: &str = ":";

#[derive(Subcommand, Debug, Serialize, Deserialize, Clone)]
pub enum Commands {
    #[clap(about = "Set value in the config")]
    Set(SetArgs),
    #[clap(about = "Get value from the config")]
    Get(GetArgs),
    #[clap(about = "Run all registered services")]
    Run,
    #[clap(about = "Stop client (used internally)", hide = true)]
    Stop,
    #[clap(about = "Break current operation (used internally)", hide = true)]
    Break,
    #[clap(about = "Register service in the config")]
    Register(PublishArgs),
    #[clap(about = "Register service and run it")]
    Publish(PublishArgs),
    #[clap(about = "Unregister service")]
    Unpublish(UnpublishArgs),
    #[clap(about = "List all registered services")]
    Ls,
    #[clap(about = "Clean all registered services")]
    Clean,
    #[clap(about = "Purge cache")]
    Purge,
}

#[derive(Args, Debug, Serialize, Deserialize, Clone)]
pub struct SetArgs {
    pub key: String,
    pub value: String,
}

#[derive(Args, Debug, Serialize, Deserialize, Clone)]
pub struct GetArgs {
    pub key: String,
}

#[derive(Args, Debug, Serialize, Deserialize, Clone, Eq)]
pub struct PublishArgs {
    #[clap(help = "Protocol to use")]
    pub protocol: Protocol,
    #[clap(help = "URL, socket address, port or file path")]
    pub address: String,
    #[clap(short = 'U', long = "username", help = "Username")]
    pub username: Option<String>,
    #[clap(short = 'P', long = "password", help = "Password")]
    pub password: Option<MaskedString>,
    #[clap(short, long, help = "Optional name of the service to publish")]
    pub name: Option<String>,
    #[clap(short, long, help = "Authentification type", default_value = "none")]
    pub auth: Option<Auth>,
    #[clap(short='A', long="acl", help = "Access list", value_parser = ACLParser)]
    pub acl: Vec<ACL>,
}

#[derive(Args, Debug, Serialize, Deserialize, Clone)]
pub struct UnpublishArgs {
    pub guid: String,
    #[clap(
        short,
        long,
        help = "Remove service from the config",
        default_value = "true"
    )]
    pub remove: bool,
}

impl PublishArgs {
    pub fn parse(&self) -> Result<ClientEndpoint> {
        let auth = self
            .auth
            .clone()
            .unwrap_or(if self.protocol == Protocol::WebDav {
                Auth::BASIC
            } else {
                Auth::NONE
            });
        if self.address.contains("://") {
            let url = url::Url::parse(&self.address).context("Неверный URL")?;
            let local_proto = Protocol::from_str(url.scheme()).context("Неверный протокол")?;
            let local_addr = url.host_str().unwrap().to_string();
            let local_port = url
                .port()
                .or_else(|| self.protocol.default_port())
                .context("Для этого прокола нужно указать порт")?;
            let mut local_path = url.path().to_string();
            if url.query().is_some() {
                local_path.push('?');
                local_path.push_str(url.query().unwrap());
            }
            let mut username = String::new();
            if !url.username().is_empty() {
                username = url.username().to_string();
            }
            let mut password = MaskedString(String::new());
            if let Some(pass) = url.password() {
                password = MaskedString(pass.to_string());
            }
            Ok(ClientEndpoint {
                description: self.name.clone(),
                local_proto,
                local_addr,
                local_port,
                local_path,
                nodelay: Some(true),
                auth,
                acl: self.acl.clone(),
                username,
                password,
            })
        } else {
            let (local_addr, local_port, local_path) = match self.protocol {
                Protocol::OneC | Protocol::Minecraft | Protocol::WebDav => {
                    (self.address.clone(), 0, String::new())
                }

                Protocol::Http
                | Protocol::Https
                | Protocol::Tcp
                | Protocol::Udp
                | Protocol::Rtsp => {
                    if let Ok(port) = self.address.parse::<u16>() {
                        ("localhost".to_string(), port, String::new())
                    } else {
                        let mut address = self.address.split('/').next().unwrap().to_string();
                        let path = self.address[address.len()..].to_string();

                        if let Some(port) = self.protocol.default_port() {
                            if !address.contains(":") {
                                address.push(':');
                                address.push_str(port.to_string().as_str());
                            }
                        }

                        match address.to_socket_addrs() {
                            Ok(mut addrs) => {
                                if addrs.next().is_some() {
                                    // Split original address to addr and port
                                    let parts = address.split(':').collect::<Vec<&str>>();
                                    (parts[0].to_string(), parts[1].parse::<u16>().unwrap(), path)
                                } else {
                                    bail!("Неправильно указан адрес: {}", address);
                                }
                            }
                            Err(err) => bail!("Неправильно указан адрес ({}): {}", address, err),
                        }
                    }
                }
            };

            Ok(ClientEndpoint {
                description: self.name.clone(),
                local_proto: self.protocol,
                local_addr,
                local_port,
                local_path,
                nodelay: Some(true),
                auth,
                acl: self.acl.clone(),
                username: self.username.clone().unwrap_or("".to_string()),
                password: self
                    .password
                    .clone()
                    .unwrap_or(MaskedString("".to_string())),
            })
        }
    }
}

impl PartialEq for PublishArgs {
    fn eq(&self, other: &Self) -> bool {
        self.protocol == other.protocol && self.address == other.address
    }
}

impl From<ClientEndpoint> for PublishArgs {
    fn from(val: ClientEndpoint) -> Self {
        PublishArgs {
            protocol: val.local_proto,
            address: match val.local_proto {
                Protocol::OneC | Protocol::Minecraft | Protocol::WebDav => val.local_addr.clone(),
                Protocol::Http
                | Protocol::Https
                | Protocol::Tcp
                | Protocol::Udp
                | Protocol::Rtsp => {
                    format!("{}:{}{}", val.local_addr, val.local_port, val.local_path)
                }
            },
            name: val.description,
            auth: Some(val.auth),
            acl: val.acl,
            username: if val.username.is_empty() {
                None
            } else {
                Some(val.username.clone())
            },
            password: if val.password.is_empty() {
                None
            } else {
                Some(val.password.clone())
            },
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ProgressInfo {
    pub message: String,
    pub template: String,
    pub current: u64,
    pub total: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[allow(clippy::large_enum_variant)]
pub enum CommandResult {
    Ok(String),
    Connecting,
    Connected,
    Disconnected,
    Progress(ProgressInfo),
    Published(ServerEndpoint),
    Unpublished(String),
    Removed(String),
    Error(ErrorKind, String),
    UpgradeAvailable(UpgradeInfo),
    Exit,
}

impl From<anyhow::Error> for CommandResult {
    fn from(err: anyhow::Error) -> Self {
        CommandResult::Error(ErrorKind::Fatal, format!("{:?}", err))
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct ACLParser;

impl TypedValueParser for ACLParser {
    type Value = ACL;

    fn parse_ref(
        &self,
        _cmd: &clap::Command,
        _arg: Option<&clap::Arg>,
        value: &std::ffi::OsStr,
    ) -> Result<Self::Value, clap::Error> {
        let value = value.to_string_lossy();
        let parts: Vec<&str> = value.split(ROLE_SEP).collect();
        if parts.len() != 2 {
            return Err(clap::Error::raw(
                clap::error::ErrorKind::ValueValidation,
                format!("Invalid ACL: {}", value),
            ));
        }
        let role = Role::from_str(parts[1]).map_err(|_err| {
            clap::Error::raw(
                clap::error::ErrorKind::ValueValidation,
                format!("Invalid role: {}", parts[1]),
            )
        })?;
        Ok(ACL {
            user: parts[0].to_string(),
            role,
        })
    }
}
