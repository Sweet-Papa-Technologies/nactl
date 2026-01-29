//! Traceroute command implementation

use crate::errors::{ExitCodes, NactlError};
use crate::utils::output::{print_output, OutputFormat};
use crate::utils::validation;
use regex::Regex;
use serde::Serialize;
use std::process::Command;

#[derive(Debug, Serialize)]
struct HopResult {
    hop: u32,
    ip: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    hostname: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    time_ms: Option<Vec<f64>>,
}

#[derive(Debug, Serialize)]
struct TraceData {
    host: String,
    hops: Vec<HopResult>,
    destination_reached: bool,
    total_hops: u32,
}

#[derive(Debug, Serialize)]
struct TraceResponse {
    success: bool,
    data: TraceData,
}

pub fn execute(host: &str, max_hops: u32, timeout: u32, format: OutputFormat) -> Result<u8, NactlError> {
    // Validate input to prevent command injection
    validation::validate_hostname(host)?;

    // Calculate per-hop timeout from overall timeout
    // tracert -w is timeout per probe in milliseconds
    let per_hop_timeout = if timeout == 0 {
        5000  // 5 seconds per hop if no overall timeout specified
    } else {
        // Divide overall timeout by (max_hops * 3 probes per hop), min 500ms
        std::cmp::max(500, timeout / (max_hops * 3))
    };

    // Run tracert command
    // Windows tracert: -h max_hops, -w timeout_per_probe
    let output = Command::new("tracert")
        .args([
            "-h", &max_hops.to_string(),
            "-w", &per_hop_timeout.to_string(),
            host,
        ])
        .output()
        .map_err(|e| NactlError::command_failed(format!("Failed to run tracert: {}", e)))?;

    let output_str = String::from_utf8_lossy(&output.stdout);
    let data = parse_tracert_output(&output_str, host)?;

    let response = TraceResponse {
        success: data.destination_reached,
        data,
    };

    print_output(&response, format)?;
    Ok(ExitCodes::Success as u8)
}

fn parse_tracert_output(output: &str, host: &str) -> Result<TraceData, NactlError> {
    let mut data = TraceData {
        host: host.to_string(),
        hops: Vec::new(),
        destination_reached: false,
        total_hops: 0,
    };

    // Pattern for hop lines:
    // "  1    <1 ms    <1 ms    <1 ms  192.168.1.1"
    // "  2     8 ms     9 ms     8 ms  10.0.0.1"
    // "  3     *        *        *     Request timed out."
    // "  2    12 ms    11 ms    12 ms  hostname.example.com [192.168.1.1]"
    let hop_pattern = Regex::new(
        r"^\s*(\d+)\s+(?:(<?\d+)\s*ms|(\*))\s+(?:(<?\d+)\s*ms|(\*))\s+(?:(<?\d+)\s*ms|(\*))\s+(.+)$"
    ).unwrap();

    // Pattern to extract IP and optional hostname
    let ip_pattern = Regex::new(r"(\d+\.\d+\.\d+\.\d+)").unwrap();
    let hostname_ip_pattern = Regex::new(r"(\S+)\s+\[(\d+\.\d+\.\d+\.\d+)\]").unwrap();

    // Get destination IP from header
    let dest_ip_pattern = Regex::new(r"Tracing route to.*\[?(\d+\.\d+\.\d+\.\d+)\]?").unwrap();
    let mut destination_ip: Option<String> = None;

    if let Some(caps) = dest_ip_pattern.captures(output) {
        destination_ip = Some(caps[1].to_string());
    }

    for line in output.lines() {
        if let Some(caps) = hop_pattern.captures(line) {
            let hop_num: u32 = caps[1].parse().unwrap_or(0);

            // Extract timing values
            let mut times: Vec<f64> = Vec::new();

            // Time 1
            if let Some(time_match) = caps.get(2) {
                let time_str = time_match.as_str().trim_start_matches('<');
                if let Ok(t) = time_str.parse::<f64>() {
                    times.push(t);
                }
            }

            // Time 2
            if let Some(time_match) = caps.get(4) {
                let time_str = time_match.as_str().trim_start_matches('<');
                if let Ok(t) = time_str.parse::<f64>() {
                    times.push(t);
                }
            }

            // Time 3
            if let Some(time_match) = caps.get(6) {
                let time_str = time_match.as_str().trim_start_matches('<');
                if let Ok(t) = time_str.parse::<f64>() {
                    times.push(t);
                }
            }

            // Extract hostname and IP
            let rest = caps[8].trim();
            let (ip, hostname) = if rest.contains("Request timed out") || rest == "*" {
                ("*".to_string(), None)
            } else if let Some(host_caps) = hostname_ip_pattern.captures(rest) {
                (host_caps[2].to_string(), Some(host_caps[1].to_string()))
            } else if let Some(ip_caps) = ip_pattern.captures(rest) {
                (ip_caps[1].to_string(), None)
            } else {
                (rest.to_string(), None)
            };

            // Check if this is the destination
            if let Some(ref dest) = destination_ip {
                if &ip == dest {
                    data.destination_reached = true;
                }
            }

            data.hops.push(HopResult {
                hop: hop_num,
                ip,
                hostname,
                time_ms: if times.is_empty() { None } else { Some(times) },
            });

            data.total_hops = hop_num;
        }
    }

    // Check for "Trace complete" message
    if output.contains("Trace complete") {
        data.destination_reached = true;
    }

    Ok(data)
}
