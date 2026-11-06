use hrafnsyn_mobile::TrackingClient;
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let server = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "http://localhost:50051".into());
    let client = TrackingClient::new(server, None)?;
    let status = client.connect().await?;
    println!(
        "auth_required={} authenticated={}",
        status.auth_required, status.authenticated
    );
    if status.auth_required {
        let username = std::env::var("HRAFNSYN_TEST_USERNAME")?;
        let password = std::env::var("HRAFNSYN_TEST_PASSWORD")?;
        client.login(username, password).await?;
    }
    let tracks = client.active_tracks().await?;
    println!("{} active tracks", tracks.len());
    if let Some(track) = tracks.first() {
        let details = client.track_details(track.id.clone()).await?;
        println!("{} route points", details.route.len());
    }
    if status.auth_required {
        client.sign_out().await?;
    }
    Ok(())
}
