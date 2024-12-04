use anyhow::{bail, Result};
use clap::builder::TypedValueParser;
use clap::{Args, Subcommand};
use common::protocol::{
    Auth, ClientEndpoint, ErrorKind, Protocol, Role, ServerEndpoint, UpgradeInfo, ACL,
};
use serde::{Deserialize, Serialize};
use std::net::ToSocketAddrs;
use std::str::FromStr;

const ROLE_SEP: &str = ":";

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
            auth: self.auth.unwrap_or(if self.protocol == Protocol::WebDav {
                Auth::BASIC
            } else {
                Auth::NONE
            }),
            acl: self.acl,
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
            auth: Some(self.auth),
            acl: self.acl,
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
