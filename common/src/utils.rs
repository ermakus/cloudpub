use anyhow::{anyhow, Context, Result};
use backoff::backoff::Backoff;
use backoff::Notify;
use std::future::Future;
use std::io;
use std::net::SocketAddr;
use tokio::net::{lookup_host, TcpListener, TcpSocket, ToSocketAddrs, UdpSocket};
use tokio::sync::watch;
use tracing::debug;

use crate::protocol::ServerEndpoint;

pub async fn to_socket_addr<A: ToSocketAddrs>(addr: A) -> Result<std::net::SocketAddr> {
    lookup_host(addr)
        .await?
        .next()
        .ok_or_else(|| anyhow!("Failed to lookup the host"))
}

pub fn host_port_pair(s: &str) -> Result<(&str, u16)> {
    let semi = s.rfind(':').expect("missing semicolon");
    Ok((&s[..semi], s[semi + 1..].parse()?))
}

/// Create a UDP socket and connect to `addr`
pub async fn udp_connect<A: ToSocketAddrs>(addr: A) -> Result<UdpSocket> {
    let addr = to_socket_addr(addr).await?;

    let bind_addr = match addr {
        std::net::SocketAddr::V4(_) => "0.0.0.0:0",
        std::net::SocketAddr::V6(_) => ":::0",
    };

    let s = UdpSocket::bind(bind_addr).await?;
    s.connect(addr).await?;
    Ok(s)
}

// Wrapper of retry_notify
pub async fn retry_notify_with_deadline<I, E, Fn, Fut, B, N>(
    backoff: B,
    operation: Fn,
    notify: N,
    deadline: &mut watch::Receiver<bool>,
) -> Result<I>
where
    E: std::error::Error + Send + Sync + 'static,
    B: Backoff,
    Fn: FnMut() -> Fut,
    Fut: Future<Output = std::result::Result<I, backoff::Error<E>>>,
    N: Notify<E>,
{
    tokio::select! {
        v = backoff::future::retry_notify(backoff, operation, notify) => {
            v.map_err(anyhow::Error::new)
        }
        _ = deadline.changed() => {
            Err(anyhow!("shutdown"))
        }
    }
}

pub async fn find_free_tcp_port() -> Result<u16> {
    let tcp_listener = TcpListener::bind("0.0.0.0:0").await?;
    let port = tcp_listener.local_addr()?.port();
    Ok(port)
}

pub async fn find_free_udp_port() -> Result<u16> {
    let udp_listener = UdpSocket::bind("0.0.0.0:0").await?;
    let port = udp_listener.local_addr()?.port();
    Ok(port)
}

pub async fn free_port_for_bind(endpoint: &mut ServerEndpoint) -> Result<()> {
    let client = endpoint.client.as_mut().unwrap();
    client.local_port = find_free_tcp_port().await? as u32;
    client.local_addr = "localhost".to_string();
    Ok(())
}

pub async fn is_udp_port_available(bind_addr: &str, port: u16) -> Result<bool> {
    match UdpSocket::bind((bind_addr, port)).await {
        Ok(_) => Ok(true),
        Err(ref e) if e.kind() == io::ErrorKind::AddrInUse => Ok(false),
        Err(e) => Err(e).context("Failed to check UDP port")?,
    }
}

pub async fn is_tcp_port_available(bind_addr: &str, port: u16) -> Result<bool> {
    let tcp_socket = TcpSocket::new_v4()?;
    tcp_socket.set_reuseaddr(true).unwrap();
    let bind_addr: SocketAddr = format!("{}:{}", bind_addr, port).parse().unwrap();
    debug!("Check port: {}", bind_addr);
    match tcp_socket.bind(bind_addr) {
        Ok(_) => Ok(true),
        Err(ref e) if e.kind() == io::ErrorKind::AddrInUse => Ok(false),
        Err(e) => Err(e).context("Failed to check TCP port")?,
    }
}

pub fn get_version_number(version: &str) -> i64 {
    let mut n = 0;
    for x in version.split(".") {
        n = n * 10000 + x.parse::<i64>().unwrap_or(0);
    }
    n
}

pub fn get_platform() -> String {
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    let platform = "linux-x86_64".to_string();
    #[cfg(all(target_os = "linux", target_arch = "arm"))]
    let platform = "linux-armv7".to_string();
    #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
    let platform = "linux-aarch64".to_string();
    #[cfg(all(target_os = "linux", target_arch = "x86"))]
    let platform = "linux-i686".to_string();
    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
    let platform = "windows-x86_64".to_string();
    #[cfg(all(target_os = "windows", target_arch = "x86"))]
    let platform = "windows-i686".to_string();
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    let platform = "macos-x86_64".to_string();
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    let platform = "macos-aarch64".to_string();
    platform
}

pub fn split_host_port(host_and_port: &str, default_port: u16) -> (String, u16) {
    let parts = host_and_port.split(':');
    let parts: Vec<&str> = parts.collect();
    let host = parts[0].to_string();
    let port = if parts.len() > 1 {
        parts[1].parse::<u16>().unwrap_or(default_port)
    } else {
        default_port
    };
    (host, port)
}
