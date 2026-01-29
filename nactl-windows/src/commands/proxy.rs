//! Proxy configuration command implementations

use crate::errors::{ExitCodes, NactlError};
use crate::utils::admin;
use crate::utils::output::{print_output, OutputFormat};
use crate::utils::registry;
use serde::Serialize;

#[derive(Debug, Serialize)]
struct ProxyEndpoint {
    enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    server: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    port: Option<u16>,
}

#[derive(Debug, Serialize)]
struct ProxyConfig {
    http_proxy: ProxyEndpoint,
    https_proxy: ProxyEndpoint,
    socks_proxy: ProxyEndpoint,
    #[serde(skip_serializing_if = "Option::is_none")]
    auto_config_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    bypass_list: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
struct GetProxyResponse {
    success: bool,
    data: ProxyConfig,
}

#[derive(Debug, Serialize)]
struct ClearProxyResponse {
    success: bool,
    message: String,
}

/// Get current proxy configuration
pub fn get(format: OutputFormat) -> Result<u8, NactlError> {
    let config = read_proxy_config()?;

    let response = GetProxyResponse {
        success: true,
        data: config,
    };

    print_output(&response, format)?;
    Ok(ExitCodes::Success as u8)
}

/// Clear all proxy settings
pub fn clear(format: OutputFormat) -> Result<u8, NactlError> {
    // Check for admin privileges (recommended but not strictly required for HKCU)
    // The registry key is in HKCU so regular users can modify it
    // But we'll check anyway for consistency

    // Disable proxy
    registry::set_proxy_enabled(false)?;

    // Clear proxy server
    registry::clear_proxy_server()?;

    // Clear auto-config URL
    registry::clear_auto_config_url()?;

    // Also reset WinHTTP proxy
    // This requires admin, so we try but don't fail if it doesn't work
    if admin::is_elevated() {
        let _ = std::process::Command::new("netsh")
            .args(["winhttp", "reset", "proxy"])
            .output();
    }

    let response = ClearProxyResponse {
        success: true,
        message: "Proxy settings cleared".to_string(),
    };

    print_output(&response, format)?;
    Ok(ExitCodes::Success as u8)
}

fn read_proxy_config() -> Result<ProxyConfig, NactlError> {
    // Read from Windows Registry:
    // HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    // - ProxyEnable (DWORD): 0 or 1
    // - ProxyServer (string): "server:port" or "http=server:port;https=server:port;..."
    // - ProxyOverride (string): bypass list separated by semicolons
    // - AutoConfigURL (string): PAC file URL

    let proxy_enabled = registry::get_proxy_enabled()?;
    let proxy_server = registry::get_proxy_server()?;
    let proxy_override = registry::get_proxy_override()?;
    let auto_config_url = registry::get_auto_config_url()?;

    // Parse proxy server string
    let (http_proxy, https_proxy, socks_proxy) = parse_proxy_server(&proxy_server, proxy_enabled);

    // Parse bypass list
    let bypass_list = if let Some(override_str) = proxy_override {
        Some(
            override_str
                .split(';')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect(),
        )
    } else {
        None
    };

    Ok(ProxyConfig {
        http_proxy,
        https_proxy,
        socks_proxy,
        auto_config_url,
        bypass_list,
    })
}

fn parse_proxy_server(
    proxy_server: &Option<String>,
    enabled: bool,
) -> (ProxyEndpoint, ProxyEndpoint, ProxyEndpoint) {
    let mut http = ProxyEndpoint {
        enabled: false,
        server: None,
        port: None,
    };
    let mut https = ProxyEndpoint {
        enabled: false,
        server: None,
        port: None,
    };
    let mut socks = ProxyEndpoint {
        enabled: false,
        server: None,
        port: None,
    };

    if let Some(server_str) = proxy_server {
        if server_str.is_empty() {
            return (http, https, socks);
        }

        // Check if it's a simple "server:port" or a complex "protocol=server:port;..." format
        if server_str.contains('=') {
            // Complex format: "http=proxy:8080;https=proxy:8080;socks=proxy:1080"
            for part in server_str.split(';') {
                let part = part.trim();
                if let Some((protocol, addr)) = part.split_once('=') {
                    let (server, port) = parse_server_port(addr);
                    match protocol.to_lowercase().as_str() {
                        "http" => {
                            http.enabled = enabled;
                            http.server = server;
                            http.port = port;
                        }
                        "https" => {
                            https.enabled = enabled;
                            https.server = server;
                            https.port = port;
                        }
                        "socks" | "socks5" | "socks4" => {
                            socks.enabled = enabled;
                            socks.server = server;
                            socks.port = port;
                        }
                        _ => {}
                    }
                }
            }
        } else {
            // Simple format: "proxy:8080" applies to both HTTP and HTTPS
            let (server, port) = parse_server_port(server_str);
            http.enabled = enabled;
            http.server = server.clone();
            http.port = port;
            https.enabled = enabled;
            https.server = server;
            https.port = port;
        }
    }

    (http, https, socks)
}

fn parse_server_port(addr: &str) -> (Option<String>, Option<u16>) {
    let addr = addr.trim();
    if addr.is_empty() {
        return (None, None);
    }

    if let Some((server, port_str)) = addr.rsplit_once(':') {
        let port = port_str.parse::<u16>().ok();
        (Some(server.to_string()), port)
    } else {
        (Some(addr.to_string()), None)
    }
}
