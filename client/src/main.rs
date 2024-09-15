mod client;
mod commands;
mod config;
mod mod_1c;
mod shell;

use crate::commands::{CommandResult, Commands};
use crate::config::ClientConfig;
use anyhow::{Context, Result};
use clap::Parser;
use common::protocol::Protocol;
use common::version::{LONG_VERSION, VERSION};
use parking_lot::RwLock;
use std::sync::Arc;
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
    let mut args = Cli::parse();

    // Raise `nofile` limit on linux and mac
    fdlimit::raise_fd_limit();

    init_log(&args.log_level);

    let config = if let Some(path) = args.conf {
        ClientConfig::from_file(&path.into())?
    } else {
        ClientConfig::load(CONFIG_FILE, true)?
    };

    let config = Arc::new(RwLock::new(config));

    match &mut args.command {
        Commands::Publish(args) => {
            config.read().validate()?;
            args.populate()?;
            if args.protocol == Protocol::OneC {
                #[cfg(target_os = "windows")]
                if !is_elevated::is_elevated() {
                    eprint!("Please run as administrator");
                    return Ok(());
                }
                let env = commands::EnvArgs {
                    platform: args.platform.clone(),
                    home: args.home.clone(),
                };
                crate::mod_1c::setup(env, config.clone()).await?;
                crate::mod_1c::publish(&args, config.clone()).await?;
            }
        }
        Commands::Unpublish(args) => {
            args.populate()?;
            let mut guard = config.write();
            for service in guard.services.iter() {
                if service.client == args.clone().into() {
                    println!("Unpublishing service: {}", service);
                    if args.protocol == Protocol::OneC {
                        crate::mod_1c::cleanup(config.clone()).await?;
                    }
                }
            }
            guard
                .services
                .retain(|service| service.client != args.clone().into());
            guard.save().context("Failed to save config")?;
            return Ok(());
        }
        Commands::Set(set_args) => {
            config.write().set(&set_args.key, &set_args.value)?;
            return Ok(());
        }
        Commands::Get(get_args) => {
            let value = config.read().get(&get_args.key)?;
            println!("{}", value);
            return Ok(());
        }
        Commands::Ls => {
            for endpoint in config.read().services.iter() {
                println!("Service: {}", endpoint);
            }
            return Ok(());
        }
        Commands::Run => {
            config.read().validate()?;
        }
        Commands::Stop => {}
    }

    debug!("Config: {:?}", config);

    let (command_tx, command_rx) = broadcast::channel(1024);
    let (result_tx, mut result_rx) = broadcast::channel(1024);

    tokio::spawn(client::run_client(config.clone(), command_rx, result_tx));

    loop {
        match result_rx.recv().await? {
            CommandResult::Ok(res) => {
                println!("{}", res);
                break;
            }

            CommandResult::Error(_, res) => {
                eprintln!("{:?}", res);
                break;
            }

            CommandResult::Published(endpoint) => {
                println!("Service published: {}", endpoint);
                let mut guard = config.write();
                guard.services.retain(|service| *service != endpoint);
                guard.services.push(endpoint);
                guard.save().context("Failed to save config")?;
            }

            CommandResult::Connected => {
                let guard = config.read();
                println!("Connected to server: {}", guard.server);

                match args.command {
                    Commands::Run => {
                        for server_endpoint in guard.services.iter() {
                            command_tx
                                .send(Commands::Publish(server_endpoint.client.clone().into()))?;
                        }
                    }
                    ref cmd => {
                        command_tx.send(cmd.clone())?;
                    }
                }
            }
            CommandResult::Disconnected => {
                println!("Disconnected from server: {}", config.read().server);
            }

            CommandResult::Exit => break,
        }
    }

    command_tx.send(Commands::Stop)?;

    Ok(())
}
