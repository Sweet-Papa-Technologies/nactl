//! Network status command implementation

use crate::errors::{ExitCodes, NactlError};
use crate::utils::netsh;
use crate::utils::output::{OutputFormat, print_output};
use regex::Regex;
use serde::Serialize;
use std::process::Command;

#[derive(Debug, Serialize)]
pub struct NetworkStatus {
    pub connected: bool,
    #[serde(rename = "type")]
    pub connection_type: Option<String>,
    pub interface: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ssid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bssid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signal_strength: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signal_rssi: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub channel: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frequency: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub link_speed: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ip_address: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subnet_mask: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gateway: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dns_servers: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mac_address: Option<String>,
}

impl Default for NetworkStatus {
    fn default() -> Self {
        Self {
            connected: false,
            connection_type: None,
            interface: None,
            ssid: None,
            bssid: None,
            signal_strength: None,
            signal_rssi: None,
            channel: None,
            frequency: None,
            link_speed: None,
            ip_address: None,
            subnet_mask: None,
            gateway: None,
            dns_servers: None,
            mac_address: None,
        }
    }
}

#[derive(Debug, Serialize)]
struct StatusResponse {
    success: bool,
    data: NetworkStatus,
}

pub fn execute(format: OutputFormat, interface: Option<&str>) -> Result<u8, NactlError> {
    let mut status = NetworkStatus::default();

    // Get Wi-Fi interface info using netsh
    if let Ok(wifi_info) = get_wifi_status(interface) {
        status = wifi_info;
    }

    // Get IP configuration using ipconfig
    if let Ok(ip_info) = get_ip_config(status.interface.as_deref()) {
        // Merge IP info with existing status
        if status.ip_address.is_none() {
            status.ip_address = ip_info.ip_address;
        }
        if status.subnet_mask.is_none() {
            status.subnet_mask = ip_info.subnet_mask;
        }
        if status.gateway.is_none() {
            status.gateway = ip_info.gateway;
        }
        if status.dns_servers.is_none() {
            status.dns_servers = ip_info.dns_servers;
        }
        if status.mac_address.is_none() {
            status.mac_address = ip_info.mac_address;
        }

        // Update connection status based on IP
        if status.ip_address.is_some() {
            status.connected = true;
        }
    }

    let response = StatusResponse {
        success: true,
        data: status,
    };

    print_output(&response, format)?;
    Ok(ExitCodes::Success as u8)
}

fn get_wifi_status(interface: Option<&str>) -> Result<NetworkStatus, NactlError> {
    let output = netsh::run_command(&["wlan", "show", "interfaces"])?;

    let mut status = NetworkStatus::default();
    let mut current_interface = String::new();
    let mut found_interface = false;

    for line in output.lines() {
        let line = line.trim();

        if line.starts_with("Name") {
            if let Some(value) = extract_value(line) {
                current_interface = value.to_string();
                if interface.is_none() || interface == Some(&current_interface) {
                    found_interface = true;
                    status.interface = Some(current_interface.clone());
                    status.connection_type = Some("wifi".to_string());
                }
            }
        }

        if !found_interface {
            continue;
        }

        if let Some(value) = extract_value(line) {
            if line.starts_with("State") {
                status.connected = value.to_lowercase() == "connected";
            } else if line.starts_with("SSID") && !line.starts_with("BSSID") {
                status.ssid = Some(value.to_string());
            } else if line.starts_with("BSSID") {
                status.bssid = Some(value.to_string());
            } else if line.starts_with("Signal") {
                if let Some(percent) = value.strip_suffix('%') {
                    if let Ok(signal) = percent.trim().parse::<i32>() {
                        status.signal_strength = Some(signal);
                        // Approximate RSSI from percentage (rough estimation)
                        // 100% ~ -30 dBm, 0% ~ -100 dBm
                        status.signal_rssi = Some(-100 + (signal * 70 / 100));
                    }
                }
            } else if line.starts_with("Channel") {
                if let Ok(channel) = value.parse::<u32>() {
                    status.channel = Some(channel);
                    // Determine frequency band from channel
                    if channel <= 14 {
                        status.frequency = Some("2.4GHz".to_string());
                    } else {
                        status.frequency = Some("5GHz".to_string());
                    }
                }
            } else if line.starts_with("Receive rate") || line.starts_with("Transmit rate") {
                if status.link_speed.is_none() {
                    status.link_speed = Some(value.to_string());
                }
            }
        }

        // If we hit another interface section, stop
        if line.starts_with("Name") && status.interface.is_some() && !current_interface.is_empty() {
            if let Some(ref iface) = status.interface {
                if &current_interface != iface {
                    break;
                }
            }
        }
    }

    Ok(status)
}

fn get_ip_config(interface: Option<&str>) -> Result<NetworkStatus, NactlError> {
    let output = Command::new("ipconfig")
        .arg("/all")
        .output()
        .map_err(|e| NactlError::command_failed(format!("Failed to run ipconfig: {}", e)))?;

    let output_str = String::from_utf8_lossy(&output.stdout);

    let mut status = NetworkStatus::default();
    let mut in_target_adapter = false;
    let mut dns_servers: Vec<String> = Vec::new();
    let mut collecting_dns = false;

    // Patterns for matching
    let adapter_pattern = Regex::new(r"(?i)(Wireless|Wi-Fi|Ethernet).*adapter.*:").unwrap();
    let ipv4_pattern = Regex::new(r"IPv4 Address.*:\s*(\d+\.\d+\.\d+\.\d+)").unwrap();
    let subnet_pattern = Regex::new(r"Subnet Mask.*:\s*(\d+\.\d+\.\d+\.\d+)").unwrap();
    let gateway_pattern = Regex::new(r"Default Gateway.*:\s*(\d+\.\d+\.\d+\.\d+)").unwrap();
    let dns_pattern = Regex::new(r"DNS Servers.*:\s*(\d+\.\d+\.\d+\.\d+)").unwrap();
    let mac_pattern = Regex::new(r"Physical Address.*:\s*([0-9A-Fa-f-]+)").unwrap();
    let ip_continuation = Regex::new(r"^\s+(\d+\.\d+\.\d+\.\d+)").unwrap();

    for line in output_str.lines() {
        // Check for adapter header
        if adapter_pattern.is_match(line) {
            // If we already found our target, stop
            if in_target_adapter && status.ip_address.is_some() {
                break;
            }

            // Check if this is our target interface
            if let Some(iface) = interface {
                in_target_adapter = line.to_lowercase().contains(&iface.to_lowercase());
            } else {
                // Default to Wi-Fi or first adapter with IP
                in_target_adapter = line.to_lowercase().contains("wi-fi")
                    || line.to_lowercase().contains("wireless");
            }
            collecting_dns = false;
            continue;
        }

        if !in_target_adapter {
            continue;
        }

        // Extract values
        if let Some(caps) = ipv4_pattern.captures(line) {
            status.ip_address = Some(caps[1].to_string());
            collecting_dns = false;
        } else if let Some(caps) = subnet_pattern.captures(line) {
            status.subnet_mask = Some(caps[1].to_string());
            collecting_dns = false;
        } else if let Some(caps) = gateway_pattern.captures(line) {
            status.gateway = Some(caps[1].to_string());
            collecting_dns = false;
        } else if let Some(caps) = dns_pattern.captures(line) {
            dns_servers.push(caps[1].to_string());
            collecting_dns = true;
        } else if collecting_dns {
            if let Some(caps) = ip_continuation.captures(line) {
                dns_servers.push(caps[1].to_string());
            } else if !line.trim().is_empty() && !line.starts_with(' ') {
                collecting_dns = false;
            }
        }

        if let Some(caps) = mac_pattern.captures(line) {
            // Convert from XX-XX-XX-XX-XX-XX to XX:XX:XX:XX:XX:XX
            status.mac_address = Some(caps[1].replace('-', ":"));
        }
    }

    if !dns_servers.is_empty() {
        status.dns_servers = Some(dns_servers);
    }

    Ok(status)
}

fn extract_value(line: &str) -> Option<&str> {
    line.split_once(':').map(|(_, v)| v.trim())
}
