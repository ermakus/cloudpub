use backoff::ExponentialBackoff;
use std::time::Duration;

/// Application-layer heartbeat interval in secs
pub const DEFAULT_HEARTBEAT_INTERVAL_SECS: u64 = 30;
pub const DEFAULT_HEARTBEAT_TIMEOUT_SECS: u64 = 40;

/// Client
pub const DEFAULT_CLIENT_RETRY_INTERVAL_SECS: u64 = 1;
pub const DEFAULT_SERVER: &str = "endpoint.cloudpub.ru:443";

/// Server
pub const TCP_POOL_SIZE: usize = 8; // The number of cached connections for TCP servies
pub const UDP_POOL_SIZE: usize = 2; // The number of cached connections for UDP services
pub const CHAN_SIZE: usize = 2048; // The capacity of various chans
pub const HANDSHAKE_TIMEOUT: u64 = 5; // Timeout for transport handshake

/// TCP
pub const DEFAULT_NODELAY: bool = true;
pub const DEFAULT_KEEPALIVE_SECS: u64 = 20;
pub const DEFAULT_KEEPALIVE_INTERVAL: u64 = 8;

// FIXME: Determine reasonable size
/// UDP MTU. Currently far larger than necessary
pub const UDP_BUFFER_SIZE: usize = 2048;
pub const UDP_SENDQ_SIZE: usize = 1024;
pub const UDP_TIMEOUT: u64 = 60;

pub fn listen_backoff() -> ExponentialBackoff {
    ExponentialBackoff {
        max_elapsed_time: None,
        max_interval: Duration::from_secs(1),
        ..Default::default()
    }
}

pub fn run_control_chan_backoff(interval: u64) -> ExponentialBackoff {
    ExponentialBackoff {
        randomization_factor: 0.2,
        max_elapsed_time: None,
        multiplier: 3.0,
        max_interval: Duration::from_secs(interval),
        ..Default::default()
    }
}
