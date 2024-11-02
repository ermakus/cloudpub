use crate::config::{TlsConfig, TransportConfig};
use crate::helper::host_port_pair;
use crate::transport::{
    AddrMaybeCached, Listener, SocketAddr, SocketOpts, Stream, TcpTransport, Transport,
};
use std::fmt::Debug;
use std::fs;
use std::sync::Arc;
use tokio_rustls::rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer, ServerName, UnixTime};

use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;
use p12::PFX;
use tokio_rustls::rustls::client::danger::{
    HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier,
};
use tokio_rustls::rustls::{
    ClientConfig, DigitallySignedStruct, Error, RootCertStore, ServerConfig, SignatureScheme,
};
pub(crate) use tokio_rustls::TlsStream;
use tokio_rustls::{TlsAcceptor, TlsConnector};
use tokio_unix_tcp::NamedSocketAddr;

pub struct TlsTransport {
    tcp: TcpTransport,
    config: TlsConfig,
    connector: Option<TlsConnector>,
    tls_acceptor: Option<TlsAcceptor>,
}

// workaround for TlsConnector and TlsAcceptor not implementing Debug
impl Debug for TlsTransport {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TlsTransport")
            .field("tcp", &self.tcp)
            .field("config", &self.config)
            .finish()
    }
}

fn load_server_config(config: &TlsConfig) -> Result<Option<ServerConfig>> {
    if let Some(pkcs12_path) = config.pkcs12.as_ref() {
        let buf = fs::read(pkcs12_path)?;
        let pfx = PFX::parse(buf.as_slice())?;
        let pass = config.pkcs12_password.as_ref().unwrap();

        let certs = pfx.cert_bags(pass)?;
        let keys = pfx.key_bags(pass)?;

        let chain: Vec<CertificateDer> = certs.into_iter().map(CertificateDer::from).collect();
        let key = PrivatePkcs8KeyDer::from(keys.into_iter().next().unwrap());

        Ok(Some(
            ServerConfig::builder()
                .with_no_client_auth()
                .with_single_cert(chain, key.into())?,
        ))
    } else {
        Ok(None)
    }
}

pub fn load_roots(config: &TlsConfig) -> Result<Vec<CertificateDer>> {
    let mut root_certs = Vec::new();

    if let Some(path) = config.trusted_root.as_ref() {
        let mut reader = std::io::BufReader::new(
            fs::File::open(path).context("Failed to open trusted root file")?,
        );
        for cert in rustls_pemfile::certs(&mut reader) {
            root_certs.push(cert.context("Failed to parse trusted root cert")?);
        }
    }

    let static_roots: &[u8] = include_bytes!("../../roots/GlobalSign_GCC_R3_DV_TLS_CA_2020.pem");
    let mut reader = std::io::BufReader::new(static_roots);

    for cert in rustls_pemfile::certs(&mut reader) {
        root_certs.push(cert.context("Failed to parse static root cert")?);
    }

    for cert in rustls_native_certs::load_native_certs().context("Failed to load native certs")? {
        root_certs.push(cert);
    }
    Ok(root_certs)
}

#[derive(Debug)]
struct NoVerifier;

impl ServerCertVerifier for NoVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        Ok(ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        vec![
            SignatureScheme::RSA_PKCS1_SHA1,
            SignatureScheme::ECDSA_SHA1_Legacy,
            SignatureScheme::RSA_PKCS1_SHA256,
            SignatureScheme::ECDSA_NISTP256_SHA256,
            SignatureScheme::RSA_PKCS1_SHA384,
            SignatureScheme::ECDSA_NISTP384_SHA384,
            SignatureScheme::RSA_PKCS1_SHA512,
            SignatureScheme::ECDSA_NISTP521_SHA512,
            SignatureScheme::RSA_PSS_SHA256,
            SignatureScheme::RSA_PSS_SHA384,
            SignatureScheme::RSA_PSS_SHA512,
            SignatureScheme::ED25519,
            SignatureScheme::ED448,
        ]
    }
}

pub fn load_client_config(config: &TlsConfig) -> Result<Option<ClientConfig>> {
    let mut root_certs = RootCertStore::empty();
    for cert in load_roots(config)? {
        root_certs.add(cert).ok();
    }
    let mut tls_config = ClientConfig::builder()
        .with_root_certificates(root_certs)
        .with_no_client_auth();

    Ok(Some(
        if config
            .danger_ignore_certificate_verification
            .unwrap_or(false)
        {
            tls_config
                .dangerous()
                .set_certificate_verifier(Arc::new(NoVerifier));
            tls_config
        } else {
            tls_config
        },
    ))
}

#[async_trait]
impl Transport for TlsTransport {
    type Acceptor = Listener;
    type RawStream = Stream;
    type Stream = TlsStream<Stream>;

    fn new(config: &TransportConfig) -> Result<Self> {
        let tcp = TcpTransport::new(config)?;
        let config = config
            .tls
            .as_ref()
            .ok_or_else(|| anyhow!("Missing tls config"))?;

        let connector = load_client_config(config)
            .unwrap()
            .map(|c| Arc::new(c).into());
        let tls_acceptor = load_server_config(config)
            .unwrap()
            .map(|c| Arc::new(c).into());

        Ok(TlsTransport {
            tcp,
            config: config.clone(),
            connector,
            tls_acceptor,
        })
    }

    fn hint(conn: &Self::Stream, opt: SocketOpts) {
        opt.apply(conn.get_ref().0);
    }

    async fn bind(&self, addr: NamedSocketAddr) -> Result<Self::Acceptor> {
        let l = Listener::bind(&addr)
            .await
            .with_context(|| "Failed to create tcp listener")?;
        Ok(l)
    }

    async fn accept(&self, a: &Self::Acceptor) -> Result<(Self::RawStream, SocketAddr)> {
        self.tcp
            .accept(a)
            .await
            .with_context(|| "Failed to accept TCP connection")
    }

    async fn handshake(&self, conn: Self::RawStream) -> Result<Self::Stream> {
        let conn = self
            .tls_acceptor
            .as_ref()
            .context("TLS acceptor is None")?
            .accept(conn)
            .await?;
        Ok(tokio_rustls::TlsStream::Server(conn))
    }

    async fn connect(&self, addr: &AddrMaybeCached) -> Result<Self::Stream> {
        let conn = self.tcp.connect(addr).await?;

        let connector = self.connector.as_ref().context("TLS connector is None")?;

        let host_name = self
            .config
            .hostname
            .as_deref()
            .unwrap_or(host_port_pair(&addr.addr)?.0);

        Ok(tokio_rustls::TlsStream::Client(
            connector
                .connect(ServerName::try_from(host_name)?.to_owned(), conn)
                .await?,
        ))
    }
}

pub(crate) fn get_stream(s: &TlsStream<Stream>) -> &Stream {
    &s.get_ref().0
}