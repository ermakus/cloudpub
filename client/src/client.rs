use anyhow::{anyhow, bail, Context, Result};
use backoff::backoff::Backoff;
use backoff::future::retry_notify;
use backoff::ExponentialBackoff;
use bytes::{Bytes, BytesMut};
use common::config::TransportType;
use common::helper::udp_connect;
use common::protocol::{
    read_message, write_message, AgentInfo, DataChannelInfo, ErrorKind, Message, Protocol,
    ServerEndpoint, UdpTraffic,
};
use common::transport::{
    AddrMaybeCached, SocketOpts, TcpTransport, TlsTransport, Transport, WebsocketTransport,
};
use common::utils::get_platform;
use common::version::VERSION;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{self, copy_bidirectional, AsyncReadExt};
use tokio::net::{TcpStream, UdpSocket};
use tokio::sync::{broadcast, mpsc};
use tokio::time::{self, Duration, Instant};
use tracing::{debug, error, info, instrument, trace, warn};

use common::constants::{run_control_chan_backoff, UDP_BUFFER_SIZE, UDP_SENDQ_SIZE, UDP_TIMEOUT};
use common::utils::find_free_tcp_port;

use crate::commands::{CommandResult, Commands};
use crate::config::ClientConfig;
use crate::shell::SubProcess;

struct DataChannel<T: Transport> {
    agent_id: String,
    remote_addr: AddrMaybeCached,
    connector: Arc<T>,
    socket_opts: SocketOpts,
    endpoint: ServerEndpoint,
}

type Service<T> = Arc<DataChannel<T>>;

type Services<T> = Arc<RwLock<HashMap<String, Service<T>>>>;

// Holds the state of a client
struct Client<T: Transport> {
    config: Arc<RwLock<ClientConfig>>,
    services: Services<T>,
    transport: Arc<T>,
    servers: HashMap<String, (SubProcess, u16)>,
}

impl<T: 'static + Transport> Client<T> {
    // Create a Client from `[client]` config block
    async fn from(config: Arc<RwLock<ClientConfig>>) -> Result<Client<T>> {
        let transport = Arc::new(
            T::new(&config.clone().read().transport)
                .with_context(|| "Failed to create the transport")?,
        );
        Ok(Client {
            config,
            services: Default::default(),
            servers: Default::default(),
            transport,
        })
    }

    // The entrypoint of Client
    async fn run(
        &mut self,
        mut command_rx: broadcast::Receiver<Commands>,
        result_tx: broadcast::Sender<CommandResult>,
    ) -> Result<()> {
        let result_tx = result_tx.clone();
        let transport = self.transport.clone();

        let config = self.config.clone();
        let services = self.services.clone();

        let mut retry_backoff = run_control_chan_backoff(config.read().retry_interval);

        let mut start = Instant::now();
        result_tx.send(CommandResult::Connecting)?;
        while let Err(err) = self
            .run_control_channel(
                config.clone(),
                transport.clone(),
                command_rx.resubscribe(),
                result_tx.clone(),
            )
            .await
        {
            error!("Control channel error: {:?}", err);
            let is_disconnected = !services.read().is_empty();

            if is_disconnected {
                result_tx.send(CommandResult::Error(
                    ErrorKind::HandshakeFailed,
                    "Ошибка сети, пробуем еще раз.".to_string(),
                ))?;
                result_tx.send(CommandResult::Disconnected)?;
                result_tx.send(CommandResult::Connecting)?;
            }

            services.write().clear();

            if start.elapsed() > Duration::from_secs(3) {
                // The client runs for at least 3 secs and then disconnects
                retry_backoff.reset();
            }

            if let Some(duration) = retry_backoff.next_backoff() {
                warn!("{:#}. Retry in {:?}...", err, duration);
                tokio::select! {
                    _ = time::sleep(duration) => {},
                    command = command_rx.recv() => {
                        if matches!(command, Ok(Commands::Stop)) {
                            break;
                        }
                    }
                }
            }

            start = Instant::now();
        }

        services.write().clear();

        Ok(())
    }

    async fn run_control_channel(
        &mut self,
        config: Arc<RwLock<ClientConfig>>,
        transport: Arc<T>,
        mut command_rx: broadcast::Receiver<Commands>,
        result_tx: broadcast::Sender<CommandResult>,
    ) -> Result<()> {
        config.read().validate().context("Invalid configuration")?;

        let url = config.read().server.clone();
        let port = url.port().unwrap_or(443);
        let host = url.host_str().context("Failed to get host")?;
        let host_and_port = format!("{}:{}", host, port);

        let mut remote_addr = AddrMaybeCached::new(&host_and_port);
        remote_addr
            .resolve()
            .await
            .context("Failed to resolve server address")?;

        let mut conn = transport.connect(&remote_addr).await.context(format!(
            "Failed to connect control channel to {}",
            &host_and_port
        ))?;

        T::hint(&conn, SocketOpts::for_control_channel());

        // Send hello
        debug!("Sending hello");

        let agent_info = AgentInfo {
            agent_id: config.read().agent_id.clone(),
            token: config.read().token.clone().unwrap(),
            hostname: hostname::get()?.into_string().unwrap(),
            version: VERSION.to_string(),
            gui: config.read().gui,
            platform: get_platform(),
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
                cmd = command_rx.recv() => {
                    if let Ok(cmd) = cmd {
                        match cmd {
                            Commands::Publish(service) | Commands::Register(service) => {
                                let server_endpoint = ServerEndpoint {
                                    guid: String::new(),
                                    client: service.clone().into(),
                                    status: Some("offline".to_string()),
                                    remote_proto: service.protocol,
                                    remote_addr: String::new(),
                                    remote_port: 0,
                                    bind_addr: String::new(),
                                    id: None,
                                };

                                result_tx.send(CommandResult::Published(server_endpoint))?;

                                let err = match service.protocol {
                                    Protocol::WebDav => {
                                        crate::webdav::setup(config.clone(), command_rx.resubscribe(), result_tx.clone()).await
                                    }
                                    Protocol::OneC => {
                                        crate::onec::setup(config.clone(), command_rx.resubscribe(), result_tx.clone()).await
                                    }
                                    Protocol::Minecraft => {
                                        crate::minecraft::setup(config.clone(), command_rx.resubscribe(), result_tx.clone()).await
                                    }
                                    Protocol::Tcp | Protocol::Udp | Protocol::Http | Protocol::Https => {
                                        Ok(())
                                    }

                                };

                                    if let Err(err) = err
                                     {
                                        error!("{:?}", err);
                                        result_tx.send(CommandResult::Error(ErrorKind::Fatal, err.to_string()))?;
                                        continue;
                                    }
                                info!("Publishing service: {:?}", service);
                                let msg = Message::EndpointStart(service.into());
                                write_message(&mut conn, &msg).await.context("Failed to send message")?;
                            }
                            Commands::Unpublish(service) => {
                                info!("Unpublishing service: {:?}", service);
                                let msg = Message::EndpointStop(service.guid.clone());
                                write_message(&mut conn, &msg).await.context("Failed to send message")?;

                                // Stop server process if needed
                                if let Some(mut srv) = self.servers.remove(&service.guid) {
                                    srv.0.stop();
                                }

                                if service.remove {
                                    result_tx.send(CommandResult::Removed(service.guid))?;
                                } else {
                                    result_tx.send(CommandResult::Unpublished(service.guid))?;
                                }
                            }
                            Commands::Stop => {
                                debug!("Shutting down gracefully...");
                                break;
                            }
                            Commands::Break => {
                                debug!("Break signal");
                            }
                            _ => unreachable!(),
                        };
                    } else {
                        debug!("No more commands, shutting down...");
                        break;
                    }
                },
                val = read_message(&mut conn) => {
                    let val = val?;
                    debug!("Received message {:?}", val);
                    match val {
                        Message::CreateDataChannel(mut endpoint) => {

                            let socket_opts = SocketOpts::nodelay(endpoint.client.nodelay.clone());

                            let maybe_port = if let Some(s) = self.servers.get(&endpoint.guid) {
                                endpoint.client.local_port = s.1;
                                endpoint.client.local_addr = "localhost".to_string();
                                Some(s.1)
                            } else {
                                None
                            };

                            if maybe_port.is_none() {
                                let res = match endpoint.client.local_proto {
                                    Protocol::OneC => {
                                        endpoint.client.local_port = find_free_tcp_port().await?;
                                        Some(crate::onec::publish(&endpoint, config.clone(),result_tx.clone()).await)
                                    },
                                    Protocol::Minecraft => {
                                        endpoint.client.local_port = find_free_tcp_port().await?;
                                        Some(crate::minecraft::publish(&endpoint, config.clone(),result_tx.clone()).await)
                                    },
                                    Protocol::WebDav => {
                                        endpoint.client.local_port = find_free_tcp_port().await?;
                                        Some(crate::webdav::publish(&endpoint, config.clone(),result_tx.clone()).await)
                                    },
                                    _ => {
                                        None
                                    }
                                };
                                match res {
                                    Some(Ok(p)) => {
                                        endpoint.client.local_addr = "localhost".to_string();
                                        self.servers.insert(endpoint.guid.clone(), (p, endpoint.client.local_port));
                                    }
                                    Some(Err(err)) => {
                                        error!("{:?}", err);
                                        result_tx.send(CommandResult::Error(ErrorKind::Fatal, err.to_string()))?;
                                        continue;
                                    }
                                    None => {}
                                }
                            }


                            let service = Arc::new(DataChannel {
                                agent_id: config.read().agent_id.clone(),
                                remote_addr,
                                connector: transport.clone(),
                                socket_opts,
                                endpoint: endpoint.clone(),
                            });
                            self.services.write().insert(endpoint.guid.clone(), service.clone());
                            tokio::spawn(async move {
                                if let Err(e) = run_data_channel(service).await.context("Failed to run the data channel") {
                                    error!("{:?}", e);
                                }
                                info!("Data channel shutdown");
                            });
                        },
                        Message::EndpointAck(endpoint) => {
                            result_tx.send(CommandResult::Published(endpoint))?;
                        },
                        Message::HeartBeat => (),
                        Message::Error(kind, msg) => {
                            info!("Server error: {:?} {}", kind, msg);
                            result_tx.send(CommandResult::Error(kind.clone(), msg.clone()))?;
                        },
                        Message::UpgradeAvailable(info) => {
                            info!("Upgrade available: {:?}", info);
                            result_tx.send(CommandResult::UpgradeAvailable(info))?;
                        },
                        v => {
                            warn!("Unexpected message: {:?}", v);
                        }
                    }
                },
                _ = time::sleep(Duration::from_secs(heartbeat_timeout)), if heartbeat_timeout != 0 => {
                    return Err(anyhow!("Heartbeat timed out"))
                }
            }
        }

        info!("Control channel shutdown");
        result_tx.send(CommandResult::Disconnected)?;
        Ok(())
    }
}

async fn do_data_channel_handshake<T: Transport>(service: Service<T>) -> Result<T::Stream> {
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
            service
                .connector
                .connect(&service.remote_addr)
                .await
                .with_context(|| {
                    format!(
                        "Failed to handshake data channel to {}",
                        &service.remote_addr
                    )
                })
                .map_err(backoff::Error::transient)
        },
        |e, duration| {
            warn!("{:#}. Retry in {:?}", e, duration);
        },
    )
    .await?;

    T::hint(&conn, service.socket_opts);

    let hello = Message::DataChannelHello(DataChannelInfo {
        agent_id: service.agent_id.clone(),
        guid: service.endpoint.guid.clone(),
    });
    write_message(&mut conn, &hello).await?;
    Ok(conn)
}

async fn run_data_channel<T: Transport>(service: Service<T>) -> Result<()> {
    // Do the handshake
    let mut conn = do_data_channel_handshake(service.clone()).await?;

    let (local_addr, local_port) = (
        service.endpoint.client.local_addr.clone(),
        service.endpoint.client.local_port,
    );

    tokio::select! {
    // Forward
        msg = read_message(&mut conn) => {
            match msg {
                Ok(Message::StartForwardTcp) => {
                    run_data_channel_for_tcp::<T>(conn,  &local_addr, local_port).await?;
                }
                Ok(Message::StartForwardUdp) => {
                    run_data_channel_for_udp::<T>(conn, &local_addr, local_port).await?;
                }
                Ok(msg) => {
                    warn!("Unexpected data channel message: {:?}", msg);
                }
                Err(e) => {
                    return Err(e)
                }
            }
        }
    }
    Ok(())
}

// Simply copying back and forth for TCP
#[instrument(skip(conn))]
async fn run_data_channel_for_tcp<T: Transport>(
    mut conn: T::Stream,
    local_addr: &str,
    local_port: u16,
) -> Result<()> {
    debug!("New data channel starts forwarding");

    let mut local = TcpStream::connect(format!("{}:{}", local_addr, local_port))
        .await
        .with_context(|| format!("Failed to local connect to {}:{}", local_addr, local_port))?;

    tokio::select! {
        _ = copy_bidirectional(&mut conn, &mut local) => {
            debug!("Remote -> Local done");
        },
    }

    Ok(())
}

// Things get a little tricker when it gets to UDP because it's connection-less.
// A UdpPortMap must be maintained for recent seen incoming address, giving them
// each a local port, which is associated with a socket. So just the sender
// to the socket will work fine for the map's value.
type UdpPortMap = Arc<tokio::sync::RwLock<HashMap<SocketAddr, mpsc::Sender<Bytes>>>>;

#[instrument(skip(conn))]
async fn run_data_channel_for_udp<T: Transport>(
    conn: T::Stream,
    local_addr: &str,
    local_port: u16,
) -> Result<()> {
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

            match udp_connect(format!("{}:{}", local_addr, local_port)).await {
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

// The entrypoint of running a client
pub async fn run_client(
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Commands>,
    result_tx: broadcast::Sender<CommandResult>,
) -> Result<()> {
    let transport_type = config.read().transport.transport_type;
    match transport_type {
        TransportType::Tcp => {
            let mut client = Client::<TcpTransport>::from(config).await?;
            client.run(command_rx, result_tx).await
        }
        TransportType::Tls => {
            let mut client = Client::<TlsTransport>::from(config).await?;
            client.run(command_rx, result_tx).await
        }
        TransportType::Websocket => {
            let mut client = Client::<WebsocketTransport>::from(config).await?;
            client.run(command_rx, result_tx).await
        }
    }
}
