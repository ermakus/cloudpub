use anyhow::{Context, Result};
use std::io;
use tokio::net::{TcpListener, UdpSocket};

pub async fn find_free_port() -> Result<u16> {
    // Bind a TCP listener to port 0 to find an available port
    loop {
        let tcp_listener = TcpListener::bind("127.0.0.1:0").await?;

        // Retrieve the port number assigned by the system
        let port = tcp_listener.local_addr()?.port();

        // Attempt to bind a UDP socket to the same port
        match UdpSocket::bind(("127.0.0.1", port)).await {
            Ok(_) => return Ok(port),
            Err(ref e) if e.kind() == io::ErrorKind::AddrInUse => {
                // Port already in use, try again
                continue;
            }
            Err(e) => Err(e).context("Failed to bind UDP socket")?,
        }
    }
}
