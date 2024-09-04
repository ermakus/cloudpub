mod common;

use common::{init, run_cloudpub, run_command, App};
use serde_json::{from_str, Value};
use std::time::Duration;
use tokio::time;
use tracing::info;

#[tokio::test]
async fn test_commands() {
    init().await;
    // Start the server
    let _server = run_cloudpub(App::Server, None).await.unwrap();
    // Sleep for 1 second for client to connect

    // Start the client
    info!("start the client");
    let _client = run_cloudpub(App::Client, None).await.unwrap();

    // Sleep for 1 second to start
    time::sleep(Duration::from_secs(1)).await;

    assert_eq!(
        run_command(App::Client, &["run"]).await.unwrap(),
        "Fatal error: Service already running"
    );

    // Sleep for 1 second for client to connect
    //time::sleep(Duration::from_secs(4)).await;

    /*
    // Get sessions from the server
    let json: Value =
        from_str(&run_command(App::Server, &["--json", "ls"]).await.unwrap()).unwrap();
    println!("{:?}", json);
    let sess = json.as_object().unwrap().get("Listing").unwrap();
    // Check if sess is array of 4 elements
    assert_eq!(sess.as_array().unwrap().len(), 4);

    // Disconnect client
    drop(client);
    time::sleep(Duration::from_secs(5)).await;

    // Get sessions from the server
    let json: Value =
        from_str(&run_command(App::Server, &["--json", "ls"]).await.unwrap()).unwrap();
    let sess = json.as_object().unwrap().get("Listing").unwrap();

    // Check if sess is array of 0 elements
    assert_eq!(sess.as_array().unwrap().len(), 0);
    */
}
