use crate::config::MaskedString;
use crate::utils::get_version_number;
use anyhow::{bail, Context, Result};
use bytes::{Bytes, BytesMut};
use clap::ValueEnum;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::fmt::{self, Display, Formatter};
use std::net::SocketAddr;
use std::str::FromStr;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tracing::trace;
use urlencoding::encode;

#[derive(ValueEnum, Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Default)]
pub enum Protocol {
    #[default]
    #[serde(rename = "http")]
    Http,
    #[serde(rename = "https")]
    Https,
    #[serde(rename = "tcp")]
    Tcp,
    #[serde(rename = "udp")]
    Udp,
    #[serde(rename = "1c")]
    #[clap(name = "1c")]
    OneC,
    #[serde(rename = "minecraft")]
    #[clap(name = "minecraft")]
    Minecraft,
    #[serde(rename = "webdav")]
    #[clap(name = "webdav")]
    WebDav,
    #[serde(rename = "rtsp")]
    #[clap(name = "rtsp")]
    Rtsp,
}

impl Protocol {
    pub fn default_port(&self) -> Option<u16> {
        match self {
            Protocol::Http => Some(80),
            Protocol::Https => Some(443),
            Protocol::Tcp => None,
            Protocol::Udp => None,
            Protocol::OneC => None,
            Protocol::Minecraft => Some(25565),
            Protocol::WebDav => None,
            Protocol::Rtsp => Some(554),
        }
    }
}

impl Display for Protocol {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            Protocol::Http => write!(f, "http"),
            Protocol::Https => write!(f, "https"),
            Protocol::Tcp => write!(f, "tcp"),
            Protocol::Udp => write!(f, "udp"),
            Protocol::OneC => write!(f, "1c"),
            Protocol::Minecraft => write!(f, "minecraft"),
            Protocol::WebDav => write!(f, "webdav"),
            Protocol::Rtsp => write!(f, "rtsp"),
        }
    }
}

impl FromStr for Protocol {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        match s {
            "http" => Ok(Protocol::Http),
            "https" => Ok(Protocol::Https),
            "tcp" => Ok(Protocol::Tcp),
            "udp" => Ok(Protocol::Udp),
            "1c" => Ok(Protocol::OneC),
            "minecraft" => Ok(Protocol::Minecraft),
            "webdav" => Ok(Protocol::WebDav),
            "rtsp" => Ok(Protocol::Rtsp),
            _ => bail!("Invalid protocol: {}", s),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, Default)]
pub enum Auth {
    #[default]
    NONE,
    BASIC,
    FORM,
}

impl FromStr for Auth {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        match s {
            "none" => Ok(Auth::NONE),
            "basic" => Ok(Auth::BASIC),
            "form" => Ok(Auth::FORM),
            _ => bail!("Invalid auth: {}", s),
        }
    }
}

impl Display for Auth {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            Auth::NONE => write!(f, "none"),
            Auth::BASIC => write!(f, "basic"),
            Auth::FORM => write!(f, "form"),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, Default)]
pub enum Role {
    #[default]
    NONE,
    ADMIN,
    READER,
    WRITER,
}

impl FromStr for Role {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        match s {
            "none" => Ok(Role::NONE),
            "admin" => Ok(Role::ADMIN),
            "reader" => Ok(Role::READER),
            "writer" => Ok(Role::WRITER),
            _ => bail!("Invalid access: {}", s),
        }
    }
}

impl Display for Role {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            Role::NONE => write!(f, "none"),
            Role::ADMIN => write!(f, "admin"),
            Role::READER => write!(f, "reader"),
            Role::WRITER => write!(f, "writer"),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, Default)]
pub struct ACL {
    pub user: String,
    pub role: Role,
}

#[derive(Debug, Serialize, Deserialize, Clone, Eq, Default)]
pub struct ClientEndpoint {
    pub local_proto: Protocol,
    pub local_addr: String,
    pub local_port: u16,
    #[serde(default)]
    pub local_path: String,
    pub nodelay: Option<bool>,
    pub description: Option<String>,
    #[serde(default)]
    pub auth: Auth,
    #[serde(default)]
    pub acl: Vec<ACL>,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: MaskedString,
}

impl PartialEq for ClientEndpoint {
    fn eq(&self, other: &Self) -> bool {
        self.local_proto == other.local_proto
            && self.local_addr == other.local_addr
            && self.local_port == other.local_port
    }
}

impl Display for ClientEndpoint {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        if let Some(name) = self.description.as_ref() {
            write!(f, "[{}] ", name)?;
        }
        write!(f, "{}", self.as_url())
    }
}

impl ClientEndpoint {
    pub fn credentials(&self) -> String {
        let mut s = String::new();
        if !self.username.is_empty() {
            s.push_str(&encode(&self.username));
        }
        if !self.password.is_empty() {
            s.push(':');
            s.push_str(&encode(&self.password.0));
        }
        if !s.is_empty() {
            s.push('@');
        }
        s
    }

    pub fn as_url(&self) -> String {
        match self.local_proto {
            Protocol::OneC | Protocol::Minecraft | Protocol::WebDav => {
                let credentials = self.credentials();
                format!("{}://{}{}", self.local_proto, credentials, &self.local_addr)
            }
            Protocol::Http | Protocol::Https | Protocol::Tcp | Protocol::Udp | Protocol::Rtsp => {
                let credentials = self.credentials();
                format!(
                    "{}://{}{}:{}{}",
                    self.local_proto,
                    credentials,
                    self.local_addr,
                    self.local_port,
                    self.local_path
                )
            }
        }
    }
}

#[derive(Deserialize, Serialize, Debug, Clone, Eq)]
pub struct ServerEndpoint {
    pub status: Option<String>,
    pub guid: String,
    pub remote_proto: Protocol,
    pub remote_addr: String,
    pub remote_port: u16,
    pub client: ClientEndpoint,
    #[serde(skip)]
    pub bind_addr: String,
    #[serde(skip)]
    pub id: Option<i64>,
}

impl Display for ServerEndpoint {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        write!(
            f,
            "{} -> {}://{}{}:{}{}",
            self.client,
            self.remote_proto,
            self.client.credentials(),
            self.remote_addr,
            self.remote_port,
            self.client.local_path
        )
    }
}

impl PartialEq for ServerEndpoint {
    fn eq(&self, other: &Self) -> bool {
        self.client == other.client
    }
}

#[derive(Deserialize, Serialize, Debug, Clone, PartialEq, Eq)]
pub enum ErrorKind {
    AuthFailed,
    Fatal,
    HandshakeFailed,
    PermissionDenied,
    PublishFailed,
    ExecuteFailed,
}

fn default_version() -> String {
    "1.0.x".to_string()
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct AgentInfo {
    pub agent_id: String,
    pub token: MaskedString,
    pub hostname: String,
    // Next fields should have default values
    #[serde(default = "default_version")]
    pub version: String,
    #[serde(default)]
    pub gui: bool,
    #[serde(default)]
    pub platform: String,
    #[serde(default)]
    pub hwid: String,
    #[serde(default)]
    pub server_host_and_port: String,
}

impl AgentInfo {
    pub fn is_support_upgrade(&self) -> bool {
        get_version_number(&self.version) >= get_version_number("1.1.0")
    }

    pub fn is_support_pong(&self) -> bool {
        get_version_number(&self.version) >= get_version_number("1.2.104")
    }

    pub fn is_support_redirect(&self) -> bool {
        get_version_number(&self.version) >= get_version_number("1.3.2")
    }
}

impl Display for AgentInfo {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        write!(f, "{}", self.hostname)
    }
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct DataChannelInfo {
    pub agent_id: String,
    pub guid: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct UpgradeInfo {
    pub version: String,
    pub url: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub enum Message {
    AgentHello(AgentInfo),
    AgentAck,
    EndpointStart(ClientEndpoint),
    EndpointAck(ServerEndpoint),
    EndpointStop(String),
    DataChannelHello(DataChannelInfo),
    CreateDataChannel(ServerEndpoint),
    HeartBeat,
    StartForwardTcp,
    StartForwardUdp,
    Error(ErrorKind, String),
    UpgradeAvailable(UpgradeInfo),
    Redirect(String),
}

type UdpPacketLen = u16; // `u16` should be enough for any practical UDP traffic on the Internet
                         //
#[derive(Deserialize, Serialize, Debug)]
struct UdpHeader {
    from: SocketAddr,
    len: UdpPacketLen,
}

#[derive(Debug)]
pub struct UdpTraffic {
    pub from: SocketAddr,
    pub data: Bytes,
}

impl UdpTraffic {
    pub async fn write<T: AsyncWrite + Unpin>(&self, writer: &mut T) -> Result<()> {
        let hdr = UdpHeader {
            from: self.from,
            len: self.data.len() as UdpPacketLen,
        };

        let v = bincode::serialize(&hdr).unwrap();

        trace!("Write {:?} of length {}", hdr, v.len());
        writer.write_u8(v.len() as u8).await?;
        writer.write_all(&v).await?;

        writer.write_all(&self.data).await?;

        Ok(())
    }

    #[allow(dead_code)]
    pub async fn write_slice<T: AsyncWrite + Unpin>(
        writer: &mut T,
        from: SocketAddr,
        data: &[u8],
    ) -> Result<()> {
        let hdr = UdpHeader {
            from,
            len: data.len() as UdpPacketLen,
        };

        let v = bincode::serialize(&hdr).unwrap();

        trace!("Write {:?} of length {}", hdr, v.len());
        writer.write_u8(v.len() as u8).await?;
        writer.write_all(&v).await?;

        writer.write_all(data).await?;

        Ok(())
    }

    pub async fn read<T: AsyncRead + Unpin>(reader: &mut T, hdr_len: u8) -> Result<UdpTraffic> {
        let mut buf = vec![0; hdr_len as usize];
        reader
            .read_exact(&mut buf)
            .await
            .with_context(|| "Failed to read udp header")?;

        let hdr: UdpHeader =
            bincode::deserialize(&buf).with_context(|| "Failed to deserialize UdpHeader")?;

        trace!("hdr {:?}", hdr);

        let mut data = BytesMut::new();
        data.resize(hdr.len as usize, 0);
        reader.read_exact(&mut data).await?;

        Ok(UdpTraffic {
            from: hdr.from,
            data: data.freeze(),
        })
    }
}

pub async fn read_message<T: AsyncRead + Unpin, M: DeserializeOwned>(conn: &mut T) -> Result<M> {
    let mut buf = [0u8; std::mem::size_of::<u64>()];
    conn.read_exact(&mut buf).await?;
    let len = u64::from_le_bytes(buf) as usize;
    if !(1..=1024 * 1024 * 10).contains(&len) {
        bail!("Invalid message length: {}", len);
    }
    let mut buf = vec![0u8; len];
    conn.read_exact(&mut buf).await?;
    Ok(serde_json::from_slice::<M>(&buf)?)
}

pub async fn write_message<T: AsyncWrite + Unpin, M: Serialize>(
    conn: &mut T,
    msg: &M,
) -> Result<()> {
    let json_msg = serde_json::to_string(msg)?;
    let mut buf = (json_msg.len() as u64).to_le_bytes().to_vec();
    buf.append(&mut json_msg.as_bytes().to_vec());
    conn.write_all(&buf).await?;
    conn.flush().await?;
    Ok(())
}
