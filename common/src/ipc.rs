use crate::protocol::{read_message, write_message};
use anyhow::{Context, Result};
use futures::stream::StreamExt;
use serde::de::DeserializeOwned;
use serde::Serialize;
use std::fmt::Debug;
use tipsy::{Connection, Endpoint, OnConflict, ServerId};
use tokio::io::split;
use tokio::signal;
use tokio::sync::broadcast;
use tracing::{debug, error};

pub async fn shutdown_signal(shutdown_tx: broadcast::Sender<()>) -> Result<()> {
    signal::ctrl_c().await?;
    debug!("Received ctrl-c signal.");
    shutdown_tx.send(())?;
    Ok(())
}

pub async fn ipc_server<Commands, CommandsResult>(
    server_name: &str,
    command_tx: broadcast::Sender<Commands>,
    result_rx: broadcast::Receiver<CommandsResult>,
    mut shutdown_rx: broadcast::Receiver<()>,
) -> Result<()>
where
    Commands: Serialize + DeserializeOwned + Debug + Send + 'static,
    CommandsResult: Serialize + DeserializeOwned + Debug + Send + Sync + Clone + 'static,
{
    debug!("IPC: server started");

    let mut endpoint = Endpoint::new(ServerId(server_name), OnConflict::Overwrite)?.incoming()?;

    loop {
        let result_rx = result_rx.resubscribe();
        tokio::select! {
            stream = endpoint.next() => {
                debug!("IPC: client connected");
                match stream  {
                    Some(Ok(stream)) => ipc_receiver(stream, command_tx.clone(), result_rx).await?,

                    Some(Err(e)) => {
                        error!("IPC: server listen error: {:?}", e);
                        return Ok(());
                    }
                    None => {
                        error!("IPC: server stopped");
                        return Ok(());
                    }
                }
            }
            _ = shutdown_rx.recv() => {
                debug!("IPC: server shut down");
                return Ok(());
            }
        }
    }
}

async fn ipc_receiver<Commands, CommandsResult>(
    stream: Connection,
    command_tx: broadcast::Sender<Commands>,
    command_rx: broadcast::Receiver<CommandsResult>,
) -> Result<()>
where
    Commands: Serialize + DeserializeOwned + Debug + Send + 'static,
    CommandsResult: Serialize + DeserializeOwned + Debug + Send + Sync + Clone + 'static,
{
    let command_tx = command_tx.clone();
    let (mut reader, mut writer) = split(stream);

    tokio::spawn(async move {
        loop {
            let mut command_rx = command_rx.resubscribe();
            tokio::select! {
                    msg = command_rx.recv() => match msg {
                            Ok(msg) => {
                                if let Err(err) = write_message(&mut writer, &msg).await {
                                    error!("IPC: server command result error: {:?}", err);
                                    return;
                                }
                            }
                            Err(e) => {
                                error!("IPC: server command result error: {:?}", e);
                                return;
                            }
                        },
                    msg = read_message::<_, Commands>(&mut reader) => match msg {
                    Ok(msg) => {
                        debug!("IPC server received: {:?}", msg);
                        if let Err(e) = command_tx.send(msg) {
                            error!("IPC: Error sending to channel: {:?}", e);
                        }
                    }
                    Err(e) => {
                        debug!("IPC: Read error {:?}", e);
                        break;
                    }
                }
            }
        }
    });
    Ok(())
}

pub async fn ipc_send<M: Serialize, R: DeserializeOwned>(
    server_name: &str,
    message: &M,
) -> Result<R> {
    let mut client = Endpoint::connect(ServerId(server_name)).await?;
    write_message(&mut client, message)
        .await
        .context("Can't write IPC")?;
    read_message(&mut client).await.context("Can't read IPC")
}
