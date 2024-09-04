use anyhow::{bail, Result};
use clap::{Args, Subcommand, ValueEnum};
use common::protocol::{ErrorKind, ServerEndpoint, ServiceType};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt::{self, Display, Formatter};
use std::net::ToSocketAddrs;
use std::path::{Path, PathBuf};

#[derive(Subcommand, Debug, Serialize, Deserialize, Clone)]
pub enum Commands {
    Set(SetArgs),
    Run,
    Publish(PublishArgs),
    Unpublish(UnpublishArgs),
    Ls,
    #[clap(name = "setup-1c")]
    Setup1C(EnvArgs),
    #[clap(name = "cleanup-1c")]
    Cleanup1C,
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
pub struct EnvArgs {
    #[clap(long, help = "Optional path to the service home directory")]
    pub home: Option<PathBuf>,
    #[clap(long, help = "Service platform")]
    pub platform: Option<EnvPlatform>,
}

#[derive(Args, Debug, Serialize, Deserialize, Clone)]
pub struct PublishArgs {
    #[clap(short, long, help = "Optional name of the service to publish")]
    pub name: Option<String>,
    pub protocol: ServiceType,
    #[clap(help = "Socket address, port or file path", value_parser=validate_socket_address)]
    pub address: String,
}

#[derive(Args, Debug, Serialize, Deserialize, Clone)]
pub struct UnpublishArgs {
    #[clap(help = "ID of service to unpublish")]
    pub id: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum CommandResult {
    Ok(String),
    Connected,
    Disconnected,
    Published(ServerEndpoint),
    ServiceList(HashMap<String, ServerEndpoint>),
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
            CommandResult::ServiceList(list) => {
                writeln!(f, "Service list:")?;
                for (name, endpoint) in list {
                    writeln!(f, "{}: {}", name, endpoint)?;
                }
                Ok(())
            }
        }
    }
}

impl From<anyhow::Error> for CommandResult {
    fn from(err: anyhow::Error) -> Self {
        CommandResult::Error(ErrorKind::Fatal, format!("{:?}", err))
    }
}

pub fn validate_socket_address(input: &str) -> Result<String> {
    if Path::new(input).exists() {
        return Ok(input.to_string());
    }
    let addr_with_port: String;
    if input.contains(':') {
        addr_with_port = input.to_string();
    } else {
        addr_with_port = format!("localhost:{}", input);
    }

    match addr_with_port.to_socket_addrs() {
        Ok(mut addrs) => {
            if let Some(_addr) = addrs.next() {
                Ok(addr_with_port)
            } else {
                bail!("Invalid socket address: {}", addr_with_port);
            }
        }
        Err(err) => bail!("Invalid socket address: {}", err),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_validate_socket_address() {
        // Valid input
        assert!(validate_socket_address("127.0.0.1:8000").unwrap() == "127.0.0.1:8000".to_string());
        assert!(validate_socket_address("8000").unwrap() == "localhost:8000".to_string());
        // Invalid inputs
        assert!(validate_socket_address("127.0.0.1").is_err());
        assert!(validate_socket_address("127.0.0.1:").is_err());
        assert!(validate_socket_address("127.0.0.1:port").is_err());
        assert!(validate_socket_address("127.0.0.1:90000").is_err());
    }
}
