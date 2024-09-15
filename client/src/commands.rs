use anyhow::{bail, Result};
use clap::{Args, Subcommand, ValueEnum};
use common::protocol::{ClientEndpoint, ErrorKind, Protocol, ServerEndpoint};
use serde::{Deserialize, Serialize};
use std::fmt::{self, Display, Formatter};
use std::net::ToSocketAddrs;
use std::path::{Path, PathBuf};

#[derive(Subcommand, Debug, Serialize, Deserialize, Clone)]
pub enum Commands {
    Set(SetArgs),
    Get(GetArgs),
    Run,
    Stop,
    Publish(PublishArgs),
    Unpublish(PublishArgs),
    Ls,
}

#[derive(ValueEnum, Clone, Default, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum EnvPlatform {
    #[default]
    X64,
    X86,
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

#[derive(Args, Debug, Serialize, Deserialize, Clone, Default)]
pub struct EnvArgs {
    #[clap(long, help = "Optional path to the service home directory")]
    pub home: Option<PathBuf>,
    #[clap(long, help = "Service platform")]
    pub platform: Option<EnvPlatform>,
}

#[derive(Args, Debug, Serialize, Deserialize, Clone, Eq)]
pub struct PublishArgs {
    #[clap(help = "Protocol to use (http, https, udp, tcp, 1c)")]
    pub protocol: Protocol,
    #[clap(help = "Socket address, port or file path")]
    pub address: String,
    #[clap(short, long, help = "Optional name of the service to publish")]
    pub name: Option<String>,
    #[clap(name = "home", long, help = "Optional path to the 1C home directory")]
    pub home: Option<PathBuf>,
    #[clap(long, help = "Optional platform type (x64 or x86)")]
    pub platform: Option<EnvPlatform>,
}

impl PublishArgs {
    pub fn address(&self) -> String {
        self.address
            .split(':')
            .next()
            .unwrap_or("localhost")
            .to_string()
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
            if Path::new(&self.address).exists() {
                self.address = format!("File=\"{}\"", self.address);
            }
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
        if self.protocol == Protocol::OneC {
            ClientEndpoint {
                description: self.name.clone(),
                local_proto: Protocol::Http,
                local_addr: "127.0.0.1".to_string(),
                local_port: 5050,
                nodelay: Some(true),
            }
        } else {
            ClientEndpoint {
                description: self.name.clone(),
                local_proto: self.protocol,
                local_addr: self.address(),
                local_port: self.port(),
                nodelay: Some(true),
            }
        }
    }
}

impl Into<PublishArgs> for ClientEndpoint {
    fn into(self) -> PublishArgs {
        PublishArgs {
            protocol: self.local_proto,
            address: format!("{}:{}", self.local_addr, self.local_port),
            name: self.description,
            home: None,
            platform: None,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum CommandResult {
    Ok(String),
    Connected,
    Disconnected,
    Published(ServerEndpoint),
    Error(ErrorKind, String),
    Exit,
}

impl Display for CommandResult {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            CommandResult::Ok(msg) => write!(f, "{}", msg),
            CommandResult::Error(kind, msg) => write!(f, "{:?} error: {}", kind, msg),
            CommandResult::Published(endpoint) => write!(f, "Service published: {}", endpoint),
            CommandResult::Connected => write!(f, "Connected"),
            CommandResult::Disconnected => write!(f, "Disconnected"),
            CommandResult::Exit => write!(f, "Exiting"),
        }
    }
}

impl From<anyhow::Error> for CommandResult {
    fn from(err: anyhow::Error) -> Self {
        CommandResult::Error(ErrorKind::Fatal, format!("{:?}", err))
    }
}
