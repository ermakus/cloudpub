mod base;
mod client;
mod commands;
mod config;
mod mod_1c;
mod shell;

use anyhow::{Context, Result};
use base::{cli_main, init, Cli};
use clap::Parser;

pub fn main() -> Result<()> {
    let cli = Cli::parse();
    let (_guard, config) = init(&cli).context("Failed to initialize config")?;
    cli_main(cli, config)
}
