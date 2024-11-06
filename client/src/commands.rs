use anyhow::{bail, Result};
use clap::{Args, Subcommand};
use common::protocol::{
    Access, ClientEndpoint, ErrorKind, Permission, Protocol, ServerEndpoint, UpgradeInfo,
};
use serde::{Deserialize, Serialize};
use std::net::ToSocketAddrs;

const ACCESS_SEP: &str = ":";

#[derive(Subcommand, Debug, Serialize, Deserialize, Clone)]
pub enum Commands {
    Set(SetArgs),
    Get(GetArgs),
    Run,
    Stop,
    Break,
    Register(PublishArgs),
    Publish(PublishArgs),
    Unpublish(UnpublishArgs),
    Ls,
    Clean,
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
    #[clap(help = "Protocol to use (http, https, udp, tcp, 1c)")]
    pub protocol: Protocol,
    #[clap(help = "Socket address, port or file path")]
    pub address: String,
    #[clap(short, long, help = "Optional name of the service to publish")]
    pub name: Option<String>,
    #[clap(short, long)]
    pub access: Option<Vec<String>>,
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
    pub fn address(&self) -> String {
        match self.protocol {
            Protocol::OneC | Protocol::Minecraft | Protocol::WebDav => self.address.clone(),
            Protocol::Http | Protocol::Https | Protocol::Tcp | Protocol::Udp => {
                self.address.split(':').next().unwrap().to_string()
            }
        }
    }
    pub fn port(&self) -> u16 {
        self.address
            .split(':')
            .last()
            .unwrap_or("0")
            .parse()
            .unwrap_or(0)
    }

    pub fn populate(&mut self) -> Result<()> {
        parse_accesses(self.access.clone())?;
        match self.protocol {
            Protocol::OneC | Protocol::Minecraft | Protocol::WebDav => Ok(()),

            Protocol::Http | Protocol::Https | Protocol::Tcp | Protocol::Udp => {
                if !self.address.contains(':') {
                    self.address = format!("localhost:{}", self.address);
                }

                match self.address.to_socket_addrs() {
                    Ok(mut addrs) => {
                        if let Some(_addr) = addrs.next() {
                            Ok(())
                        } else {
                            bail!("Invalid socket address: {}", self.address);
                        }
                    }
                    Err(err) => bail!("Invalid socket address: {}", err),
                }
            }
        }
    }
}

impl PartialEq for PublishArgs {
    fn eq(&self, other: &Self) -> bool {
        self.protocol == other.protocol && self.address == other.address
    }
}

impl Into<ClientEndpoint> for PublishArgs {
    fn into(self) -> ClientEndpoint {
        ClientEndpoint {
            description: self.name.clone(),
            local_proto: self.protocol,
            local_addr: self.address(),
            local_port: self.port(),
            nodelay: Some(true),
            access: parse_accesses(self.access).unwrap_or_default(),
        }
    }
}

impl Into<PublishArgs> for ClientEndpoint {
    fn into(self) -> PublishArgs {
        PublishArgs {
            protocol: self.local_proto,
            address: match self.local_proto {
                Protocol::OneC | Protocol::Minecraft | Protocol::WebDav => self.local_addr.clone(),
                Protocol::Http | Protocol::Https | Protocol::Tcp | Protocol::Udp => {
                    format!("{}:{}", self.local_addr, self.local_port)
                }
            },
            name: self.description,
            access: Some(
                self.access
                    .iter()
                    .map(|p| format!("{}{}{}", p.user, ACCESS_SEP, p.access))
                    .collect(),
            ),
        }
    }
}

fn parse_access(s: &str) -> Result<Permission> {
    let sv: Vec<&str> = s.split(ACCESS_SEP).collect();
    if sv.len() != 2 {
        bail!(format!(
            "Неверный парамер доступа ({}). Ожидается формат [email|guest|owner]:[read|write]",
            s
        ));
    }

    if let Ok(access) = sv[1].parse::<Access>() {
        return Ok(Permission {
            user: sv[0].to_string(),
            access,
        });
    } else {
        bail!(format!(
            "Неверное значение доступа: {}. Ожидается read или write",
            sv[1]
        ));
    }
}

fn parse_accesses(s: Option<Vec<String>>) -> Result<Vec<Permission>> {
    match s {
        Some(s) => s.into_iter().map(|s| parse_access(&s)).collect(),
        None => Ok(vec![]),
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
