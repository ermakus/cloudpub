use crate::config::{TcpConfig, TransportConfig};

use super::{AddrMaybeCached, SocketOpts, Transport};
use anyhow::Result;
use async_http_proxy::{http_connect_tokio, http_connect_tokio_with_basic_auth};
use async_trait::async_trait;
use socket2::{SockRef, TcpKeepalive};
use std::str::FromStr;
use std::time::Duration;
use tokio::net::TcpStream;
pub use tokio_unix_tcp::{Listener, NamedSocketAddr, SocketAddr, Stream};
use tracing::trace;
use url::Url;

#[derive(Debug)]
pub struct TcpTransport {
    socket_opts: SocketOpts,
    cfg: TcpConfig,
}

#[async_trait]
impl Transport for TcpTransport {
    type Acceptor = Listener;
    type Stream = Stream;
    type RawStream = Stream;

    fn new(config: &TransportConfig) -> Result<Self> {
        Ok(TcpTransport {
            socket_opts: SocketOpts::from_cfg(&config.tcp),
            cfg: config.tcp.clone(),
        })
    }

    fn hint(conn: &Self::Stream, opt: SocketOpts) {
        opt.apply(conn);
    }

    async fn bind(&self, addr: NamedSocketAddr) -> Result<Self::Acceptor> {
        Ok(Listener::bind(&addr).await?)
    }

    async fn accept(&self, a: &Self::Acceptor) -> Result<(Self::RawStream, SocketAddr)> {
        let (s, addr) = a.accept().await?;
        self.socket_opts.apply(&s);
        Ok((s, addr))
    }

    async fn handshake(&self, conn: Self::RawStream) -> Result<Self::Stream> {
        Ok(conn)
    }

    async fn connect(&self, addr: &AddrMaybeCached) -> Result<Self::Stream> {
        let s = tcp_connect_with_proxy(addr, self.cfg.proxy.as_ref()).await?;
        self.socket_opts.apply(&s);
        Ok(s)
    }
}

// Tokio hesitates to expose this option...So we have to do it on our own :(
// The good news is that using socket2 it can be easily done, without losing portability.
// See https://github.com/tokio-rs/tokio/issues/3082
pub fn try_set_tcp_keepalive(
    conn: &TcpStream,
    keepalive_duration: Duration,
    keepalive_interval: Duration,
) -> Result<()> {
    let s = SockRef::from(conn);
    let keepalive = TcpKeepalive::new()
        .with_time(keepalive_duration)
        .with_interval(keepalive_interval);

    trace!(
        "Set TCP keepalive {:?} {:?}",
        keepalive_duration,
        keepalive_interval
    );

    Ok(s.set_tcp_keepalive(&keepalive)?)
}

pub fn host_port_pair(s: &str) -> Result<(&str, u16)> {
    let semi = s.rfind(':').expect("missing semicolon");
    Ok((&s[..semi], s[semi + 1..].parse()?))
}

/// Create a TcpStream using a proxy
/// e.g. socks5://user:pass@127.0.0.1:1080 http://127.0.0.1:8080
pub async fn tcp_connect_with_proxy(addr: &AddrMaybeCached, proxy: Option<&Url>) -> Result<Stream> {
    if let Some(url) = proxy {
        let addr = &addr.addr;
        let mut s = TcpStream::connect((
            url.host_str().expect("proxy url should have host field"),
            url.port().expect("proxy url should have port field"),
        ))
        .await?;

        let auth = if !url.username().is_empty() || url.password().is_some() {
            Some(async_socks5::Auth {
                username: url.username().into(),
                password: url.password().unwrap_or("").into(),
            })
        } else {
            None
        };
        match url.scheme() {
            "socks5" => {
                async_socks5::connect(&mut s, host_port_pair(addr)?, auth).await?;
            }
            "http" => {
                let (host, port) = host_port_pair(addr)?;
                match auth {
                    Some(auth) => {
                        http_connect_tokio_with_basic_auth(
                            &mut s,
                            host,
                            port,
                            &auth.username,
                            &auth.password,
                        )
                        .await?
                    }
                    None => http_connect_tokio(&mut s, host, port).await?,
                }
            }
            _ => panic!("unknown proxy scheme"),
        }
        Ok(Stream::Tcp(s))
    } else {
        Ok(match addr.socket_addr.as_ref() {
            Some(s) => Stream::connect(&s).await?,
            None => Stream::connect(&NamedSocketAddr::from_str(&addr.addr)?).await?,
        })
    }
}
