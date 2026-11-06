use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio_stream::wrappers::TcpListenerStream;
use tonic::{transport::Server, Response};

struct AuthFixture {
    required: bool,
    refreshes: Arc<AtomicUsize>,
}

struct TrackingFixture;

fn require_rotated_token<T>(request: &Request<T>) -> Result<(), Status> {
    if request
        .metadata()
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        != Some("Bearer rotated-access")
    {
        return Err(Status::unauthenticated("Rotate the access token"));
    }
    Ok(())
}

#[tonic::async_trait]
impl proto::tracking_service_server::TrackingService for TrackingFixture {
    async fn get_system_info(
        &self,
        request: Request<()>,
    ) -> Result<Response<proto::SystemInfo>, Status> {
        require_rotated_token(&request)?;
        Ok(Response::new(proto::SystemInfo {
            web_url: "https://SHARE.example:443/".into(),
            ..Default::default()
        }))
    }
    async fn list_active_tracks(
        &self,
        _: Request<proto::ListActiveTracksRequest>,
    ) -> Result<Response<proto::ListActiveTracksResponse>, Status> {
        Err(Status::unimplemented("test"))
    }
    async fn search_tracks(
        &self,
        _: Request<proto::SearchTracksRequest>,
    ) -> Result<Response<proto::SearchTracksResponse>, Status> {
        Err(Status::unimplemented("test"))
    }
    async fn get_track(
        &self,
        request: Request<proto::GetTrackRequest>,
    ) -> Result<Response<proto::GetTrackResponse>, Status> {
        require_rotated_token(&request)?;
        let request = request.into_inner();
        if request.identity == "missing" {
            return Err(Status::not_found("Track was not found"));
        }
        if !request.track_id.is_empty()
            || request.vehicle_type != 2
            || request.identity != "378113455"
            || request.history_hours != 24
        {
            return Err(Status::invalid_argument("Wrong shared selector"));
        }
        Ok(Response::new(proto::GetTrackResponse {
            track: Some(proto::TrackSummary {
                id: "resolved-id".into(),
                identity: request.identity,
                vehicle_type: 2,
                ..Default::default()
            }),
            ..Default::default()
        }))
    }
    type StreamTrackUpdatesStream = tokio_stream::Empty<Result<proto::TrackUpdate, Status>>;
    async fn stream_track_updates(
        &self,
        _: Request<proto::StreamTrackUpdatesRequest>,
    ) -> Result<Response<Self::StreamTrackUpdatesStream>, Status> {
        Err(Status::unimplemented("test"))
    }
}
fn pair(access: &str, refresh: &str) -> proto::TokenPair {
    proto::TokenPair {
        access_token: access.into(),
        refresh_token: refresh.into(),
        access_token_expires_at: Some(prost_types::Timestamp {
            seconds: now() + 900,
            nanos: 0,
        }),
        refresh_token_expires_at: Some(prost_types::Timestamp {
            seconds: now() + 3600,
            nanos: 0,
        }),
        session: Some(proto::SessionInfo {
            id: "session".into(),
            ..Default::default()
        }),
        user: Some(proto::UserProfile {
            username: "test-user".into(),
            ..Default::default()
        }),
    }
}
#[tonic::async_trait]
impl proto::auth_service_server::AuthService for AuthFixture {
    async fn get_auth_status(
        &self,
        request: Request<()>,
    ) -> Result<Response<proto::AuthStatus>, Status> {
        let authenticated = request.metadata().get("authorization").is_some();
        Ok(Response::new(proto::AuthStatus {
            auth_required: self.required,
            authenticated,
            ..Default::default()
        }))
    }
    async fn login(
        &self,
        request: Request<proto::LoginRequest>,
    ) -> Result<Response<proto::TokenPair>, Status> {
        let login = request.into_inner();
        if login.username != "test-user" || login.password != "test-password" {
            return Err(Status::unauthenticated("Invalid credentials"));
        }
        Ok(Response::new(pair("access", "refresh")))
    }
    async fn refresh(
        &self,
        request: Request<proto::RefreshRequest>,
    ) -> Result<Response<proto::TokenPair>, Status> {
        if request.into_inner().refresh_token != "refresh" {
            return Err(Status::unauthenticated("Revoked"));
        }
        self.refreshes.fetch_add(1, Ordering::SeqCst);
        Ok(Response::new(pair("rotated-access", "rotated-refresh")))
    }
    async fn list_sessions(
        &self,
        _: Request<()>,
    ) -> Result<Response<proto::ListSessionsResponse>, Status> {
        Err(Status::unimplemented("test"))
    }
    async fn revoke_session(
        &self,
        _: Request<proto::RevokeSessionRequest>,
    ) -> Result<Response<proto::RevocationResponse>, Status> {
        Ok(Response::new(proto::RevocationResponse::default()))
    }
    async fn revoke_all_sessions(
        &self,
        _: Request<()>,
    ) -> Result<Response<proto::RevocationResponse>, Status> {
        Err(Status::unimplemented("test"))
    }
}
async fn fixture(required: bool) -> (String, Arc<AtomicUsize>, tokio::task::JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = format!("http://{}", listener.local_addr().unwrap());
    let refreshes = Arc::new(AtomicUsize::new(0));
    let service = AuthFixture {
        required,
        refreshes: refreshes.clone(),
    };
    let task = tokio::spawn(async move {
        Server::builder()
            .add_service(proto::auth_service_server::AuthServiceServer::new(service))
            .add_service(proto::tracking_service_server::TrackingServiceServer::new(
                TrackingFixture,
            ))
            .serve_with_incoming(TcpListenerStream::new(listener))
            .await
            .unwrap();
    });
    (address, refreshes, task)
}
#[tokio::test]
async fn auth_discovery_login_rotation_and_revocation_use_real_grpc() {
    let (address, refreshes, task) = fixture(true).await;
    let client = TrackingClient::new(address.clone(), None).unwrap();
    let status = client.connect().await.unwrap();
    assert!(status.auth_required && !status.authenticated);
    assert!(matches!(
        client.login("test-user".into(), "wrong".into()).await,
        Err(ClientError::InvalidCredentials)
    ));
    let mut session = client
        .login("test-user".into(), "test-password".into())
        .await
        .unwrap();
    session.access_expires_at = 0;
    let client = TrackingClient::new(address, Some(session)).unwrap();
    let (first, second) = tokio::join!(client.connect(), client.connect());
    assert!(first.unwrap().authenticated && second.unwrap().authenticated);
    assert_eq!(refreshes.load(Ordering::SeqCst), 1);
    assert_eq!(
        client.saved_session().await.unwrap().refresh_token,
        "rotated-refresh"
    );
    client.sign_out().await.unwrap();
    assert!(client.saved_session().await.is_none());
    task.abort();
}
#[tokio::test]
async fn public_server_does_not_require_login_for_expired_saved_session() {
    let (address, _, task) = fixture(false).await;
    let mut session = session_from(pair("expired", "expired"));
    session.access_expires_at = 0;
    session.refresh_expires_at = 0;
    let client = TrackingClient::new(address, Some(session)).unwrap();
    let status = client.connect().await.unwrap();
    assert!(!status.auth_required && !status.authenticated);
    assert!(client.saved_session().await.is_none());
    task.abort();
}

#[tokio::test]
async fn shared_selection_and_server_metadata_refresh_credentials_on_the_grpc_origin() {
    let (address, refreshes, task) = fixture(true).await;
    let client = TrackingClient::new(
        address.clone(),
        Some(session_from(pair("stale-access", "refresh"))),
    )
    .unwrap();
    assert_eq!(
        client.server_web_url().await.unwrap(),
        "https://share.example"
    );
    assert_eq!(client.server(), address);
    assert_eq!(refreshes.load(Ordering::SeqCst), 1);
    let details = client
        .get_track_by_identity("vessel".into(), "378113455".into(), 24)
        .await
        .unwrap();
    assert_eq!(details.track.unwrap().id, "resolved-id");
    assert!(
        matches!(client.get_track_by_identity("vessel".into(), "missing".into(), 24).await,
        Err(ClientError::Server { reason }) if reason == "Track was not found")
    );
    assert_eq!(
        client.saved_session().await.unwrap().refresh_token,
        "rotated-refresh"
    );
    task.abort();
}
