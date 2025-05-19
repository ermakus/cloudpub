use anyhow::{anyhow, bail, Context, Result};
use backoff::backoff::Backoff;
use backoff::future::retry_notify;
use backoff::ExponentialBackoff;
use bytes::{Bytes, BytesMut};
use common::config::TransportType;
use common::protocol::message::Message;
use common::protocol::{
    read_message, write_message, AgentInfo, ConnectState, DataChannelInfo, EndpointRemove,
    EndpointStop, ErrorInfo, ErrorKind, HeartBeat, Protocol, ServerEndpoint, UdpTraffic,
};
use common::transport::{
    AddrMaybeCached, SocketOpts, TcpTransport, TlsTransport, Transport, WebsocketTransport,
};
use common::utils::{get_platform, udp_connect};
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

use common::constants::{
    run_control_chan_backoff, DEFAULT_CLIENT_RETRY_INTERVAL_SECS, UDP_BUFFER_SIZE, UDP_SENDQ_SIZE,
    UDP_TIMEOUT,
};

use crate::config::ClientConfig;
use crate::shell::SubProcess;
use machineid_rs::{Encryption, HWIDComponent, IdBuilder};
use std::fmt::{self, Debug, Formatter};

#[cfg(feature = "plugins")]
use crate::plugins::registry::PluginRegistry;

struct DataChannel<T: Transport> {
    agent_id: String,
    remote_addr: AddrMaybeCached,
    connector: Arc<T>,
    socket_opts: SocketOpts,
    endpoint: ServerEndpoint,
}

type Service<T> = Arc<DataChannel<T>>;

type Services<T> = Arc<RwLock<HashMap<String, Service<T>>>>;

impl<T: Transport> Debug for DataChannel<T> {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.write_str(&self.endpoint.client.as_ref().unwrap().to_string())
    }
}

// Holds the state of a client
struct Client<T: Transport> {
    config: Arc<RwLock<ClientConfig>>,
    services: Services<T>,
    transport: Arc<T>,
    servers: HashMap<String, (SubProcess, u16)>,
    connected: bool,
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
            connected: false,
        })
    }

    // The entrypoint of Client
    async fn run(
        &mut self,
        command_rx: broadcast::Receiver<Message>,
        result_tx: broadcast::Sender<Message>,
    ) -> Result<()> {
        let result_tx = result_tx.clone();
        let transport = self.transport.clone();

        let config = self.config.clone();
        let services = self.services.clone();

        let mut retry_backoff = run_control_chan_backoff(DEFAULT_CLIENT_RETRY_INTERVAL_SECS);

        let mut start = Instant::now();
        result_tx
            .send(Message::ConnectState(ConnectState::Connecting.into()))
            .context("Can't send Connecting event")?;
        while let Err(err) = self
            .run_control_channel(
                config.clone(),
                transport.clone(),
                command_rx.resubscribe(),
                result_tx.clone(),
            )
            .await
        {
            if result_tx.receiver_count() == 0 {
                // The client is shutting down
                break;
            }

            if self.connected {
                result_tx
                    .send(Message::Error(ErrorInfo {
                        kind: ErrorKind::HandshakeFailed.into(),
                        message: "Ошибка сети, пробуем еще раз.".to_string(),
                    }))
                    .context("Can't send Error event")?;
                result_tx
                    .send(Message::ConnectState(ConnectState::Disconnected.into()))
                    .context("Can't send Disconnected event")?;
                result_tx
                    .send(Message::ConnectState(ConnectState::Connecting.into()))
                    .context("Can't send Connecting event")?;
                self.connected = false;
            }

            services.write().clear();

            if start.elapsed() > Duration::from_secs(3) {
                // The client runs for at least 3 secs and then disconnects
                retry_backoff.reset();
            }

            if let Some(duration) = retry_backoff.next_backoff() {
                warn!("{:#}. Retry in {:?}...", err, duration);
                time::sleep(duration).await;
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
        mut command_rx: broadcast::Receiver<Message>,
        result_tx: broadcast::Sender<Message>,
    ) -> Result<()> {
        let url = config.read().server.clone();
        let port = url.port().unwrap_or(443);
        let host = url.host_str().context("Failed to get host")?;
        let mut host_and_port = format!("{}:{}", host, port);

        let (mut conn, remote_addr) = loop {
            let mut remote_addr = AddrMaybeCached::new(&host_and_port);
            remote_addr
                .resolve()
                .await
                .context("Failed to resolve server address")?;

            let mut conn = transport.connect(&remote_addr).await.context(format!(
                "Failed to connect control channel to {}",
                &host_and_port
            ))?;

            self.connected = true;

            T::hint(&conn, SocketOpts::for_control_channel());

            // Send hello
            let hwid = IdBuilder::new(Encryption::SHA256)
                .add_component(HWIDComponent::OSName)
                .add_component(HWIDComponent::SystemID)
                .add_component(HWIDComponent::MachineName)
                .add_component(HWIDComponent::CPUID)
                .build("cloudpub")
                .unwrap_or_default();

            let hwid = config
                .read()
                .hwid
                .as_ref()
                .map(|s| s.to_string())
                .unwrap_or(hwid);

            let (email, password) = if let Some(ref cred) = config.read().credentials {
                (cred.0.clone(), cred.1.clone())
            } else {
                (String::new(), String::new())
            };

            let token = config.read().token.clone().unwrap_or_default().to_string();

            let agent_info = AgentInfo {
                agent_id: config.read().agent_id.clone(),
                token,
                email,
                password,
                hostname: hostname::get()?.into_string().unwrap(),
                version: VERSION.to_string(),
                gui: config.read().gui,
                platform: get_platform(),
                hwid,
                server_host_and_port: remote_addr.to_string(),
            };

            debug!("Sending hello: {:?}", agent_info);

            let hello_send = Message::AgentHello(agent_info);

            write_message(&mut conn, &hello_send)
                .await
                .context("Failed to send hello message")?;

            debug!("Reading ack");
            match read_message(&mut conn)
                .await
                .context("Failed to read ack message")?
            {
                Message::AgentAck(args) => {
                    if !args.token.is_empty() {
                        let mut c = config.write();
                        c.token = Some(args.token.as_str().into());
                        c.save().context("Write config")?;
                    }
                    break (conn, remote_addr);
                }
                Message::Redirect(r) => {
                    host_and_port = r.host_and_port;
                    debug!("Redirecting to {}", host_and_port);
                    continue;
                }
                Message::Error(err) => {
                    result_tx
                        .send(Message::Error(err.clone()))
                        .context("Can't send server error event")?;
                    bail!("Error: {:?}", err.kind);
                }
                v => bail!("Unexpected ack message: {:?}", v),
            };
        };

        debug!("Control channel established");

        result_tx
            .send(Message::ConnectState(ConnectState::Connected.into()))
            .context("Can't send Connected event")?;

        let (command_tx2, mut command_rx2) = mpsc::channel::<Message>(1);

        let heartbeat_timeout = config.read().heartbeat_timeout;

        loop {
            let remote_addr = remote_addr.clone();
            tokio::select! {
                cmd = command_rx2.recv() => {
                    if let Some(cmd) = cmd {
                        write_message(&mut conn, &cmd).await.context("Failed to send command")?;
                    }
                },
                cmd = command_rx.recv() => {
                    if let Ok(cmd) = cmd {
                        match cmd {
                            Message::EndpointStart(client) => {
                                info!("Publishing service: {:?}", client);
                                let protocol: Protocol = client.local_proto.try_into().unwrap();
                                let server_endpoint = ServerEndpoint {
                                    guid: String::new(),
                                    client: Some(client.clone()),
                                    status: Some("offline".to_string()),
                                    remote_proto: protocol.into(),
                                    remote_addr: String::new(),
                                    remote_port: 0,
                                    id: 0,
                                    bind_addr: String::new(),
                                };

                                result_tx.send(Message::EndpointAck(server_endpoint.clone())).context("Can't send Published event")?;

                                let result_tx = result_tx.clone();
                                let command_rx = command_rx.resubscribe();
                                let command_tx2 = command_tx2.clone();
                                let config = config.clone();

                                tokio::spawn(async move {
                                    handle_endpoint_start(protocol, config, command_rx, result_tx, command_tx2, client).await.ok();
                                });

                            }

                            Message::EndpointStop(ep) => {
                                info!("Unpublishing service: {:?}", ep.guid);
                                // Stop server process if needed
                                if let Some(mut srv) = self.servers.remove(&ep.guid) {
                                    srv.0.stop();
                                }
                                let msg = Message::EndpointStop(EndpointStop { guid: ep.guid });
                                write_message(&mut conn, &msg).await.context("Failed to send message")?;

                            }

                            Message::EndpointRemove(ep) => {
                                info!("Remove service: {:?}", ep.guid);
                                // Stop server process if needed
                                if let Some(mut srv) = self.servers.remove(&ep.guid) {
                                    srv.0.stop();
                                }
                                let msg = Message::EndpointRemove(EndpointRemove { guid: ep.guid });
                                write_message(&mut conn, &msg).await.context("Failed to send message")?;
                            }

                            Message::Stop(_) => {
                                info!("Stopping the client");
                                break;
                            }
                            cmd => {
                                write_message(&mut conn, &cmd).await.context("Failed to send message")?;
                            }
                        };
                    } else {
                        debug!("No more commands, shutting down...");
                        break;
                    }
                },
                val = read_message(&mut conn) => {
                    let val = val?;
                    match val {
                        Message::CreateDataChannel(mut endpoint) => {

                            let socket_opts = SocketOpts::nodelay(endpoint.client.as_ref().unwrap().nodelay);
                            if let Some(s) = self.servers.get(&endpoint.guid) {
                                let client = endpoint.client.as_mut().unwrap();
                                client.local_port = s.1 as u32;
                                client.local_addr = "localhost".to_string();
                                Some(s.1)
                            } else {
                                let protocol: Protocol = endpoint.client.as_ref().unwrap().local_proto.try_into().context("Unsupported protocol")?;
                                debug!("Publish service: {:?}", endpoint);
                                let res: Option<anyhow::Result<SubProcess>> = match protocol {
                                    #[cfg(feature = "plugins")]
                                    Protocol::OneC | Protocol::Minecraft | Protocol::Webdav => {
                                        if let Ok(plugin) = PluginRegistry::new().get(protocol) {
                                            Some(plugin.publish(&mut endpoint, config.clone(), result_tx.clone()).await)
                                        } else {
                                            None
                                        }
                                    },
                                    _ => {
                                        None
                                    }
                                };
                                match res {
                                    Some(Ok(p)) => {
                                        self.servers.insert(endpoint.guid.clone(), (p, endpoint.client.as_ref().unwrap().local_port as u16));
                                    }
                                    Some(Err(err)) => {
                                        error!("{:?}", err);
                                        result_tx.send(Message::Error(
                                            ErrorInfo {
                                                kind: ErrorKind::Fatal.into(),
                                                message: err.to_string()
                                            })
                                        ).context("Can't send Error event")?;
                                        continue;
                                    }
                                    None => {}
                                }
                                None
                            };


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
                                debug!("Data channel shutdown");
                            });
                        },
                        Message::HeartBeat(_) => {
                            write_message(&mut conn, &Message::HeartBeat(HeartBeat{})).await.context("Failed to send heartbeat")?;
                        },
                        v => {
                            result_tx.send(v).context("Can't send server message")?;
                        }
                    }
                },
                _ = time::sleep(Duration::from_secs(heartbeat_timeout)), if heartbeat_timeout != 0 => {
                    return Err(anyhow!("Heartbeat timed out"))
                }
            }
        }

        info!("Control channel shutdown");
        result_tx
            .send(Message::ConnectState(ConnectState::Disconnected.into()))
            .context("Can't send Disconnected event")?;
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
    .await
    .context("Failed to connect to the data remote address")?;

    T::hint(&conn, service.socket_opts);

    let hello = Message::DataChannelHello(DataChannelInfo {
        agent_id: service.agent_id.clone(),
        guid: service.endpoint.guid.clone(),
    });
    write_message(&mut conn, &hello)
        .await
        .context("Failed to send data hello message")?;
    Ok(conn)
}

#[instrument]
async fn run_data_channel<T: Transport>(service: Service<T>) -> Result<()> {
    // Do the handshake
    let mut conn = do_data_channel_handshake(service.clone())
        .await
        .context("Failed to handshake data channel")?;

    let client = service.endpoint.client.as_ref().unwrap();
    let (local_addr, local_port) = (client.local_addr.clone(), client.local_port as u16);

    tokio::select! {
    // Forward
        msg = read_message(&mut conn) => {
            match msg {
                Ok(Message::StartForwardTcp(_)) => {
                    run_data_channel_for_tcp::<T>(conn,  &local_addr, local_port).await.context("Failed to run TCP data channel")?;
                }
                Ok(Message::StartForwardUdp(_)) => {
                    run_data_channel_for_udp::<T>(conn, &local_addr, local_port).await.context("Failed to run UDP data channel")?;
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
                    s.send(&data).await.with_context(|| "Failed to send UDP traffic to the service")?;
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

                outbount_tx.send(t).await.with_context(|| "Failed to send UDP traffic to the server")?;
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
async fn setup_plugin(
    protocol: Protocol,
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Message>,
    result_tx: broadcast::Sender<Message>,
) -> anyhow::Result<()> {
    match protocol {
        #[cfg(feature = "plugins")]
        Protocol::Webdav | Protocol::OneC | Protocol::Minecraft => {
            if let Ok(plugin) = PluginRegistry::new().get(protocol) {
                plugin.setup(config, command_rx, result_tx).await
            } else {
                Err(anyhow!(
                    "Unsupported protocol: no plugin found for {:?}",
                    protocol
                ))
            }
        }
        #[cfg(not(feature = "plugins"))]
        Protocol::Webdav | Protocol::OneC | Protocol::Minecraft => Err(anyhow!(
            "Unsupported protocol: plugins support is not enabled"
        )),
        Protocol::Tcp | Protocol::Udp | Protocol::Http | Protocol::Https | Protocol::Rtsp => Ok(()),
    }
}

async fn handle_endpoint_start(
    protocol: Protocol,
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Message>,
    result_tx: broadcast::Sender<Message>,
    command_tx2: mpsc::Sender<Message>,
    client: common::protocol::ClientEndpoint,
) -> anyhow::Result<()> {
    let err = setup_plugin(protocol, config, command_rx, result_tx.clone()).await;

    if let Err(err) = err {
        error!("{:?}", err);
        result_tx
            .send(Message::Error(ErrorInfo {
                kind: ErrorKind::Fatal.into(),
                message: err.to_string(),
            }))
            .context("Can't send Error event")?;
    }
    command_tx2
        .send(Message::EndpointStart(client))
        .await
        .context("Failed to send EndpointStart message")?;
    Ok(())
}

pub async fn run_client(
    config: Arc<RwLock<ClientConfig>>,
    command_rx: broadcast::Receiver<Message>,
    result_tx: broadcast::Sender<Message>,
) -> Result<()> {
    let transport_type = config.read().transport.transport_type;
    match transport_type {
        TransportType::Tcp => {
            let mut client = Client::<TcpTransport>::from(config)
                .await
                .context("Failed to create TCP client")?;
            client.run(command_rx, result_tx).await
        }
        TransportType::Tls => {
            let mut client = Client::<TlsTransport>::from(config)
                .await
                .context("Failed to create TLS client")?;
            client.run(command_rx, result_tx).await
        }
        TransportType::Websocket => {
            let mut client = Client::<WebsocketTransport>::from(config)
                .await
                .context("Failed to create Websocket client")?;
            client.run(command_rx, result_tx).await
        }
    }
}
