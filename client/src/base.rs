use crate::client::run_client;
use crate::commands::{Commands, ServiceAction};
pub use crate::config::ClientConfig;
use crate::ping;
use crate::service::{create_service_manager, ServiceConfig, ServiceStatus};
use crate::shell::get_cache_dir;
use anyhow::{Context, Result, bail};
use clap::Parser;
use common::logging::{init_log, WorkerGuard};
use common::protocol::message::Message;
use common::protocol::{
    ConnectState, EndpointClear, EndpointList, EndpointRemove, EndpointStartAll, EndpointStop,
    ErrorKind, Stop,
};
use common::version::{LONG_VERSION, VERSION};
use dirs::cache_dir;
use indicatif::{ProgressBar, ProgressStyle};
use parking_lot::RwLock;
use std::env;
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

fn handle_service_command(action: &ServiceAction, config: &ClientConfig) -> Result<()> {
    // Get the current executable path
    let exe_path = env::current_exe().context("Failed to get current executable path")?;

    // Prepare config file argument
    let mut args = Vec::new();
    if let Some(path_str) = config.get_config_path().to_str() {
        args.push("--conf".to_string());
        args.push(path_str.to_string());
    }

    // Add the run command for the service
    args.push("run".to_string());

    // On Windows, add the service flag
    #[cfg(target_os = "windows")]
    {
        args.push("--run-as-service".to_string());
    }

    // Create service configuration
    let service_config = ServiceConfig {
        #[cfg(target_os = "macos")]
        name: "ru.cloudpub.clo".to_string(),
        #[cfg(not(target_os = "macos"))]
        name: "cloudpub".to_string(),
        display_name: "CloudPub Client".to_string(),
        description: "CloudPub Client Service".to_string(),
        executable_path: exe_path,
        args,
        config_path: Some(config.get_config_path().to_owned()),
    };

    // Create the appropriate service manager for the current platform
    let service_manager = create_service_manager(service_config);

    match action {
        ServiceAction::Install => {
            service_manager.install()?;
            println!("Service installed successfully");
        }
        ServiceAction::Uninstall => {
            service_manager.uninstall()?;
            println!("Service uninstalled successfully");
        }
        ServiceAction::Start => {
            service_manager.start()?;
            println!("Service started successfully");
        }
        ServiceAction::Stop => {
            service_manager.stop()?;
            println!("Service stopped successfully");
        }
        ServiceAction::Status => {
            let status = service_manager.status()?;
            match status {
                ServiceStatus::Running => println!("Service is running"),
                ServiceStatus::Stopped => println!("Service is stopped"),
                ServiceStatus::NotInstalled => println!("Service is not installed"),
                ServiceStatus::Unknown => println!("Service status is unknown"),
            }
        }
    }

    Ok(())
}

pub fn init(args: &Cli, gui: bool) -> Result<(WorkerGuard, Arc<RwLock<ClientConfig>>)> {
    // Raise `nofile` limit on linux and mac
    fdlimit::raise_fd_limit();

    // Create log directory
    let log_dir = cache_dir().context("Can't get cache dir")?.join("cloudpub");
    std::fs::create_dir_all(&log_dir).context("Can't create log dir")?;

    let log_file = log_dir.join("client.log");

    let guard = init_log(&args.log_level, &log_file, args.verbose, 2)
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
pub async fn cli_main(cli: Cli, config: Arc<RwLock<ClientConfig>>) -> Result<()> {
    ctrlc::set_handler(move || {
        std::process::exit(1);
    })
    .context("Error setting Ctrl-C handler")?;

    let (command_tx, command_rx) = broadcast::channel(1024);
    main_loop(cli, config, command_tx, command_rx, None, None).await
}

fn make_spinner(msg: &'static str) -> ProgressBar {
    let spinner = ProgressBar::new_spinner();
    let style = ProgressStyle::default_spinner()
        .template("{spinner} {msg}")
        .unwrap();
    #[cfg(target_os = "windows")]
    let style = style.tick_chars("-\\|/ ");
    spinner.set_style(style);
    spinner.set_message(msg);
    #[cfg(unix)]
    spinner.enable_steady_tick(std::time::Duration::from_millis(100));
    spinner
}

pub async fn main_loop(
    mut cli: Cli,
    config: Arc<RwLock<ClientConfig>>,
    command_tx: broadcast::Sender<Message>,
    command_rx: broadcast::Receiver<Message>,
    stdout: Option<broadcast::Sender<String>>,
    stderr: Option<broadcast::Sender<String>>,
) -> Result<()> {
    let write_stdout = |res: String| {
        if let Some(tx) = stdout.as_ref() {
            tx.send(res).ok();
        } else {
            println!("{}", res);
        }
    };

    let write_stderr = |res: String| {
        if let Some(tx) = stderr.as_ref() {
            tx.send(res).ok();
        } else {
            eprintln!("{}", res);
        }
    };

    let (result_tx, mut result_rx) = broadcast::channel(1024);

    let mut pings = 1;

    match &mut cli.command {
        Commands::Set(set_args) => {
            config.write().set(&set_args.key, &set_args.value)?;
            return Ok(());
        }
        Commands::Get(get_args) => {
            let value = config.read().get(&get_args.key)?;
            write_stdout(value);
            return Ok(());
        }
        Commands::Purge => {
            let cache_dir = get_cache_dir("")?;
            debug!("Purge cache dir: {:?}", cache_dir.to_str().unwrap());
            std::fs::remove_dir_all(&cache_dir).ok();
            return Ok(());
        }
        Commands::Register(publish_args) => {
            config.read().validate()?;
            publish_args.parse()?;
        }
        Commands::Publish(publish_args) => {
            config.read().validate()?;
            publish_args.parse()?;
        }
        Commands::Unpublish(_)
        | Commands::Run
        | Commands::Stop
        | Commands::Break
        | Commands::Ping(_)
        | Commands::Ls
        | Commands::Clean => {
            config.read().validate()?;
        }
        Commands::Service { action } => {
            return handle_service_command(action, &config.read());
        }
    }

    debug!("Config: {:?}", config);

    tokio::spawn(run_client(config.clone(), command_rx, result_tx));

    let mut current_spinner = None;
    let mut progress_bar = None;

    loop {
        match result_rx.recv().await? {
            Message::Error(err) => {
                write_stderr(err.message.clone());
                let kind: ErrorKind = err.kind.try_into().unwrap_or(ErrorKind::Fatal);
                if kind == ErrorKind::Fatal || kind == ErrorKind::AuthFailed {
                    command_tx.send(Message::Stop(Stop {})).ok();
                    bail!("{}", err.message);
                }
            }

            Message::UpgradeAvailable(info) => match cli.command {
                Commands::Publish(_) | Commands::Run => {
                    write_stdout(format!("Доступна новая версия: {}", info.version));
                }
                _ => {}
            },

            Message::EndpointAck(endpoint) => {
                if endpoint.status == Some("online".to_string()) {
                    match cli.command {
                        Commands::Ping(ref args) => {
                            current_spinner =
                                Some(make_spinner("Измеряем скорость подключения..."));
                            let stats = ping::ping_test(endpoint, args.bare).await?;
                            current_spinner.take();
                            if args.bare {
                                write_stdout(stats.to_string());
                            } else {
                                write_stdout(format!("Время пинга (процентили):\n{}", stats));
                            }
                            pings -= 1;
                            if pings == 0 {
                                break;
                            }
                        }
                        Commands::Register(_) => {
                            write_stdout(format!("Сервис зарегистрирован: {}", endpoint));
                            break;
                        }
                        Commands::Publish(_) | Commands::Run => {
                            write_stdout(format!("Сервис опубликован: {}", endpoint));
                        }
                        _ => {}
                    }
                }
            }

            Message::EndpointStopAck(ep) => {
                write_stdout(format!("Сервис остановлен: {}", ep.guid));
                break;
            }

            Message::EndpointRemoveAck(ep) => {
                write_stdout(format!("Сервис удален: {}", ep.guid));
                break;
            }

            Message::ConnectState(st) => match st.try_into().unwrap_or(ConnectState::Connecting) {
                ConnectState::Connecting => {
                    current_spinner = Some(make_spinner("Подключение к серверу..."));
                }

                ConnectState::Connected => {
                    if let Some(spinner) = current_spinner.take() {
                        spinner.finish_and_clear();
                    }

                    match cli.command {
                        Commands::Ls => {
                            command_tx.send(Message::EndpointList(EndpointList {}))?;
                        }
                        Commands::Clean => {
                            command_tx.send(Message::EndpointClear(EndpointClear {}))?;
                        }
                        Commands::Run => {
                            command_tx.send(Message::EndpointStartAll(EndpointStartAll {}))?;
                        }
                        Commands::Publish(ref endpoint) => {
                            command_tx.send(Message::EndpointStart(endpoint.parse()?))?;
                        }
                        Commands::Register(ref endpoint) => {
                            command_tx.send(Message::EndpointStart(endpoint.parse()?))?;
                        }
                        Commands::Unpublish(ref args) => {
                            if args.remove {
                                command_tx.send(Message::EndpointRemove(EndpointRemove {
                                    guid: args.guid.clone(),
                                }))?;
                            } else {
                                command_tx.send(Message::EndpointStop(EndpointStop {
                                    guid: args.guid.clone(),
                                }))?;
                            }
                        }
                        Commands::Ping(ref args) => {
                            pings = args.num.unwrap_or(1);
                            for _i in 0..pings {
                                ping::publish(command_tx.clone()).await?;
                            }
                        }
                        _ => {}
                    }
                }
                ConnectState::Disconnected => {
                    if let Some(spinner) = current_spinner.take() {
                        spinner.finish_and_clear();
                    }
                }
            },

            Message::Progress(info) => {
                if info.current == 0 {
                    let bar = ProgressBar::new(info.total as u64);
                    bar.set_message(info.message);
                    bar.set_style(ProgressStyle::default_bar().template(&info.template)?);
                    progress_bar = Some(bar)
                } else if info.current >= info.total {
                    if let Some(progress_bar) = progress_bar.take() {
                        progress_bar.finish();
                    }
                } else {
                    progress_bar
                        .as_ref()
                        .unwrap()
                        .set_position(info.current as u64);
                }
            }

            Message::EndpointListAck(list) => {
                if list.endpoints.is_empty() {
                    write_stdout("Нет зарегистрированных сервисов".to_string());
                } else {
                    let mut output = String::new();
                    for ep in &list.endpoints {
                        output.push_str(&format!("{}: {}\n", ep.guid, ep));
                    }
                    write_stdout(output);
                }
                break;
            }

            Message::EndpointClearAck(_) => {
                write_stdout("Все сервисы удалены".to_string());
                break;
            }

            other => {
                debug!("Unhandled message: {:?}", other);
            }
        }
    }

    command_tx.send(Message::Stop(Stop {})).ok();

    Ok(())
}
