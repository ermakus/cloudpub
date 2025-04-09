use crate::config::ClientConfig;
use crate::plugins::httpd::{setup_httpd, start_httpd};
use crate::shell::SubProcess;
use anyhow::Result;
use common::protocol::message::Message;
use common::protocol::ServerEndpoint;
use common::utils::free_port_for_bind;
use parking_lot::RwLock;
use std::sync::Arc;
use tokio::sync::broadcast;

const WEBDAV_CONFIG: &str = include_str!("httpd.conf");
const WEBDAV_SUBDIR: &str = "webdav";

pub async fn setup(
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Message>,
    result_tx: broadcast::Sender<Message>,
) -> Result<()> {
    setup_httpd(config, command_rx, result_tx, Default::default()).await
}

pub async fn publish(
    endpoint: &mut ServerEndpoint,
    _config: Arc<RwLock<ClientConfig>>,
    result_tx: broadcast::Sender<Message>,
) -> Result<SubProcess> {
    let publish_dir = endpoint.client.as_ref().unwrap().local_addr.clone();
    let env = Default::default();

    free_port_for_bind(endpoint).await?;

    start_httpd(
        endpoint,
        WEBDAV_CONFIG,
        WEBDAV_SUBDIR,
        &publish_dir,
        env,
        result_tx,
    )
    .await
}
