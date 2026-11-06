use std::{
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::sync::Mutex;
use tonic::{
    transport::{Channel, ClientTlsConfig, Endpoint},
    Code, Request, Status,
};
use url::Url;

mod sharing;
pub use sharing::{make_track_share_url, parse_shared_track_link, SharedTrackLink};

mod proto {
    tonic::include_proto!("hrafnsyn.v1");
}
uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ClientError {
    #[error("{reason}")]
    InvalidServer { reason: String },
    #[error("Sign in to this server to continue.")]
    SignInRequired,
    #[error("The username or password is incorrect.")]
    InvalidCredentials,
    #[error("{reason}")]
    Connection { reason: String },
    #[error("{reason}")]
    Server { reason: String },
}
impl From<Status> for ClientError {
    fn from(value: Status) -> Self {
        if value.code() == Code::Unauthenticated {
            Self::SignInRequired
        } else {
            Self::Server {
                reason: value.message().to_owned(),
            }
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct SavedSession {
    pub access_token: String,
    pub refresh_token: String,
    pub access_expires_at: i64,
    pub refresh_expires_at: i64,
    pub session_id: String,
    pub username: String,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct ConnectionStatus {
    pub auth_required: bool,
    pub authenticated: bool,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct Track {
    pub id: String,
    pub name: String,
    pub identity: String,
    pub callsign: String,
    pub registration: String,
    pub country: String,
    pub destination: String,
    pub source_name: String,
    pub is_aircraft: bool,
    pub latitude: f64,
    pub longitude: f64,
    pub speed_knots: f64,
    pub heading_degrees: f64,
    pub altitude_feet: i32,
    pub observed_at: i64,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct RoutePoint {
    pub latitude: f64,
    pub longitude: f64,
    pub observed_at: i64,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct TrackDetails {
    pub track: Option<Track>,
    pub route: Vec<RoutePoint>,
    pub distance_meters: f64,
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
fn session_from(p: proto::TokenPair) -> SavedSession {
    SavedSession {
        access_token: p.access_token,
        refresh_token: p.refresh_token,
        access_expires_at: p.access_token_expires_at.map_or(0, |t| t.seconds),
        refresh_expires_at: p.refresh_token_expires_at.map_or(0, |t| t.seconds),
        session_id: p.session.map_or_else(String::new, |s| s.id),
        username: p.user.map_or_else(String::new, |u| u.username),
    }
}
impl From<proto::TrackSummary> for Track {
    fn from(t: proto::TrackSummary) -> Self {
        let name = [&t.display_name, &t.callsign, &t.registration, &t.identity]
            .into_iter()
            .find(|s| !s.is_empty())
            .cloned()
            .unwrap_or_default();
        Self {
            id: t.id,
            name,
            identity: t.identity,
            callsign: t.callsign,
            registration: t.registration,
            country: t.country,
            destination: t.destination,
            source_name: t.latest_source_name,
            is_aircraft: t.vehicle_type == 1,
            latitude: t.latitude,
            longitude: t.longitude,
            speed_knots: t.speed_knots,
            heading_degrees: t.heading_degrees,
            altitude_feet: t.altitude_feet,
            observed_at: t.observed_at.map_or(0, |t| t.seconds),
        }
    }
}

/// Canonical server keys also partition Keychain/Keystore credentials.
#[uniffi::export]
pub fn normalize_server(server: String) -> Result<String, ClientError> {
    let input = server.trim();
    let input = if input.contains("://") {
        input.to_owned()
    } else {
        format!("https://{input}")
    };
    let url = Url::parse(&input).map_err(|_| ClientError::InvalidServer {
        reason: "Enter a server hostname and optional port.".into(),
    })?;
    let host = url.host_str().ok_or_else(|| ClientError::InvalidServer {
        reason: "Enter a server hostname.".into(),
    })?;
    let local = host == "localhost" || host == "127.0.0.1" || host == "[::1]";
    if url.scheme() != "https" && !(url.scheme() == "http" && local) {
        return Err(ClientError::InvalidServer { reason: "Use HTTPS. Unencrypted connections are allowed only on this device's loopback address.".into() });
    }
    if !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || url.path() != "/"
    {
        return Err(ClientError::InvalidServer {
            reason: "Use only the server hostname and gRPC port, without credentials or a path."
                .into(),
        });
    }
    Ok(url.as_str().trim_end_matches('/').to_owned())
}

#[derive(uniffi::Object)]
pub struct TrackingClient {
    server: String,
    channel: Mutex<Option<Channel>>,
    session: Mutex<Option<SavedSession>>,
    // Serialize refresh rotation, including concurrent map and detail requests.
    refresh_lock: Mutex<()>,
}
#[uniffi::export(async_runtime = "tokio")]
impl TrackingClient {
    #[uniffi::constructor]
    pub fn new(server: String, session: Option<SavedSession>) -> Result<Arc<Self>, ClientError> {
        Ok(Arc::new(Self {
            server: normalize_server(server)?,
            channel: Mutex::new(None),
            session: Mutex::new(session),
            refresh_lock: Mutex::new(()),
        }))
    }
    pub fn server(&self) -> String {
        self.server.clone()
    }
    pub async fn saved_session(&self) -> Option<SavedSession> {
        self.session.lock().await.clone()
    }
    pub async fn connect(&self) -> Result<ConnectionStatus, ClientError> {
        // Refresh an expired saved access token before auth discovery.
        if self.session.lock().await.is_some() {
            match self.refresh_if_needed(false).await {
                Ok(()) | Err(ClientError::SignInRequired) => (),
                Err(error) => return Err(error),
            }
        }
        let mut client = proto::auth_service_client::AuthServiceClient::new(self.channel().await?);
        let response = client
            .get_auth_status(self.request((), false).await?)
            .await?
            .into_inner();
        if response.auth_required && !response.authenticated {
            // Access credentials might have been invalidated earlier than their expiry.
            if self.session.lock().await.is_some() {
                self.refresh_if_needed(true).await?;
                let response = client
                    .get_auth_status(self.request((), false).await?)
                    .await?
                    .into_inner();
                return Ok(ConnectionStatus {
                    auth_required: response.auth_required,
                    authenticated: response.authenticated,
                });
            }
        }
        Ok(ConnectionStatus {
            auth_required: response.auth_required,
            authenticated: response.authenticated,
        })
    }
    pub async fn login(
        &self,
        username: String,
        password: String,
    ) -> Result<SavedSession, ClientError> {
        let _guard = self.refresh_lock.lock().await;
        let mut client = proto::auth_service_client::AuthServiceClient::new(self.channel().await?);
        let pair = client
            .login(proto::LoginRequest {
                username: username.trim().into(),
                password,
            })
            .await
            .map_err(|status| {
                if status.code() == Code::Unauthenticated {
                    ClientError::InvalidCredentials
                } else {
                    ClientError::from(status)
                }
            })?
            .into_inner();
        let session = session_from(pair);
        *self.session.lock().await = Some(session.clone());
        Ok(session)
    }
    pub async fn active_tracks(&self) -> Result<Vec<Track>, ClientError> {
        let mut client =
            proto::tracking_service_client::TrackingServiceClient::new(self.channel().await?);
        let message = proto::ListActiveTracksRequest {
            limit: 500,
            active_window_minutes: 30,
        };
        let response = client
            .list_active_tracks(self.request(message.clone(), true).await?)
            .await;
        let response = match response {
            Err(status) if status.code() == Code::Unauthenticated => {
                self.refresh_if_needed(true).await?;
                client
                    .list_active_tracks(self.request(message, false).await?)
                    .await?
            }
            other => other?,
        };
        Ok(response
            .into_inner()
            .tracks
            .into_iter()
            .map(Track::from)
            .collect())
    }
    pub async fn track_details(&self, id: String) -> Result<TrackDetails, ClientError> {
        self.fetch_track_details(proto::GetTrackRequest {
            track_id: id,
            history_hours: 6,
            log_limit: 100,
            ..Default::default()
        })
        .await
    }
    pub async fn get_track_by_identity(
        &self,
        vehicle: String,
        identity: String,
        history_hours: i32,
    ) -> Result<TrackDetails, ClientError> {
        let vehicle_type = match vehicle.as_str() {
            "plane" => 1,
            "vessel" => 2,
            _ => {
                return Err(ClientError::Server {
                    reason: "Unknown vehicle type.".into(),
                })
            }
        };
        if !sharing::valid_identity(&identity) || !sharing::valid_history(history_hours) {
            return Err(ClientError::Server {
                reason: "Invalid shared track selection.".into(),
            });
        }
        self.fetch_track_details(proto::GetTrackRequest {
            vehicle_type,
            identity,
            history_hours,
            log_limit: 100,
            ..Default::default()
        })
        .await
    }
    pub async fn server_web_url(&self) -> Result<String, ClientError> {
        let mut client =
            proto::tracking_service_client::TrackingServiceClient::new(self.channel().await?);
        let response = client.get_system_info(self.request((), true).await?).await;
        let response = match response {
            Err(status) if status.code() == Code::Unauthenticated => {
                self.refresh_if_needed(true).await?;
                client
                    .get_system_info(self.request((), false).await?)
                    .await?
            }
            other => other?,
        }
        .into_inner();
        // Older servers omit this optional field; keep their read API usable.
        if response.web_url.is_empty() {
            Ok(String::new())
        } else {
            normalize_server(response.web_url)
        }
    }
    pub async fn sign_out(&self) -> Result<(), ClientError> {
        let _guard = self.refresh_lock.lock().await;
        // Remove local credentials before network work, even when offline.
        let session = self.session.lock().await.take();
        if let Some(session) = session {
            let mut client =
                proto::auth_service_client::AuthServiceClient::new(self.channel().await?);
            let mut request = Request::new(proto::RevokeSessionRequest {
                session_id: session.session_id,
            });
            request.set_timeout(Duration::from_secs(20));
            request.metadata_mut().insert(
                "authorization",
                format!("Bearer {}", session.access_token)
                    .parse()
                    .map_err(|_| ClientError::SignInRequired)?,
            );
            client
                .revoke_session(request)
                .await
                .map(|_| ())
                .map_err(ClientError::from)
        } else {
            Ok(())
        }
    }
}
impl TrackingClient {
    async fn fetch_track_details(
        &self,
        message: proto::GetTrackRequest,
    ) -> Result<TrackDetails, ClientError> {
        let mut client =
            proto::tracking_service_client::TrackingServiceClient::new(self.channel().await?);
        let response = client
            .get_track(self.request(message.clone(), true).await?)
            .await;
        let response = match response {
            Err(status) if status.code() == Code::Unauthenticated => {
                self.refresh_if_needed(true).await?;
                client
                    .get_track(self.request(message, false).await?)
                    .await?
            }
            other => other?,
        }
        .into_inner();
        Ok(TrackDetails {
            track: response.track.map(Track::from),
            route: response
                .route_points
                .into_iter()
                .map(|p| RoutePoint {
                    latitude: p.latitude,
                    longitude: p.longitude,
                    observed_at: p.observed_at.map_or(0, |t| t.seconds),
                })
                .collect(),
            distance_meters: response.route_stats.map_or(0.0, |s| s.distance_meters),
        })
    }
    async fn channel(&self) -> Result<Channel, ClientError> {
        let mut channel = self.channel.lock().await;
        if let Some(channel) = channel.as_ref() {
            return Ok(channel.clone());
        }
        let mut endpoint = Endpoint::from_shared(self.server.clone())
            .map_err(|e| ClientError::Connection {
                reason: e.to_string(),
            })?
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(20));
        if self.server.starts_with("https://") {
            endpoint = endpoint
                .tls_config(ClientTlsConfig::new().with_webpki_roots())
                .map_err(|e| ClientError::Connection {
                    reason: e.to_string(),
                })?;
        }
        let connected = endpoint.connect().await.map_err(|_| ClientError::Connection { reason: "Could not reach the gRPC server. Check the address, port, TLS certificate and network connection.".into() })?;
        *channel = Some(connected.clone());
        Ok(connected)
    }
    async fn request<T>(&self, value: T, refresh: bool) -> Result<Request<T>, ClientError> {
        if refresh {
            self.refresh_if_needed(false).await?;
        }
        let mut request = Request::new(value);
        request.set_timeout(Duration::from_secs(20));
        if let Some(session) = self.session.lock().await.as_ref() {
            let value = format!("Bearer {}", session.access_token)
                .parse()
                .map_err(|_| ClientError::SignInRequired)?;
            request.metadata_mut().insert("authorization", value);
        }
        Ok(request)
    }
    async fn refresh_if_needed(&self, force: bool) -> Result<(), ClientError> {
        let _guard = self.refresh_lock.lock().await;
        let Some(session) = self.session.lock().await.clone() else {
            return if force {
                Err(ClientError::SignInRequired)
            } else {
                Ok(())
            };
        };
        if !force && session.access_expires_at > now() + 60 {
            return Ok(());
        }
        if session.refresh_expires_at <= now() {
            *self.session.lock().await = None;
            return Err(ClientError::SignInRequired);
        }
        let mut client = proto::auth_service_client::AuthServiceClient::new(self.channel().await?);
        match client
            .refresh(proto::RefreshRequest {
                refresh_token: session.refresh_token,
            })
            .await
        {
            Ok(response) => {
                *self.session.lock().await = Some(session_from(response.into_inner()));
                Ok(())
            }
            Err(status) if status.code() == Code::Unauthenticated => {
                *self.session.lock().await = None;
                Err(ClientError::SignInRequired)
            }
            Err(status) => Err(status.into()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonicalizes_server_and_default_tls_port() {
        assert_eq!(
            normalize_server("  EXAMPLE.com:443  ".into()).unwrap(),
            "https://example.com"
        );
        assert_eq!(
            normalize_server("https://example.com:50051/".into()).unwrap(),
            "https://example.com:50051"
        );
    }
    #[test]
    fn refuses_credentials_paths_and_insecure_remote_servers() {
        for input in [
            "http://example.com",
            "https://user:pass@example.com",
            "https://example.com/path",
            "https://example.com?token=secret",
            "ftp://example.com",
        ] {
            assert!(normalize_server(input.into()).is_err(), "{input}");
        }
        assert!(normalize_server("http://localhost:50051".into()).is_ok());
        assert!(normalize_server("http://127.0.0.1:50051".into()).is_ok());
    }
    #[tokio::test]
    async fn expired_refresh_token_requires_login_without_network() {
        let client = TrackingClient::new(
            "https://example.com".into(),
            Some(SavedSession {
                access_token: "old".into(),
                refresh_token: "old".into(),
                access_expires_at: 0,
                refresh_expires_at: 0,
                session_id: "session".into(),
                username: "user".into(),
            }),
        )
        .unwrap();
        assert!(matches!(
            client.refresh_if_needed(false).await,
            Err(ClientError::SignInRequired)
        ));
        assert!(client.saved_session().await.is_none());
    }
}

#[cfg(test)]
mod session_tests {
    use super::*;
    #[tokio::test]
    async fn signout_removes_credentials_even_if_the_server_is_offline() {
        // Port zero cannot accept the request; no DNS/external network dependency.
        let client = TrackingClient::new(
            "http://127.0.0.1:0".into(),
            Some(SavedSession {
                access_token: "old".into(),
                refresh_token: "old".into(),
                access_expires_at: now() + 300,
                refresh_expires_at: now() + 600,
                session_id: "session".into(),
                username: "user".into(),
            }),
        )
        .unwrap();
        assert!(client.sign_out().await.is_err());
        assert!(client.saved_session().await.is_none());
    }
}

#[cfg(test)]
mod auth_tests;
