mod common;

use anyhow::{Ok, Result};
use common::{exchange_traffic, init, run_cloudpub, App};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time;
use tracing::info;

#[tokio::test]
async fn test_traffic() -> Result<()> {
    init().await;

    let (client_stdout_tx, mut client_stdout_rx) = mpsc::channel(100);

    // Start the client
    info!("start the client");
    let client = run_cloudpub(App::Client, Some(client_stdout_tx))
        .await
        .unwrap();

    // Sleep for 1 second. Expect the client keep retrying to reach the server
    time::sleep(Duration::from_secs(1)).await;

    // Start the server
    info!("start the server");
    let server = run_cloudpub(App::Server, None).await.unwrap();

    exchange_traffic(&mut client_stdout_rx).await;

    // Simulate the client crash and restart
    info!("shutdown the client");
    drop(client);

    info!("restart the client");
    let (client_stdout_tx, mut client_stdout_rx) = mpsc::channel(100);
    let client = run_cloudpub(App::Client, Some(client_stdout_tx))
        .await
        .unwrap();

    exchange_traffic(&mut client_stdout_rx).await;

    // Simulate the server crash and restart
    info!("shutdown the server");
    drop(server);

    info!("restart the server");
    let server = run_cloudpub(App::Server, None).await.unwrap();

    exchange_traffic(&mut client_stdout_rx).await;

    drop(client);
    drop(server);

    Ok(())
}
