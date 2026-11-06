use crate::{normalize_server, ClientError};
use std::collections::HashMap;
use url::Url;

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct SharedTrackLink {
    pub web_origin: String,
    pub vehicle: String,
    pub identity: String,
    pub history_hours: i32,
}

fn invalid_link() -> ClientError {
    ClientError::InvalidServer {
        reason: "This is not a valid Hrafnsyn track link.".into(),
    }
}

pub(crate) fn valid_identity(identity: &str) -> bool {
    !identity.trim().is_empty() && identity.len() <= 256 && !identity.chars().any(char::is_control)
}

pub(crate) fn valid_history(hours: i32) -> bool {
    matches!(hours, 1 | 6 | 24 | 72)
}

fn parse_url(value: &str) -> Result<Url, ClientError> {
    if value.is_empty()
        || value.len() > 4096
        || value.contains('\\')
        || value.chars().any(|c| c.is_control() || c.is_whitespace())
        || value.as_bytes().iter().enumerate().any(|(index, byte)| {
            *byte == b'%'
                && !value
                    .as_bytes()
                    .get(index + 1..index + 3)
                    .is_some_and(|bytes| bytes.iter().all(u8::is_ascii_hexdigit))
        })
    {
        return Err(invalid_link());
    }
    let mut decoded = Vec::with_capacity(value.len());
    let mut bytes = value.bytes();
    while let Some(byte) = bytes.next() {
        if byte == b'%' {
            let high = (bytes.next().ok_or_else(invalid_link)? as char)
                .to_digit(16)
                .ok_or_else(invalid_link)?;
            let low = (bytes.next().ok_or_else(invalid_link)? as char)
                .to_digit(16)
                .ok_or_else(invalid_link)?;
            decoded.push((high * 16 + low) as u8);
        } else {
            decoded.push(byte);
        }
    }
    if std::str::from_utf8(&decoded)
        .map_err(|_| invalid_link())?
        .chars()
        .any(char::is_control)
    {
        return Err(invalid_link());
    }
    let url = Url::parse(value).map_err(|_| invalid_link())?;
    if !url.username().is_empty() || url.password().is_some() || url.fragment().is_some() {
        return Err(invalid_link());
    }
    Ok(url)
}

fn query(url: &Url) -> Result<HashMap<String, String>, ClientError> {
    let mut fields = HashMap::new();
    for (key, value) in url.query_pairs() {
        if fields
            .insert(key.into_owned(), value.into_owned())
            .is_some()
        {
            return Err(invalid_link());
        }
    }
    Ok(fields)
}

/// Parses web shares and the explicit app handoff without carrying credentials.
#[uniffi::export]
pub fn parse_shared_track_link(url: String) -> Result<SharedTrackLink, ClientError> {
    let mut url = parse_url(&url)?;
    if url.scheme() == "hrafnsyn" {
        if url.host_str() != Some("open") || url.port().is_some() || !matches!(url.path(), "" | "/")
        {
            return Err(invalid_link());
        }
        let fields = query(&url)?;
        if fields.len() != 1 {
            return Err(invalid_link());
        }
        url = parse_url(fields.get("url").ok_or_else(invalid_link)?)?;
    }
    if url.path() != "/" || !matches!(url.scheme(), "https" | "http") {
        return Err(invalid_link());
    }
    let web_origin = normalize_server(url.origin().ascii_serialization())?;
    let fields = query(&url)?;
    if fields.keys().any(|key| {
        !matches!(
            key.as_str(),
            "vehicle" | "identity" | "range" | "lat" | "lon" | "zoom" | "bearing" | "pitch"
        )
    }) {
        return Err(invalid_link());
    }
    let vehicle = fields.get("vehicle").ok_or_else(invalid_link)?.clone();
    let identity = fields.get("identity").ok_or_else(invalid_link)?.clone();
    let history_hours = fields
        .get("range")
        .map(|hours| hours.parse::<i32>().map_err(|_| invalid_link()))
        .transpose()?
        .unwrap_or(6);
    if !matches!(vehicle.as_str(), "plane" | "vessel")
        || !valid_identity(&identity)
        || !valid_history(history_hours)
    {
        return Err(invalid_link());
    }
    for (key, minimum, maximum) in [
        ("lat", -90.0, 90.0),
        ("lon", -180.0, 180.0),
        ("zoom", 0.0, 24.0),
        ("bearing", -360.0, 360.0),
        ("pitch", 0.0, 85.0),
    ] {
        if let Some(value) = fields.get(key) {
            let value = value.parse::<f64>().map_err(|_| invalid_link())?;
            if !value.is_finite() || !(minimum..=maximum).contains(&value) {
                return Err(invalid_link());
            }
        }
    }
    Ok(SharedTrackLink {
        web_origin,
        vehicle,
        identity,
        history_hours,
    })
}

#[uniffi::export]
pub fn make_track_share_url(
    web_origin: String,
    vehicle: String,
    identity: String,
    history_hours: i32,
) -> Result<String, ClientError> {
    if !matches!(vehicle.as_str(), "plane" | "vessel")
        || !valid_identity(&identity)
        || !valid_history(history_hours)
    {
        return Err(invalid_link());
    }
    let origin = normalize_server(web_origin)?;
    let mut url = Url::parse(&origin).map_err(|_| invalid_link())?;
    url.query_pairs_mut()
        .append_pair("vehicle", &vehicle)
        .append_pair("identity", &identity)
        .append_pair("range", &history_hours.to_string());
    Ok(url.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shares_identity_and_history_on_a_canonical_origin() {
        let link = make_track_share_url(
            "https://TRACKING.example:443".into(),
            "vessel".into(),
            "A & B/#?船".into(),
            24,
        )
        .unwrap();
        assert!(link.starts_with("https://tracking.example/?vehicle=vessel&identity="));
        let parsed = parse_shared_track_link(link.clone()).unwrap();
        assert_eq!(parsed.web_origin, "https://tracking.example");
        assert_eq!(parsed.identity, "A & B/#?船");
        assert_eq!(parsed.history_hours, 24);
        let mut wrapped = Url::parse("hrafnsyn://open").unwrap();
        wrapped.query_pairs_mut().append_pair("url", &link);
        assert_eq!(
            parse_shared_track_link(wrapped.to_string()).unwrap(),
            parsed
        );
    }

    #[test]
    fn accepts_existing_web_shares_and_loopback_development() {
        let parsed = parse_shared_track_link("https://example.test/?vehicle=plane&identity=4869BD&lat=36.4&lon=-5.1&zoom=18&bearing=0&pitch=0".into()).unwrap();
        assert_eq!(parsed.history_hours, 6);
        assert_eq!(parsed.vehicle, "plane");
        assert!(parse_shared_track_link(
            "http://127.0.0.1:4088/?vehicle=vessel&identity=123&range=72".into()
        )
        .is_ok());
    }

    #[test]
    fn rejects_ambiguous_or_credential_bearing_links() {
        for link in [
            "https://user:pass@example.test/?vehicle=plane&identity=1",
            "https://example.test/path?vehicle=plane&identity=1",
            "https://example.test/?vehicle=plane&identity=1&identity=2",
            "https://example.test/?vehicle=plane&identity=1&access_token=secret",
            "https://example.test/?vehicle=plane&identity=1#secret",
            "https://example.test/?vehicle=other&identity=1",
            "https://example.test/?vehicle=plane&identity=",
            "https://example.test/?vehicle=plane&identity=%00",
            "https://example.test/?vehicle=plane&identity=%zz",
            "https://example.test/?vehicle=plane&identity=%FF",
            "https://example.test/?vehicle=plane&identity=1&range=999999",
            "https://example.test/?vehicle=plane&identity=1&lat=NaN",
            "http://example.test/?vehicle=plane&identity=1",
            "hrafnsyn://other?url=https%3A%2F%2Fexample.test%2F",
            "hrafnsyn://open/path?url=https%3A%2F%2Fexample.test%2F",
            "hrafnsyn://open?url=https%3A%2F%2Fexample.test%2F&token=secret",
            "https://example.test\\@evil.test/?vehicle=plane&identity=1",
        ] {
            assert!(parse_shared_track_link(link.into()).is_err(), "{link}");
        }
        let long = format!(
            "https://example.test/?vehicle=plane&identity={}",
            "x".repeat(257)
        );
        assert!(parse_shared_track_link(long).is_err());
    }
}
