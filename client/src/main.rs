mod client;
mod commands;
mod config;
mod mod_1c;
mod shell;

use crate::commands::{CommandResult, Commands, PublishArgs};
use crate::config::ClientConfig;
use anyhow::{bail, Result};
use clap::Parser;
use common::ipc::{ipc_send, ipc_server, shutdown_signal};
use common::version::{LONG_VERSION, VERSION};
use tokio::sync::broadcast;
use tracing::debug;
use tracing_subscriber::EnvFilter;

pub fn init_log(level: &str) {
    #[cfg(target_os = "windows")]
    let is_atty = false;
    #[cfg(not(target_os = "windows"))]
    let is_atty = atty::is(atty::Stream::Stdout);

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::from(level)),
        )
        .with_ansi(is_atty)
        .init();
}

const IPC_SERVER_NAME: &str = "cloudpub-client-ipc";
const CONFIG_FILE: &str = "client.toml";

#[derive(Parser, Debug)]
#[command(
    about,
    version(*VERSION),
    long_version(LONG_VERSION.as_str()),
)]
pub struct Cli {
    #[clap(subcommand)]
    command: Commands,
    #[clap(short, long, default_value = "error")]
    log_level: String,
    #[clap(short, long)]
    conf: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Cli::parse();

    // Raise `nofile` limit on linux and mac
    fdlimit::raise_fd_limit();

    init_log(&args.log_level);

    let mut config = if let Some(path) = args.conf {
        ClientConfig::from_file(&path.into())?
    } else {
        ClientConfig::load(CONFIG_FILE, true)?
    };

    debug!("Config: {:?}", config);

    if let Ok(cmd) = ipc_send::<_, CommandResult>(IPC_SERVER_NAME, &args.command).await {
        println!("{}", cmd);
        return Ok(());
    }

    match &args.command {
        Commands::Set(set_args) => {
            config.set(&set_args.key, &set_args.value)?;
            return Ok(());
        }
        _ => {}
    }

    let (command_tx, command_rx) = broadcast::channel(1024);
    let (result_tx, mut result_rx) = broadcast::channel(1024);
    let (shutdown_tx, shutdown_rx) = broadcast::channel(1);

    if config.token.is_none() {
        bail!("API token is not set. Run \"cloudpub-client set token XXXXXXXXX\" first");
    };

    let services = config.services.clone();

    tokio::spawn(client::run_client(
        config,
        shutdown_rx,
        command_rx,
        result_tx,
    ));

    if let Commands::Run = args.command {
        tokio::spawn(ipc_server(
            IPC_SERVER_NAME,
            command_tx.clone(),
            result_rx.resubscribe(),
            shutdown_tx.subscribe(),
        ));
        //command_tx.send(args.command.clone())?;
        //shutdown_signal(shutdown_tx.clone()).await?;
    };

    loop {
        match result_rx.recv().await? {
            CommandResult::Ok(res) => {
                println!("{}", res);
                break;
            }
            CommandResult::Error(_, res) => {
                eprintln!("{}", res);
                break;
            }
            CommandResult::Published(endpoint) => {
                println!("Service published: {}", endpoint);
            }
            CommandResult::Connected => {
                println!("Connected");
                for (name, config) in &services {
                    command_tx.send(Commands::Publish(PublishArgs {
                        name: Some(name.clone()),
                        protocol: config.service_type,
                        address: config.local_addr.clone(),
                    }))?;
                }
                if let Commands::Publish(_) = args.command {
                    command_tx.send(args.command.clone())?;
                }
            }
            CommandResult::Disconnected => {
                println!("Disconnected");
            }
            CommandResult::Exit => break,
            other => {
                println!("{}", other);
            }
        }
    }
    shutdown_tx.send(())?;

    Ok(())
}
