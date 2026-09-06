//! Policy for remote image URLs in rendered documents.
//!
//! - `https:` is always allowed.
//! - `http:` is allowed only for local / private destinations written as IP
//!   literals or `localhost` / `*.local`, on common web ports. Hostnames that
//!   merely *resolve* to private addresses are not allowed (no DNS lookups, so
//!   DNS rebinding cannot turn a public name into an internal probe).
//! - Everything else (`http:` to public hosts, other schemes) is blocked and
//!   rendered as a placeholder that shows the URL.
//!
//! The policy is process-global (set once from config / CLI) so the page
//! renderer and the C FFI share it without threading options everywhere.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::sync::atomic::{AtomicBool, Ordering};

static REMOTE_IMAGES: AtomicBool = AtomicBool::new(true);
static ALLOW_LOCAL_HTTP: AtomicBool = AtomicBool::new(true);

/// Enable/disable loading of remote images altogether (default: on).
pub fn set_remote_images(on: bool) {
    REMOTE_IMAGES.store(on, Ordering::Relaxed);
}
/// Enable/disable plain-http images for local/private destinations (default: on).
pub fn set_allow_local_http(on: bool) {
    ALLOW_LOCAL_HTTP.store(on, Ordering::Relaxed);
}
pub fn remote_images() -> bool {
    REMOTE_IMAGES.load(Ordering::Relaxed)
}
pub fn allow_local_http() -> bool {
    ALLOW_LOCAL_HTTP.load(Ordering::Relaxed)
}

#[derive(Debug, PartialEq, Eq)]
pub enum Verdict {
    Allow,
    /// Human-readable reason shown in the placeholder.
    Block(&'static str),
}

/// Decide whether an `<img src>` URL may be loaded by the webview.
/// Non-URL sources (`data:`, relative paths) are not this function's business
/// and return `Allow`.
pub fn check_image_url(url: &str) -> Verdict {
    let lower = url.trim().to_ascii_lowercase();
    if lower.starts_with("data:") {
        return Verdict::Allow;
    }
    let (scheme, rest) = match lower.split_once("://") {
        Some(x) => x,
        None => return Verdict::Allow, // relative path, handled elsewhere
    };
    if !remote_images() {
        return Verdict::Block("remote images are disabled");
    }
    match scheme {
        "https" => Verdict::Allow,
        "http" => {
            if !allow_local_http() {
                return Verdict::Block("plain http images are disabled");
            }
            let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
            // strip userinfo (never allowed to carry credentials anyway)
            if authority.contains('@') {
                return Verdict::Block("credentials in URL");
            }
            let (host, port) = split_host_port(authority);
            if !is_local_host(host) {
                return Verdict::Block("plain http is only allowed for local / private addresses");
            }
            if !port_allowed(port) {
                return Verdict::Block("port not allowed for plain http");
            }
            Verdict::Allow
        }
        _ => Verdict::Block("unsupported URL scheme"),
    }
}

/// `host[:port]` with IPv6 literal support (`[::1]:8080`).
fn split_host_port(authority: &str) -> (&str, Option<u16>) {
    if let Some(rest) = authority.strip_prefix('[') {
        if let Some(end) = rest.find(']') {
            let host = &rest[..end];
            let port = rest[end + 1..].strip_prefix(':').and_then(|p| p.parse().ok());
            return (host, port);
        }
        return (authority, None);
    }
    match authority.rsplit_once(':') {
        Some((h, p)) if p.chars().all(|c| c.is_ascii_digit()) && !p.is_empty() => (h, p.parse().ok()),
        _ => (authority, None),
    }
}

fn port_allowed(port: Option<u16>) -> bool {
    match port {
        None => true, // 80
        Some(p) => matches!(p, 80 | 8080 | 8443 | 3000..=3999 | 5000..=5999 | 8000..=8999 | 9000..=9999),
    }
}

/// Loopback, RFC 1918, link-local, ULA, `localhost`, `*.local` — by literal only.
pub fn is_local_host(host: &str) -> bool {
    let host = host.trim_end_matches('.');
    if host == "localhost" || host.ends_with(".localhost") || host.ends_with(".local") {
        return true;
    }
    if let Ok(ip) = host.parse::<IpAddr>() {
        return is_local_ip(ip);
    }
    // IPv6 zone id, e.g. fe80::1%en0
    if let Some((addr, _zone)) = host.split_once('%') {
        if let Ok(ip) = addr.parse::<Ipv6Addr>() {
            return is_local_ip(IpAddr::V6(ip));
        }
    }
    false
}

fn is_local_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => is_local_v4(v4),
        IpAddr::V6(v6) => {
            if let Some(v4) = v6.to_ipv4_mapped() {
                return is_local_v4(v4);
            }
            let seg = v6.segments();
            v6.is_loopback()
                || v6.is_unspecified()
                || (seg[0] & 0xfe00) == 0xfc00 // fc00::/7 unique local
                || (seg[0] & 0xffc0) == 0xfe80 // fe80::/10 link local
        }
    }
}

fn is_local_v4(v4: Ipv4Addr) -> bool {
    v4.is_loopback() || v4.is_private() || v4.is_link_local() || v4.is_unspecified()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn allowed(u: &str) -> bool {
        check_image_url(u) == Verdict::Allow
    }

    #[test]
    fn https_always_allowed() {
        assert!(allowed("https://example.com/a.png"));
        assert!(allowed("HTTPS://EXAMPLE.COM/a.png"));
    }

    #[test]
    fn http_local_literals_allowed() {
        for u in [
            "http://localhost/a.png",
            "http://localhost:8080/a.png",
            "http://127.0.0.1/a.png",
            "http://127.0.0.1:3000/a.png",
            "http://[::1]:8000/a.png",
            "http://10.0.0.5/a.png",
            "http://172.16.4.4:8888/a.png",
            "http://192.168.1.10/a.png",
            "http://169.254.1.1/a.png",
            "http://[fd12:3456::1]/a.png",
            "http://[fe80::1%25en0]/a.png",
            "http://nas.local/a.png",
            "http://[::ffff:192.168.0.1]/a.png",
        ] {
            assert!(allowed(u), "{u}");
        }
    }

    #[test]
    fn http_public_blocked() {
        for u in [
            "http://example.com/a.png",
            "http://8.8.8.8/a.png",
            "http://172.32.0.1/a.png", // just outside 172.16/12
            "http://192.169.0.1/a.png",
            "http://internal.corp.example/a.png", // name that might resolve privately: still blocked
        ] {
            assert!(!allowed(u), "{u}");
        }
    }

    #[test]
    fn odd_ports_and_credentials_blocked() {
        assert!(!allowed("http://127.0.0.1:22/a.png"));
        assert!(!allowed("http://192.168.1.1:631/a.png"));
        assert!(!allowed("http://user:pw@127.0.0.1/a.png"));
    }

    #[test]
    fn other_schemes_blocked_and_local_sources_ignored() {
        assert!(!allowed("ftp://127.0.0.1/a.png"));
        assert!(allowed("data:image/png;base64,AAAA"));
        assert!(allowed("images/a.png"));
    }

    #[test]
    fn switches() {
        set_allow_local_http(false);
        assert!(!allowed("http://127.0.0.1/a.png"));
        set_allow_local_http(true);
        set_remote_images(false);
        assert!(!allowed("https://example.com/a.png"));
        set_remote_images(true);
        assert!(allowed("https://example.com/a.png"));
    }
}
