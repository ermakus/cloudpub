use crate::client::run_client;
use crate::commands::{CommandResult, Commands};
pub use crate::config::ClientConfig;
use crate::shell::get_cache_dir;
use anyhow::{Context, Result};
use clap::Parser;
use common::logging::{init_log, WorkerGuard};
use common::protocol::ErrorKind;
use common::version::{LONG_VERSION, VERSION};
use dirs::cache_dir;
use indicatif::{ProgressBar, ProgressStyle};
use parking_lot::RwLock;
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::debug;

const CONFIG_FILE: &str = "client.toml";

#[derive(Parser, Debug)]
#[command(about, version(VERSION), long_version(LONG_VERSION))]
pub struct Cli {
    #[clap(subcommand)]
    pub command: Commands,
    #[clap(short, long, default_value = "debug", help = "Log level")]
    pub log_level: String,
    #[clap(short, long, default_value = "false", help = "Ouput log to console")]
    pub verbose: bool,
    #[clap(short, long, help = "Path to the config file")]
    pub conf: Option<String>,
    #[clap(short, long, default_value = "false", help = "Read-only config mode")]
    pub readonly: bool,
}

pub fn init(args: &Cli, gui: bool) -> Result<(WorkerGuard, Arc<RwLock<ClientConfig>>)> {
    // Raise `nofile` limit on linux and mac
    fdlimit::raise_fd_limit();

    // Create log directory
    let log_dir = cache_dir().context("Can't get cache dir")?.join("cloudpub");
    std::fs::create_dir_all(&log_dir).context("Can't create log dir")?;

    let log_file = log_dir.join("client.log");

    let guard = init_log(&args.log_level, &log_file, args.verbose)
        .context("Failed to initialize logging")?;

    let config = if let Some(path) = args.conf.as_ref() {
        ClientConfig::from_file(&path.into(), args.readonly, gui)?
    } else {
        ClientConfig::load(CONFIG_FILE, true, args.readonly, gui)?
    };
    let config = Arc::new(RwLock::new(config));
    Ok((guard, config))
}

#[tokio::main]
pub async fn cli_main(mut cli: Cli, config: Arc<RwLock<ClientConfig>>) -> Result<()> {
    let (command_tx, command_rx) = broadcast::channel(1024);
    let (result_tx, mut result_rx) = broadcast::channel(1024);

    match &mut cli.command {
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
                println!("{}: {}", endpoint.guid, endpoint);
            }
            return Ok(());
        }
        Commands::Purge => {
            let cache_dir = get_cache_dir("")?;
            debug!("Purge cache dir: {:?}", cache_dir.to_str().unwrap());
            std::fs::remove_dir_all(&cache_dir).ok();
            return Ok(());
        }
        Commands::Clean => {
            let mut guard = config.write();
            guard.services.clear();
            guard.save().context("Failed to save config")?;
            return Ok(());
        }
        Commands::Publish(publish_args) => {
            config.read().validate()?;
            publish_args.populate()?;
        }
        Commands::Unpublish(_) | Commands::Run | Commands::Stop | Commands::Break => {
            config.read().validate()?;
        }
    }

    debug!("Config: {:?}", config);

    tokio::spawn(run_client(config.clone(), command_rx, result_tx));

    let command_tx1 = command_tx.clone();
    ctrlc::set_handler(move || {
        command_tx1.send(Commands::Stop).ok();
    })
    .context("Error setting Ctrl-C handler")?;

    let mut current_spinner = None;
    let mut progress_bar = None;

    loop {
        match result_rx.recv().await? {
            CommandResult::Ok(res) => {
                println!("{}", res);
                break;
            }

            CommandResult::Error(kind, res) => {
                eprintln!("{}", res);
                if kind == ErrorKind::Fatal || kind == ErrorKind::AuthFailed {
                    break;
                }
            }

            CommandResult::UpgradeAvailable(info) => {
                println!("Доступна новая версия: {}", info.version);
            }

            CommandResult::Published(endpoint) => {
                if endpoint.status == Some("online".to_string()) {
                    println!("Cервис опубликован: {}", endpoint);
                }
                let mut guard = config.write();
                guard.services.retain(|service| *service != endpoint);
                guard.services.push(endpoint);
                guard.save().context("Failed to save config")?;
            }

            CommandResult::Unpublished(guid) => {
                println!("Сервис остановлен: {}", guid);
                let mut guard = config.write();
                for service in guard.services.iter_mut() {
                    if service.guid == guid {
                        service.status = Some("offline".to_string());
                    }
                }
                guard.save().context("Failed to save config")?;
                break;
            }

            CommandResult::Removed(guid) => {
                println!("Сервис удален: {}", guid);
                let mut guard = config.write();
                guard.services.retain(|service| service.guid != guid);
                guard.save().context("Failed to save config")?;
                break;
            }

            CommandResult::Connecting => {
                let spinner = ProgressBar::new_spinner();
                let style = ProgressStyle::default_spinner()
                    .template("{spinner} {msg}")
                    .unwrap();
                #[cfg(target_os = "windows")]
                let style = style.tick_chars("-\\|/ ");
                spinner.set_style(style);
                spinner.set_message("Подключение к серверу...");
                #[cfg(unix)]
                spinner.enable_steady_tick(std::time::Duration::from_millis(100));
                current_spinner = Some(spinner);
            }

            CommandResult::Connected => {
                if let Some(spinner) = current_spinner.take() {
                    spinner.finish_and_clear();
                }

                let guard = config.read();

                match cli.command {
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
                if let Some(spinner) = current_spinner.take() {
                    spinner.finish_and_clear();
                }
            }

            CommandResult::Progress(info) => {
                if info.current == 0 {
                    let bar = ProgressBar::new(info.total);
                    bar.set_message(info.message);
                    bar.set_style(ProgressStyle::default_bar().template(&info.template)?);
                    progress_bar = Some(bar)
                } else if info.current >= info.total {
                    if let Some(progress_bar) = progress_bar.take() {
                        progress_bar.finish();
                    }
                } else {
                    progress_bar.as_ref().unwrap().set_position(info.current);
                }
            }

            CommandResult::Exit => break,
        }
    }

    command_tx.send(Commands::Stop).ok();

    Ok(())
}
