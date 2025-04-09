mod base;
mod client;
mod commands;
mod config;
mod ping;
mod service;
mod shell;

#[cfg(feature = "plugins")]
mod plugins;

use anyhow::{Context, Result};
use base::{cli_main, init, Cli};
use clap::Parser;

pub fn main() -> Result<()> {
    // Check if we're being run as a service on Windows
    #[cfg(target_os = "windows")]
    {
        use std::env;
        if env::args().any(|arg| arg == "--run-as-service") {
            return service::run_as_service();
        }
    }

    let cli = Cli::parse();
    let (_guard, config) = init(&cli, false).context("Failed to initialize config")?;
    if cli_main(cli, config).is_err() {
        std::process::exit(1);
    } else {
        Ok(())
    }
}
