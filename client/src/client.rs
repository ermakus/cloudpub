use anyhow::{anyhow, bail, Context, Result};
use backoff::backoff::Backoff;
use backoff::future::retry_notify;
use backoff::ExponentialBackoff;
use bytes::{Bytes, BytesMut};
use common::config::{ServiceType, TransportType};
use common::helper::udp_connect;
use common::protocol::{
    read_message, write_message, AgentInfo, ClientEndpoint, DataChannelInfo, Message,
    ServerEndpoint, UdpTraffic,
};
use common::transport::{AddrMaybeCached, SocketOpts, TcpTransport, Transport};
use parking_lot::RwLock;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{self, copy_bidirectional, AsyncReadExt};
use tokio::net::{TcpStream, UdpSocket};
use tokio::sync::{broadcast, mpsc};
use tokio::time::{self, Duration, Instant};
use tracing::{debug, error, info, instrument, trace, warn};

use common::transport::{TlsTransport, WebsocketTransport};

use common::constants::{run_control_chan_backoff, UDP_BUFFER_SIZE, UDP_SENDQ_SIZE, UDP_TIMEOUT};

use crate::commands::{CommandResult, Commands};
use crate::config::ClientConfig;

// The entrypoint of running a client
pub async fn run_client(
    config: ClientConfig,
    shutdown_rx: broadcast::Receiver<()>,
    command_rx: broadcast::Receiver<Commands>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<()> {
    match config.transport.transport_type {
        TransportType::Tcp => {
            let mut client = Client::<TcpTransport>::from(config).await?;
            client.run(shutdown_rx, command_rx, result_tx).await
        }
        TransportType::Tls => {
            let mut client = Client::<TlsTransport>::from(config).await?;
            client.run(shutdown_rx, command_rx, result_tx).await
        }
        TransportType::Websocket => {
            let mut client = Client::<WebsocketTransport>::from(config).await?;
            client.run(shutdown_rx, command_rx, result_tx).await
        }
    }
}

// Holds the state of a client
struct Client<T: Transport> {
    config: Arc<RwLock<ClientConfig>>,
    service_handles: HashMap<String, ServerEndpoint>,
    transport: Arc<T>,
}

impl<T: 'static + Transport> Client<T> {
    // Create a Client from `[client]` config block
    async fn from(config: ClientConfig) -> Result<Client<T>> {
        let transport =
            Arc::new(T::new(&config.transport).with_context(|| "Failed to create the transport")?);
        Ok(Client {
            config: Arc::new(RwLock::new(config)),
            service_handles: HashMap::new(),
            transport,
        })
    }

    // The entrypoint of Client
    async fn run(
        &mut self,
        shutdown_rx: broadcast::Receiver<()>,
        command_rx: broadcast::Receiver<Commands>,
        result_tx: broadcast::Sender<CommandResult>,
    ) -> Result<()> {
        let mut retry_backoff = run_control_chan_backoff(self.config.read().retry_interval);

        let mut start = Instant::now();

        while let Err(err) = run_control_channel(
            self.config.clone(),
            self.transport.clone(),
            command_rx.resubscribe(),
            result_tx.clone(),
            shutdown_rx.resubscribe(),
            &mut self.service_handles,
        )
        .await
        .context("Failed to run the control channel")
        {
            self.service_handles.clear();

            if start.elapsed() > Duration::from_secs(3) {
                // The client runs for at least 3 secs and then disconnects
                retry_backoff.reset();
            }

            if let Some(duration) = retry_backoff.next_backoff() {
                warn!("{:#}. Retry in {:?}...", err, duration);
                time::sleep(duration).await;
            } else {
                // Should never reach
                panic!("{:#}. Break", err);
            }

            start = Instant::now();
        }

        // Shutdown all services
        for (_, handle) in self.service_handles.drain() {
            drop(handle);
        }

        Ok(())
    }
}

struct RunDataChannelArgs<T: Transport> {
    agent_id: String,
    channel_id: String,
    remote_addr: AddrMaybeCached,
    connector: Arc<T>,
    socket_opts: SocketOpts,
    service: ClientEndpoint,
}

async fn do_data_channel_handshake<T: Transport>(
    args: Arc<RunDataChannelArgs<T>>,
) -> Result<T::Stream> {
    // Retry at least every 100ms, at most for 10 seconds
    let backoff = ExponentialBackoff {
        max_interval: Duration::from_millis(100),
        max_elapsed_time: Some(Duration::from_secs(10)),
        ..Default::default()
    };

    // Connect to remote_addr
    let mut conn: T::Stream = retry_notify(
        backoff,
        || async {
            args.connector
                .connect(&args.remote_addr)
                .await
                .with_context(|| format!("Failed to connect to {}", &args.remote_addr))
                .map_err(backoff::Error::transient)
        },
        |e, duration| {
            warn!("{:#}. Retry in {:?}", e, duration);
        },
    )
    .await?;

    T::hint(&conn, args.socket_opts);

    let hello = Message::DataChannelHello(DataChannelInfo {
        agent_id: args.agent_id.clone(),
        channel_id: args.channel_id.clone(),
    });
    write_message(&mut conn, &hello).await?;
    Ok(conn)
}

async fn run_data_channel<T: Transport>(args: Arc<RunDataChannelArgs<T>>) -> Result<()> {
    // Do the handshake
    let mut conn = do_data_channel_handshake(args.clone()).await?;

    // Forward
    match read_message(&mut conn).await? {
        Message::StartForwardTcp => {
            if args.service.service_type != ServiceType::Tcp
                && args.service.service_type != ServiceType::Http
            {
                bail!("Expect TCP traffic. Please check the configuration.")
            }
            run_data_channel_for_tcp::<T>(conn, &args.service.local_addr).await?;
        }
        Message::StartForwardUdp => {
            if args.service.service_type != ServiceType::Udp {
                bail!("Expect UDP traffic. Please check the configuration.")
            }
            run_data_channel_for_udp::<T>(conn, &args.service.local_addr).await?;
        }
        v => {
            bail!("Unexpected message: {:?}", v);
        }
    }
    Ok(())
}

// Simply copying back and forth for TCP
#[instrument(skip(conn))]
async fn run_data_channel_for_tcp<T: Transport>(
    mut conn: T::Stream,
    local_addr: &str,
) -> Result<()> {
    debug!("New data channel starts forwarding");

    let mut local = TcpStream::connect(local_addr)
        .await
        .with_context(|| format!("Failed to connect to {}", local_addr))?;
    let _ = copy_bidirectional(&mut conn, &mut local).await;
    Ok(())
}

// Things get a little tricker when it gets to UDP because it's connection-less.
// A UdpPortMap must be maintained for recent seen incoming address, giving them
// each a local port, which is associated with a socket. So just the sender
// to the socket will work fine for the map's value.
type UdpPortMap = Arc<tokio::sync::RwLock<HashMap<SocketAddr, mpsc::Sender<Bytes>>>>;

#[instrument(skip(conn))]
async fn run_data_channel_for_udp<T: Transport>(conn: T::Stream, local_addr: &str) -> Result<()> {
    debug!("New data channel starts forwarding");

    let port_map: UdpPortMap = Arc::new(tokio::sync::RwLock::new(HashMap::new()));

    // The channel stores UdpTraffic that needs to be sent to the server
    let (outbound_tx, mut outbound_rx) = mpsc::channel::<UdpTraffic>(UDP_SENDQ_SIZE);

    // FIXME: https://github.com/tokio-rs/tls/issues/40
    // Maybe this is our concern
    let (mut rd, mut wr) = io::split(conn);

    // Keep sending items from the outbound channel to the server
    tokio::spawn(async move {
        while let Some(t) = outbound_rx.recv().await {
            trace!("outbound {:?}", t);
            if let Err(e) = t
                .write(&mut wr)
                .await
                .with_context(|| "Failed to forward UDP traffic to the server")
            {
                debug!("{:?}", e);
                break;
            }
        }
    });

    loop {
        // Read a packet from the server
        let hdr_len = rd.read_u8().await?;
        let packet = UdpTraffic::read(&mut rd, hdr_len)
            .await
            .with_context(|| "Failed to read UDPTraffic from the server")?;
        let m = port_map.read().await;

        if m.get(&packet.from).is_none() {
            // This packet is from a address we don't see for a while,
            // which is not in the UdpPortMap.
            // So set up a mapping (and a forwarder) for it

            // Drop the reader lock
            drop(m);

            // Grab the writer lock
            // This is the only thread that will try to grab the writer lock
            // So no need to worry about some other thread has already set up
            // the mapping between the gap of dropping the reader lock and
            // grabbing the writer lock
            let mut m = port_map.write().await;

            match udp_connect(local_addr).await {
                Ok(s) => {
                    let (inbound_tx, inbound_rx) = mpsc::channel(UDP_SENDQ_SIZE);
                    m.insert(packet.from, inbound_tx);
                    tokio::spawn(run_udp_forwarder(
                        s,
                        inbound_rx,
                        outbound_tx.clone(),
                        packet.from,
                        port_map.clone(),
                    ));
                }
                Err(e) => {
                    error!("{:#}", e);
                }
            }
        }

        // Now there should be a udp forwarder that can receive the packet
        let m = port_map.read().await;
        if let Some(tx) = m.get(&packet.from) {
            let _ = tx.send(packet.data).await;
        }
    }
}

// Run a UdpSocket for the visitor `from`
#[instrument(skip_all, fields(from))]
async fn run_udp_forwarder(
    s: UdpSocket,
    mut inbound_rx: mpsc::Receiver<Bytes>,
    outbount_tx: mpsc::Sender<UdpTraffic>,
    from: SocketAddr,
    port_map: UdpPortMap,
) -> Result<()> {
    debug!("Forwarder created");
    let mut buf = BytesMut::new();
    buf.resize(UDP_BUFFER_SIZE, 0);

    loop {
        tokio::select! {
            // Receive from the server
            data = inbound_rx.recv() => {
                if let Some(data) = data {
                    s.send(&data).await?;
                } else {
                    break;
                }
            },

            // Receive from the service
            val = s.recv(&mut buf) => {
                let len = match val {
                    Ok(v) => v,
                    Err(_) => break
                };

                let t = UdpTraffic{
                    from,
                    data: Bytes::copy_from_slice(&buf[..len])
                };

                outbount_tx.send(t).await?;
            },

            // No traffic for the duration of UDP_TIMEOUT, clean up the state
            _ = time::sleep(Duration::from_secs(UDP_TIMEOUT)) => {
                break;
            }
        }
    }

    let mut port_map = port_map.write().await;
    port_map.remove(&from);

    debug!("Forwarder dropped");
    Ok(())
}

async fn handle_command<T: Transport + 'static>(
    conn: &mut T::Stream,
    result_tx: broadcast::Sender<CommandResult>,
    config: Arc<RwLock<ClientConfig>>,
    service_handles: &HashMap<String, ServerEndpoint>,
    e: Commands,
) -> Result<()> {
    debug!("Handle command: {:?}", e);
    match e {
        Commands::Publish(args) => {
            let retry_interval = config.read().retry_interval;
            let endpoint = if args.protocol == ServiceType::OneC {
                crate::mod_1c::publish(&args, config).await?;
                ClientEndpoint {
                    name: args.name.clone(),
                    service_type: ServiceType::Tcp,
                    local_addr: "127.0.0.1:5050".to_string(),
                    retry_interval: Some(retry_interval),
                    nodelay: Some(true),
                }
            } else {
                ClientEndpoint {
                    name: args.name.clone(),
                    service_type: args.protocol,
                    local_addr: args.address.clone(),
                    retry_interval: Some(retry_interval),
                    nodelay: Some(true),
                }
            };
            write_message(conn, &Message::EndpointStart(endpoint)).await?;
        }

        Commands::Unpublish(args) => {
            write_message(conn, &Message::EndpointStop(args.id)).await?;
        }

        Commands::Ls => {
            result_tx.send(CommandResult::ServiceList(service_handles.clone()))?;
        }

        Commands::Setup1C(args) => {
            crate::mod_1c::setup(args, config).await?;
            result_tx.send(CommandResult::Exit)?;
        }

        Commands::Cleanup1C => {
            crate::mod_1c::cleanup(config).await?;
            result_tx.send(CommandResult::Exit)?;
        }

        Commands::Run => {
            bail!("Service already running");
        }

        other => {
            bail!("Unsupported command: {:?}", other);
        }
    };
    Ok(())
}

async fn run_control_channel<T: Transport + 'static>(
    config: Arc<RwLock<ClientConfig>>,
    transport: Arc<T>,
    mut command_rx: broadcast::Receiver<Commands>,
    result_tx: broadcast::Sender<CommandResult>,
    mut shutdown_rx: broadcast::Receiver<()>,
    service_handles: &mut HashMap<String, ServerEndpoint>,
) -> Result<()> {
    let mut remote_addr = AddrMaybeCached::new(&config.read().remote_addr);
    remote_addr.resolve().await?;

    let mut conn = transport
        .connect(&remote_addr)
        .await
        .context(format!("Failed to connect to {}", &remote_addr))?;

    T::hint(&conn, SocketOpts::for_control_channel());

    // Send hello
    debug!("Sending hello");
    let agent_info = AgentInfo {
        agent_id: config.read().agent_id.clone(),
        token: config.read().token.clone().unwrap(),
    };

    let hello_send = Message::AgentHello(agent_info);

    write_message(&mut conn, &hello_send).await?;

    debug!("Reading ack");
    match read_message(&mut conn).await? {
        Message::AgentAck => {}
        Message::Error(kind, msg) => {
            result_tx.send(CommandResult::Error(kind.clone(), msg.clone()))?;
            bail!("Error: {:?} {}", kind, msg);
        }
        v => bail!("Unexpected ack message: {:?}", v),
    };

    debug!("Control channel established");

    result_tx.send(CommandResult::Connected)?;
    loop {
        let remote_addr = remote_addr.clone();
        let heartbeat_timeout = config.read().heartbeat_timeout;
        tokio::select! {
            e = command_rx.recv() => {
                if let Ok(e) = e {
                    match handle_command::<T>(&mut conn, result_tx.clone(), config.clone(), &service_handles, e).await {
                        Ok(()) => {
                        },
                        Err(err) => {
                            result_tx.send(err.into())?;
                        }
                    }
                } else {
                    break;
                }
            },
            val = read_message(&mut conn) => {
                let val = val?;
                debug!("Received message {:?}", val);
                match val {
                    Message::CreateDataChannel(endpoint) => {
                        let socket_opts = SocketOpts::nodelay(endpoint.client.nodelay.clone());
                        let data_ch_args = Arc::new(RunDataChannelArgs {
                            agent_id: config.read().agent_id.clone(),
                            channel_id: endpoint.channel_id,
                            remote_addr,
                            connector: transport.clone(),
                            socket_opts,
                            service: endpoint.client.clone(),
                        });
                        tokio::spawn(async move {
                            if let Err(e) = run_data_channel(data_ch_args).await.context("Failed to run the data channel") {
                                error!("{:?}", e);
                            }
                        });
                    },
                    Message::EndpointAck(endpoint) => {
                        service_handles.insert(endpoint.channel_id.clone(), endpoint.clone());
                        result_tx.send(CommandResult::Published(endpoint))?;
                    },
                    Message::HeartBeat => (),
                    v => {
                        bail!("Unexpected message: {:?}", v);
                    }
                }
            },
            _ = time::sleep(Duration::from_secs(heartbeat_timeout)), if heartbeat_timeout != 0 => {
                return Err(anyhow!("Heartbeat timed out"))
            }
            _ = shutdown_rx.recv() => {
                debug!("Shutting down gracefully...");
                break;
            }
        }
    }

    info!("Control channel shutdown");
    result_tx.send(CommandResult::Disconnected)?;
    Ok(())
}
