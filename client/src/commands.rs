use anyhow::{bail, Result};
use clap::{Args, Subcommand};
use common::protocol::{ClientEndpoint, ErrorKind, Protocol, ServerEndpoint};
use serde::{Deserialize, Serialize};
use std::fmt::{self, Display, Formatter};
use std::net::ToSocketAddrs;

#[derive(Subcommand, Debug, Serialize, Deserialize, Clone)]
pub enum Commands {
    Set(SetArgs),
    Get(GetArgs),
    Run,
    Stop,
    Break,
    Publish(PublishArgs),
    Unpublish(UnpublishArgs),
    Ls,
    Cleanup,
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
        if self.protocol == Protocol::OneC {
            self.address.clone()
        } else {
            self.address
                .split(':')
                .next()
                .unwrap_or("localhost")
                .to_string()
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
        if self.protocol == Protocol::OneC {
            return Ok(());
        }

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
        }
    }
}

impl Into<PublishArgs> for ClientEndpoint {
    fn into(self) -> PublishArgs {
        PublishArgs {
            protocol: self.local_proto,
            address: if self.local_proto == Protocol::OneC {
                self.local_addr.clone()
            } else {
                format!("{}:{}", self.local_addr, self.local_port)
            },
            name: self.description,
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
    Exit,
}

impl Display for CommandResult {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            CommandResult::Ok(msg) => write!(f, "{}", msg),
            CommandResult::Error(kind, msg) => write!(f, "{:?} error: {}", kind, msg),
            CommandResult::Published(endpoint) => write!(f, "Service published: {}", endpoint),
            CommandResult::Unpublished(guid) => write!(f, "Service unpublished: {}", guid),
            CommandResult::Removed(guid) => write!(f, "Service removed: {}", guid),
            CommandResult::Connecting => write!(f, "Connecting"),
            CommandResult::Connected => write!(f, "Connected"),
            CommandResult::Disconnected => write!(f, "Disconnected"),
            CommandResult::Exit => write!(f, "Exiting"),
            CommandResult::Progress(info) => {
                write!(f, "Progress: {:?}", info)
            }
        }
    }
}

impl From<anyhow::Error> for CommandResult {
    fn from(err: anyhow::Error) -> Self {
        CommandResult::Error(ErrorKind::Fatal, format!("{:?}", err))
    }
}
