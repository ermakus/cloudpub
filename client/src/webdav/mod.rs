use crate::commands::{CommandResult, Commands};
use crate::config::ClientConfig;
use crate::httpd::{setup_httpd, start_httpd};
use crate::shell::SubProcess;
use anyhow::Result;
use common::protocol::ServerEndpoint;
use parking_lot::RwLock;
use std::sync::Arc;
use tokio::sync::broadcast;

const WEBDAV_CONFIG: &str = include_str!("httpd.conf");
const WEBDAV_SUBDIR: &str = "webdav";

pub async fn setup(
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Commands>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<()> {
    setup_httpd(config, command_rx, result_tx, Default::default()).await
}

pub async fn publish(
    endpoint: &ServerEndpoint,
    _config: Arc<RwLock<ClientConfig>>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<SubProcess> {
    let publish_dir = endpoint.client.local_addr.clone();
    let env = Default::default();
    start_httpd(
        endpoint,
        &WEBDAV_CONFIG,
        WEBDAV_SUBDIR,
        &publish_dir,
        env,
        result_tx,
    )
    .await
}
