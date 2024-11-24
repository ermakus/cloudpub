use anyhow::{Context, Result};
use std::io;
use std::net::SocketAddr;
use tokio::net::{TcpListener, TcpSocket, UdpSocket};

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

pub async fn is_udp_port_available(bind_addr: &str, port: u16) -> Result<bool> {
    match UdpSocket::bind((bind_addr, port)).await {
        Ok(_) => return Ok(true),
        Err(ref e) if e.kind() == io::ErrorKind::AddrInUse => Ok(false),
        Err(e) => Err(e).context("Failed to check UDP port")?,
    }
}

pub async fn is_tcp_port_available(bind_addr: &str, port: u16) -> Result<bool> {
    let tcp_socket = TcpSocket::new_v4()?;
    let bind_addr: SocketAddr = format!("{}:{}", bind_addr, port).parse().unwrap();
    match tcp_socket.bind(bind_addr) {
        Ok(_) => return Ok(true),
        Err(ref e) if e.kind() == io::ErrorKind::AddrInUse => Ok(false),
        Err(e) => Err(e).context("Failed to check UDP port")?,
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
