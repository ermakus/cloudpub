use anyhow::{Context as _, Result};
use rolling_file::{BasicRollingFileAppender, RollingConditionBasic};
use std::path::Path;
use std::str::FromStr;
use tracing::debug;
pub use tracing_appender::non_blocking::WorkerGuard;
use tracing_log::LogTracer;
use tracing_subscriber::fmt;
use tracing_subscriber::prelude::*;

pub fn init_log(level: &str, log_file: &Path, stderr: bool) -> Result<WorkerGuard> {
    let file_appender = BasicRollingFileAppender::new(
        log_file,
        RollingConditionBasic::new().max_size(10 * 1024 * 1024), // 10 MB
        10,
    )
    .context("Failed to create rolling file appender")?;

    let (file_writer, guard) = tracing_appender::non_blocking(file_appender);

    let trace_cfg = format!(
        "{},hyper=info,tokio_postgres=info,pingora_core=info,pingora_prox=info,{}",
        level,
        std::env::var("RUST_LOG").unwrap_or_default()
    );

    let timer = time::format_description::parse(
        "[year]-[month padding:zero]-[day padding:zero] [hour]:[minute]:[second]",
    )
    .context("Failed to parse time format")?;

    let time_offset =
        time::UtcOffset::current_local_offset().unwrap_or_else(|_| time::UtcOffset::UTC);
    let timer = fmt::time::OffsetTime::new(time_offset, timer);

    if stderr {
        let ansi = cfg!(unix);
        tracing::subscriber::set_global_default(
            fmt::Subscriber::builder()
                .with_ansi(ansi)
                .with_timer(timer.clone())
                .with_max_level(tracing::Level::from_str(level).unwrap())
                .with_writer(std::io::stderr)
                .with_env_filter(trace_cfg)
                .finish()
                .with(
                    fmt::Layer::default()
                        .with_timer(timer)
                        .with_ansi(false)
                        .with_writer(file_writer),
                ),
        )
        .context("Failed to set global default subscriber")?;
    } else {
        tracing::subscriber::set_global_default(
            fmt::Subscriber::builder()
                .with_env_filter(trace_cfg)
                .with_timer(timer)
                .with_ansi(false)
                .with_writer(file_writer)
                .finish(),
        )
        .context("Failed to set global default subscriber")?;
    }

    LogTracer::init().context("Failed to initialize log tracer")?;
    log_panics::init();

    debug!("Tracing initialized ({})", level);
    Ok(guard)
}
