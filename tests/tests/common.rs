#![allow(dead_code)]
use anyhow::{Context, Result};
use rand::Rng;
use regex::Regex;
use std::process::Stdio;
use tokio;
use tokio::io::{self, AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream, ToSocketAddrs};
use tokio::process::{Child, Command};
use tokio::sync::mpsc;
use tracing::{debug, info};
use tracing_subscriber::EnvFilter;

const ECHO_SERVER_ADDR: &str = "127.0.0.1:5000";
const PINGPONG_SERVER_ADDR: &str = "127.0.0.1:5001";

const PING: &str = "ping";
const PONG: &str = "pong";

const RE_ENDPOINT: &str = r"^Service published: \[(.*)\] (.*) -> (.*)$";

#[derive(Debug, Clone)]
pub enum App {
    Client,
    Server,
}

pub async fn init() {
    std::env::set_current_dir("..").unwrap();

    let level = "debug";
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::from(level)),
        )
        .try_init();

    // Spawn a echo server
    tokio::spawn(async move {
        if let Err(e) = tcp::echo_server(ECHO_SERVER_ADDR).await {
            panic!("Failed to run the echo server for testing: {:?}", e);
        }
    });

    // Spawn a pingpong server
    tokio::spawn(async move {
        if let Err(e) = tcp::pingpong_server(PINGPONG_SERVER_ADDR).await {
            panic!("Failed to run the pingpong server for testing: {:?}", e);
        }
    });

    // Spawn a echo server
    tokio::spawn(async move {
        if let Err(e) = udp::echo_server(ECHO_SERVER_ADDR).await {
            panic!("Failed to run the echo server for testing: {:?}", e);
        }
    });

    // Spawn a pingpong server
    tokio::spawn(async move {
        if let Err(e) = udp::pingpong_server(PINGPONG_SERVER_ADDR).await {
            panic!("Failed to run the pingpong server for testing: {:?}", e);
        }
    });
}

pub async fn run_cloudpub(app: App, stdout_tx: Option<mpsc::Sender<String>>) -> Result<ChildGuard> {
    run_app(
        app.clone(),
        match app {
            App::Client => &["run"],
            App::Server => &[],
        },
        stdout_tx,
        match app {
            App::Client => Some(Regex::new(RE_ENDPOINT).unwrap()),
            App::Server => None,
        },
    )
    .await
}

pub async fn run_app(
    app: App,
    args: &[&str],
    stdout_tx: Option<mpsc::Sender<String>>,
    re: Option<Regex>,
) -> Result<ChildGuard> {
    let (exe_path, config_path) = match app {
        App::Client => ("target/debug/client", "tests/config/client.toml"),
        App::Server => ("target/debug/server", "tests/config/server.toml"),
    };

    debug!("Run app: {:?} {:?}", app, args);

    let mut child = Command::new(exe_path)
        .arg("--conf")
        .arg(config_path)
        .args(args)
        .stdout(Stdio::piped())
        //.stderr(Stdio::piped())
        .spawn()?;

    let stdout = child.stdout.take().expect("Failed to open stdout");

    let args = args.iter().map(|x| x.to_string()).collect::<Vec<String>>();

    tokio::spawn(async move {
        let mut reader = BufReader::new(stdout).lines();
        let re = re.clone();
        while let Some(line) = reader.next_line().await.unwrap() {
            debug!("{:?}:{:?}: {}", app, args, line);
            let ok = if let Some(re) = re.as_ref() {
                re.is_match(&line)
            } else {
                true
            };

            if ok {
                if let Some(tx) = &stdout_tx {
                    tx.send(line.clone()).await.unwrap();
                }
            }
        }
    });

    Ok(ChildGuard(child))
}

pub async fn run_command(app: App, cmd: &[&str]) -> Result<String> {
    let (stdout_tx, mut stdout_rx) = mpsc::channel(100);
    let _app = run_app(app, cmd, Some(stdout_tx), None).await?;
    Ok(stdout_rx.recv().await.context("No data in stdout")?)
}

pub struct ChildGuard(Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        info!("Kill children");
        self.0.start_kill().unwrap();
    }
}

pub fn parse_endpoint(endpoint: &str) -> Result<(String, String, String)> {
    let re = Regex::new(RE_ENDPOINT)?;
    let caps = re.captures(endpoint).context("Bad pattern")?;
    Ok((
        caps.get(1).unwrap().as_str().to_owned(),
        caps.get(2).unwrap().as_str().to_owned(),
        caps.get(3).unwrap().as_str().to_owned(),
    ))
}

pub mod tcp {
    use super::*;

    pub async fn echo_server<A: ToSocketAddrs>(addr: A) -> Result<()> {
        let l = TcpListener::bind(addr).await?;

        loop {
            let (conn, _addr) = l.accept().await?;
            tokio::spawn(async move {
                let _ = echo(conn).await;
            });
        }
    }

    pub async fn pingpong_server<A: ToSocketAddrs>(addr: A) -> Result<()> {
        let l = TcpListener::bind(addr).await?;

        loop {
            let (conn, _addr) = l.accept().await?;
            tokio::spawn(async move {
                let _ = pingpong(conn).await;
            });
        }
    }

    async fn echo(conn: TcpStream) -> Result<()> {
        let (mut rd, mut wr) = conn.into_split();
        io::copy(&mut rd, &mut wr).await?;

        Ok(())
    }

    async fn pingpong(mut conn: TcpStream) -> Result<()> {
        let mut buf = [0u8; PING.len()];

        while conn.read_exact(&mut buf).await? != 0 {
            assert_eq!(buf, PING.as_bytes());
            conn.write_all(PONG.as_bytes()).await?;
        }

        Ok(())
    }
    pub async fn echo_hitter(addr: &str) -> Result<()> {
        info!("tcp_echo_hitter: {}", addr);
        let mut conn = TcpStream::connect(addr).await?;

        let mut wr = [0u8; 1024];
        let mut rd = [0u8; 1024];
        for _ in 0..100 {
            rand::thread_rng().fill(&mut wr);
            conn.write_all(&wr).await?;
            conn.read_exact(&mut rd).await?;
            assert_eq!(wr, rd);
        }

        Ok(())
    }

    pub async fn pingpong_hitter(addr: &str) -> Result<()> {
        let mut conn = TcpStream::connect(addr).await?;

        let wr = PING.as_bytes();
        let mut rd = [0u8; PONG.len()];

        for _ in 0..100 {
            conn.write_all(wr).await?;
            conn.read_exact(&mut rd).await?;
            assert_eq!(rd, PONG.as_bytes());
        }

        Ok(())
    }
}

pub mod udp {
    use common::constants::UDP_BUFFER_SIZE;
    use tokio::net::UdpSocket;
    use tracing::debug;

    use super::*;

    pub async fn echo_server<A: ToSocketAddrs>(addr: A) -> Result<()> {
        let l = UdpSocket::bind(addr).await?;
        debug!("UDP echo server listening");

        let mut buf = [0u8; UDP_BUFFER_SIZE];
        loop {
            let (n, addr) = l.recv_from(&mut buf).await?;
            debug!("Get {:?} from {}", &buf[..n], addr);
            l.send_to(&buf[..n], addr).await?;
        }
    }

    pub async fn pingpong_server<A: ToSocketAddrs>(addr: A) -> Result<()> {
        let l = UdpSocket::bind(addr).await?;

        let mut buf = [0u8; UDP_BUFFER_SIZE];
        loop {
            let (n, addr) = l.recv_from(&mut buf).await?;
            assert_eq!(&buf[..n], PING.as_bytes());
            l.send_to(PONG.as_bytes(), addr).await?;
        }
    }

    pub async fn echo_hitter(addr: &str) -> Result<()> {
        let conn = UdpSocket::bind("127.0.0.1:0").await?;
        conn.connect(addr).await?;

        let mut wr = [0u8; 128];
        let mut rd = [0u8; 128];
        for _ in 0..3 {
            rand::thread_rng().fill(&mut wr);

            conn.send(&wr).await?;
            debug!("send");

            conn.recv(&mut rd).await?;
            debug!("recv");

            assert_eq!(wr, rd);
        }
        Ok(())
    }

    pub async fn pingpong_hitter(addr: &str) -> Result<()> {
        let conn = UdpSocket::bind("127.0.0.1:0").await?;
        conn.connect(&addr).await?;

        let wr = PING.as_bytes();
        let mut rd = [0u8; PONG.len()];

        for _ in 0..3 {
            conn.send(wr).await?;
            debug!("ping");

            conn.recv(&mut rd).await?;
            debug!("pong");

            assert_eq!(rd, PONG.as_bytes());
        }

        Ok(())
    }
}

pub async fn exchange_traffic(client_stdout_rx: &mut mpsc::Receiver<String>) {
    info!("Wait for endpoints in stdout");

    for _ in 0..4 {
        let (name, from, to) = parse_endpoint(&client_stdout_rx.recv().await.unwrap()).unwrap();
        info!("{} connected: {} -> {}", name, from, to);
        match name.as_str() {
            "tcp_echo" => tcp::echo_hitter(&to).await.unwrap(),
            "tcp_pingpong" => tcp::pingpong_hitter(&to).await.unwrap(),
            "udp_echo" => udp::echo_hitter(&to).await.unwrap(),
            "udp_pingpong" => udp::pingpong_hitter(&to).await.unwrap(),
            _ => panic!("unknown endpoint"),
        }
    }
}
