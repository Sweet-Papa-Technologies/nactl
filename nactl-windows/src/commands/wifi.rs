//! Wi-Fi management command implementations

use crate::errors::{ExitCodes, NactlError};
use crate::utils::admin;
use crate::utils::netsh;
use crate::utils::output::{print_output, OutputFormat};
use crate::utils::validation;
use regex::Regex;
use serde::Serialize;
use std::time::Instant;

#[derive(Debug, Serialize)]
struct WifiNetwork {
    ssid: String,
    bssid: String,
    signal_strength: i32,
    signal_rssi: i32,
    channel: u32,
    frequency: String,
    security: String,
    known: bool,
}

#[derive(Debug, Serialize)]
struct ScanData {
    networks: Vec<WifiNetwork>,
    scan_time_ms: u64,
}

#[derive(Debug, Serialize)]
struct ScanResponse {
    success: bool,
    data: ScanData,
}

#[derive(Debug, Serialize)]
struct ForgetData {
    ssid: String,
    was_connected: bool,
    keychain_cleared: bool,
}

#[derive(Debug, Serialize)]
struct ForgetResponse {
    success: bool,
    message: String,
    data: ForgetData,
}

/// Scan for available Wi-Fi networks
pub fn scan(format: OutputFormat) -> Result<u8, NactlError> {
    let start_time = Instant::now();

    // Get known networks first
    let known_networks = get_known_networks();

    // Run netsh wlan show networks mode=bssid
    let output = netsh::run_command(&["wlan", "show", "networks", "mode=bssid"])?;

    let networks = parse_wifi_networks(&output, &known_networks)?;
    let scan_time = start_time.elapsed().as_millis() as u64;

    let response = ScanResponse {
        success: true,
        data: ScanData {
            networks,
            scan_time_ms: scan_time,
        },
    };

    print_output(&response, format)?;
    Ok(ExitCodes::Success as u8)
}

/// Remove a saved Wi-Fi network profile
pub fn forget(ssid: &str, format: OutputFormat) -> Result<u8, NactlError> {
    // Validate SSID
    validation::validate_ssid(ssid)?;

    // Check for admin privileges
    if !admin::is_elevated() {
        return Err(NactlError::permission_denied(
            "Forgetting Wi-Fi networks requires administrator privileges",
        ));
    }

    // Check if currently connected to this network
    let was_connected = is_connected_to(ssid);

    // Delete the profile
    // netsh wlan delete profile name="NetworkName"
    let result = netsh::run_command(&["wlan", "delete", "profile", &format!("name={}", ssid)]);

    match result {
        Ok(output) => {
            let success = output.contains("deleted") || output.contains("successfully");

            if !success && output.contains("is not found") {
                return Err(NactlError::general_error(format!(
                    "Network '{}' not found in saved profiles",
                    ssid
                )));
            }

            let response = ForgetResponse {
                success,
                message: format!("Network '{}' forgotten", ssid),
                data: ForgetData {
                    ssid: ssid.to_string(),
                    was_connected,
                    keychain_cleared: true, // Windows stores credentials with profile
                },
            };

            print_output(&response, format)?;
            Ok(ExitCodes::Success as u8)
        }
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("is not found") || err_str.contains("not found") {
                Err(NactlError::general_error(format!(
                    "Network '{}' not found in saved profiles",
                    ssid
                )))
            } else {
                Err(e)
            }
        }
    }
}

fn get_known_networks() -> Vec<String> {
    let mut known = Vec::new();

    // Get list of saved profiles
    if let Ok(output) = netsh::run_command(&["wlan", "show", "profiles"]) {
        let profile_pattern = Regex::new(r"All User Profile\s*:\s*(.+)$").unwrap();

        for line in output.lines() {
            if let Some(caps) = profile_pattern.captures(line) {
                known.push(caps[1].trim().to_string());
            }
        }
    }

    known
}

fn is_connected_to(ssid: &str) -> bool {
    if let Ok(output) = netsh::run_command(&["wlan", "show", "interfaces"]) {
        let ssid_pattern = Regex::new(r"^\s*SSID\s*:\s*(.+)$").unwrap();
        let state_pattern = Regex::new(r"^\s*State\s*:\s*connected").unwrap();

        let mut found_connected = false;

        for line in output.lines() {
            if state_pattern.is_match(line) {
                found_connected = true;
            }
            if found_connected {
                if let Some(caps) = ssid_pattern.captures(line) {
                    return caps[1].trim() == ssid;
                }
            }
        }
    }
    false
}

fn parse_wifi_networks(
    output: &str,
    known_networks: &[String],
) -> Result<Vec<WifiNetwork>, NactlError> {
    let mut networks: Vec<WifiNetwork> = Vec::new();

    // Current network being parsed
    let mut current_ssid: Option<String> = None;
    let mut current_security: Option<String> = None;

    // Patterns for parsing
    let ssid_pattern = Regex::new(r"^SSID\s+\d+\s*:\s*(.*)$").unwrap();
    let security_pattern = Regex::new(r"^\s*Authentication\s*:\s*(.+)$").unwrap();
    let bssid_pattern = Regex::new(r"^\s*BSSID\s+\d+\s*:\s*([0-9a-fA-F:]+)").unwrap();
    let signal_pattern = Regex::new(r"^\s*Signal\s*:\s*(\d+)%").unwrap();
    let channel_pattern = Regex::new(r"^\s*Channel\s*:\s*(\d+)").unwrap();

    let mut current_bssid: Option<String> = None;
    let mut current_signal: Option<i32> = None;
    let mut current_channel: Option<u32> = None;

    for line in output.lines() {
        let line = line.trim_end();

        // New network SSID
        if let Some(caps) = ssid_pattern.captures(line) {
            // Save previous network if exists
            if let (Some(ssid), Some(bssid)) = (&current_ssid, &current_bssid) {
                let signal = current_signal.unwrap_or(0);
                let channel = current_channel.unwrap_or(0);

                networks.push(WifiNetwork {
                    ssid: ssid.clone(),
                    bssid: bssid.clone(),
                    signal_strength: signal,
                    signal_rssi: signal_to_rssi(signal),
                    channel,
                    frequency: channel_to_frequency(channel),
                    security: current_security
                        .clone()
                        .unwrap_or_else(|| "Unknown".to_string()),
                    known: known_networks.contains(ssid),
                });
            }

            current_ssid = Some(caps[1].trim().to_string());
            current_bssid = None;
            current_signal = None;
            current_channel = None;
            current_security = None;
        }

        // Security/Authentication
        if let Some(caps) = security_pattern.captures(line) {
            current_security = Some(normalize_security(caps[1].trim()));
        }

        // BSSID (access point MAC)
        if let Some(caps) = bssid_pattern.captures(line) {
            // If we have a previous BSSID for same SSID, save it first
            if let (Some(ssid), Some(bssid)) = (&current_ssid, &current_bssid) {
                let signal = current_signal.unwrap_or(0);
                let channel = current_channel.unwrap_or(0);

                networks.push(WifiNetwork {
                    ssid: ssid.clone(),
                    bssid: bssid.clone(),
                    signal_strength: signal,
                    signal_rssi: signal_to_rssi(signal),
                    channel,
                    frequency: channel_to_frequency(channel),
                    security: current_security
                        .clone()
                        .unwrap_or_else(|| "Unknown".to_string()),
                    known: known_networks.contains(ssid),
                });
            }

            current_bssid = Some(caps[1].to_uppercase());
            current_signal = None;
            current_channel = None;
        }

        // Signal strength
        if let Some(caps) = signal_pattern.captures(line) {
            if let Ok(signal) = caps[1].parse::<i32>() {
                current_signal = Some(signal);
            }
        }

        // Channel
        if let Some(caps) = channel_pattern.captures(line) {
            if let Ok(channel) = caps[1].parse::<u32>() {
                current_channel = Some(channel);
            }
        }
    }

    // Don't forget the last network
    if let (Some(ssid), Some(bssid)) = (&current_ssid, &current_bssid) {
        let signal = current_signal.unwrap_or(0);
        let channel = current_channel.unwrap_or(0);

        networks.push(WifiNetwork {
            ssid: ssid.clone(),
            bssid: bssid.clone(),
            signal_strength: signal,
            signal_rssi: signal_to_rssi(signal),
            channel,
            frequency: channel_to_frequency(channel),
            security: current_security
                .clone()
                .unwrap_or_else(|| "Unknown".to_string()),
            known: known_networks.contains(ssid),
        });
    }

    // Sort by signal strength (descending)
    networks.sort_by(|a, b| b.signal_strength.cmp(&a.signal_strength));

    Ok(networks)
}

fn signal_to_rssi(signal_percent: i32) -> i32 {
    // Approximate RSSI from percentage
    // 100% ~ -30 dBm, 0% ~ -100 dBm
    -100 + (signal_percent * 70 / 100)
}

fn channel_to_frequency(channel: u32) -> String {
    if channel == 0 {
        "Unknown".to_string()
    } else if channel <= 14 {
        "2.4GHz".to_string()
    } else {
        "5GHz".to_string()
    }
}

fn normalize_security(auth: &str) -> String {
    let auth_lower = auth.to_lowercase();

    if auth_lower.contains("wpa3") {
        if auth_lower.contains("enterprise") {
            "WPA3-Enterprise".to_string()
        } else {
            "WPA3-SAE".to_string()
        }
    } else if auth_lower.contains("wpa2") {
        if auth_lower.contains("enterprise") {
            "WPA2-Enterprise".to_string()
        } else {
            "WPA2-Personal".to_string()
        }
    } else if auth_lower.contains("wpa") {
        if auth_lower.contains("enterprise") {
            "WPA-Enterprise".to_string()
        } else {
            "WPA-Personal".to_string()
        }
    } else if auth_lower.contains("wep") {
        "WEP".to_string()
    } else if auth_lower.contains("open") {
        "Open".to_string()
    } else {
        auth.to_string()
    }
}
