//! Ping command implementation

use crate::errors::{ExitCodes, NactlError};
use crate::utils::output::{print_output, OutputFormat};
use crate::utils::validation;
use regex::Regex;
use serde::Serialize;
use std::process::Command;

#[derive(Debug, Serialize)]
struct PingResult {
    seq: u32,
    ttl: Option<u32>,
    time_ms: Option<f64>,
}

#[derive(Debug, Serialize)]
struct PingData {
    host: String,
    resolved_ip: Option<String>,
    packets_sent: u32,
    packets_received: u32,
    packet_loss_percent: f64,
    min_ms: Option<f64>,
    avg_ms: Option<f64>,
    max_ms: Option<f64>,
    results: Vec<PingResult>,
}

#[derive(Debug, Serialize)]
struct PingResponse {
    success: bool,
    data: PingData,
}

pub fn execute(
    host: &str,
    count: u32,
    timeout: u32,
    format: OutputFormat,
) -> Result<u8, NactlError> {
    // Validate input to prevent command injection
    validation::validate_hostname(host)?;

    // Run ping command
    // Windows ping: -n count, -w timeout (in milliseconds)
    let output = Command::new("ping")
        .args(["-n", &count.to_string(), "-w", &timeout.to_string(), host])
        .output()
        .map_err(|e| NactlError::command_failed(format!("Failed to run ping: {}", e)))?;

    let output_str = String::from_utf8_lossy(&output.stdout);
    let data = parse_ping_output(&output_str, host, count)?;

    let response = PingResponse {
        success: data.packets_received > 0,
        data,
    };

    print_output(&response, format)?;

    if response.data.packets_received == 0 {
        Ok(ExitCodes::Timeout as u8)
    } else {
        Ok(ExitCodes::Success as u8)
    }
}

fn parse_ping_output(output: &str, host: &str, count: u32) -> Result<PingData, NactlError> {
    let mut data = PingData {
        host: host.to_string(),
        resolved_ip: None,
        packets_sent: count,
        packets_received: 0,
        packet_loss_percent: 100.0,
        min_ms: None,
        avg_ms: None,
        max_ms: None,
        results: Vec::new(),
    };

    // Pattern to extract resolved IP from "Pinging hostname [IP]" or "Pinging IP"
    let ip_pattern = Regex::new(r"Pinging\s+\S+\s+\[?(\d+\.\d+\.\d+\.\d+)\]?").unwrap();
    if let Some(caps) = ip_pattern.captures(output) {
        data.resolved_ip = Some(caps[1].to_string());
    }

    // Pattern for individual ping replies
    // "Reply from 142.250.80.46: bytes=32 time=12ms TTL=117"
    let reply_pattern =
        Regex::new(r"Reply from (\d+\.\d+\.\d+\.\d+):.*?(?:time[<=](\d+)ms)?.*?TTL=(\d+)").unwrap();

    // Pattern for timeout
    let timeout_pattern = Regex::new(r"Request timed out|Destination host unreachable").unwrap();

    let mut seq = 0u32;
    let mut times: Vec<f64> = Vec::new();

    for line in output.lines() {
        if let Some(caps) = reply_pattern.captures(line) {
            seq += 1;

            // Get IP if not already set
            if data.resolved_ip.is_none() {
                data.resolved_ip = Some(caps[1].to_string());
            }

            let time_ms = caps.get(2).and_then(|m| m.as_str().parse::<f64>().ok());
            let ttl = caps.get(3).and_then(|m| m.as_str().parse::<u32>().ok());

            if let Some(t) = time_ms {
                times.push(t);
            }

            data.results.push(PingResult { seq, ttl, time_ms });
            data.packets_received += 1;
        } else if timeout_pattern.is_match(line) {
            seq += 1;
            data.results.push(PingResult {
                seq,
                ttl: None,
                time_ms: None,
            });
        }
    }

    // Calculate statistics
    if !times.is_empty() {
        data.min_ms = times.iter().cloned().reduce(f64::min);
        data.max_ms = times.iter().cloned().reduce(f64::max);
        data.avg_ms = Some(times.iter().sum::<f64>() / times.len() as f64);
    }

    // Calculate packet loss
    if data.packets_sent > 0 {
        data.packet_loss_percent =
            ((data.packets_sent - data.packets_received) as f64 / data.packets_sent as f64) * 100.0;
    }

    // Parse statistics line as fallback
    // "Packets: Sent = 4, Received = 4, Lost = 0 (0% loss)"
    let stats_pattern =
        Regex::new(r"Sent\s*=\s*(\d+),\s*Received\s*=\s*(\d+),\s*Lost\s*=\s*(\d+)\s*\((\d+)%")
            .unwrap();

    if let Some(caps) = stats_pattern.captures(output) {
        if let Ok(sent) = caps[1].parse::<u32>() {
            data.packets_sent = sent;
        }
        if let Ok(received) = caps[2].parse::<u32>() {
            data.packets_received = received;
        }
        if let Ok(loss) = caps[4].parse::<f64>() {
            data.packet_loss_percent = loss;
        }
    }

    // Parse min/max/avg from statistics
    // "Minimum = 12ms, Maximum = 18ms, Average = 15ms"
    let timing_pattern =
        Regex::new(r"Minimum\s*=\s*(\d+)ms,\s*Maximum\s*=\s*(\d+)ms,\s*Average\s*=\s*(\d+)ms")
            .unwrap();

    if let Some(caps) = timing_pattern.captures(output) {
        if data.min_ms.is_none() {
            data.min_ms = caps[1].parse::<f64>().ok();
        }
        if data.max_ms.is_none() {
            data.max_ms = caps[2].parse::<f64>().ok();
        }
        if data.avg_ms.is_none() {
            data.avg_ms = caps[3].parse::<f64>().ok();
        }
    }

    Ok(data)
}
