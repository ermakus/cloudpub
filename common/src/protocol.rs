use crate::config::MaskedString;
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
}

impl Display for Protocol {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            Protocol::Http => write!(f, "http"),
            Protocol::Https => write!(f, "https"),
            Protocol::Tcp => write!(f, "tcp"),
            Protocol::Udp => write!(f, "udp"),
            Protocol::OneC => write!(f, "1c"),
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
            _ => bail!("Invalid protocol: {}", s),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, Eq, Default)]
pub struct ClientEndpoint {
    pub local_proto: Protocol,
    pub local_addr: String,
    pub local_port: u16,
    pub nodelay: Option<bool>,
    pub description: Option<String>,
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
        if self.local_proto == Protocol::OneC {
            write!(f, "{}://{}", self.local_proto, self.local_addr)
        } else {
            write!(
                f,
                "{}://{}:{}",
                self.local_proto, self.local_addr, self.local_port
            )
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
}

impl Display for ServerEndpoint {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        write!(
            f,
            "{} -> {}://{}:{}",
            self.client, self.remote_proto, self.remote_addr, self.remote_port
        )
    }
}

impl PartialEq for ServerEndpoint {
    fn eq(&self, other: &Self) -> bool {
        self.client == other.client
    }
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub enum ErrorKind {
    AuthFailed,
    Fatal,
    HandshakeFailed,
    PermissionDenied,
    PublishFailed,
    ExecuteFailed,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct AgentInfo {
    pub agent_id: String,
    pub token: MaskedString,
    pub hostname: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct DataChannelInfo {
    pub agent_id: String,
    pub guid: String,
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
    let mut buf = [0u8; std::mem::size_of::<usize>()];
    conn.read_exact(&mut buf).await?;
    let len = usize::from_le_bytes(buf);
    let mut buf = vec![0u8; len];
    conn.read_exact(&mut buf).await?;
    Ok(serde_json::from_slice::<M>(&buf)?)
}

pub async fn write_message<T: AsyncWrite + Unpin, M: Serialize>(
    conn: &mut T,
    msg: &M,
) -> Result<()> {
    let json_msg = serde_json::to_string(msg)?;
    let mut buf = json_msg.len().to_le_bytes().to_vec();
    buf.append(&mut json_msg.as_bytes().to_vec());
    conn.write_all(&buf).await?;
    conn.flush().await?;
    Ok(())
}
