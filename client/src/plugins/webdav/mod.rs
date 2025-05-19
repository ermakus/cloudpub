use crate::config::ClientConfig;
use crate::plugins::httpd::{setup_httpd, start_httpd};
use crate::plugins::Plugin;
use crate::shell::SubProcess;
use anyhow::Result;
use async_trait::async_trait;
use common::protocol::message::Message;
use common::protocol::ServerEndpoint;
use common::utils::free_port_for_bind;
use parking_lot::RwLock;
use std::sync::Arc;
use tokio::sync::broadcast;

const WEBDAV_CONFIG: &str = include_str!("httpd.conf");
const WEBDAV_SUBDIR: &str = "webdav";

pub struct WebdavPlugin;

#[async_trait]
impl Plugin for WebdavPlugin {
    fn name(&self) -> &'static str {
        "webdav"
    }

    async fn setup(
        &self,
        config: Arc<RwLock<ClientConfig>>,
        command_rx: broadcast::Receiver<Message>,
        result_tx: broadcast::Sender<Message>,
    ) -> Result<()> {
        setup_httpd(config, command_rx, result_tx, Default::default()).await
    }

    async fn publish(
        &self,
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
}
