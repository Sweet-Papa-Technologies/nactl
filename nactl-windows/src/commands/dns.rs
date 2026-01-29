//! DNS management command implementations

use crate::errors::{ExitCodes, NactlError};
use crate::utils::admin;
use crate::utils::netsh;
use crate::utils::output::{print_output, OutputFormat};
use crate::utils::validation;
use serde::Serialize;
use std::process::Command;

#[derive(Debug, Serialize)]
struct FlushResponse {
    success: bool,
    message: String,
}

#[derive(Debug, Serialize)]
struct SetDnsData {
    interface: String,
    primary: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    secondary: Option<String>,
}

#[derive(Debug, Serialize)]
struct SetDnsResponse {
    success: bool,
    message: String,
    data: SetDnsData,
}

#[derive(Debug, Serialize)]
struct ResetResponse {
    success: bool,
    message: String,
}

/// Flush DNS resolver cache
pub fn flush(format: OutputFormat) -> Result<u8, NactlError> {
    // Run ipconfig /flushdns
    let output = Command::new("ipconfig")
        .arg("/flushdns")
        .output()
        .map_err(|e| NactlError::command_failed(format!("Failed to run ipconfig: {}", e)))?;

    let output_str = String::from_utf8_lossy(&output.stdout);

    // Check for success
    let success = output.status.success()
        && (output_str.contains("Successfully flushed")
            || output_str.contains("successfully flushed"));

    let response = FlushResponse {
        success,
        message: if success {
            "DNS cache flushed successfully".to_string()
        } else {
            format!("Failed to flush DNS cache: {}", output_str.trim())
        },
    };

    print_output(&response, format)?;

    if success {
        Ok(ExitCodes::Success as u8)
    } else {
        Ok(ExitCodes::GeneralError as u8)
    }
}

/// Set custom DNS servers
pub fn set(
    primary: &str,
    secondary: Option<&str>,
    format: OutputFormat,
    interface: Option<&str>,
) -> Result<u8, NactlError> {
    // Validate IP addresses
    validation::validate_ip_address(primary)?;
    if let Some(sec) = secondary {
        validation::validate_ip_address(sec)?;
    }

    // Check for admin privileges
    if !admin::is_elevated() {
        return Err(NactlError::permission_denied(
            "Setting DNS servers requires administrator privileges",
        ));
    }

    // Get the interface name (default to Wi-Fi)
    let iface = interface.unwrap_or("Wi-Fi");

    // Set primary DNS
    // netsh interface ip set dns "Wi-Fi" static 1.1.1.1
    let result = netsh::run_command(&["interface", "ip", "set", "dns", iface, "static", primary]);

    if let Err(e) = result {
        // Check if interface not found
        let err_str = e.to_string();
        if err_str.contains("not found") || err_str.contains("does not exist") {
            return Err(NactlError::interface_not_found(iface));
        }
        return Err(e);
    }

    // Set secondary DNS if provided
    if let Some(sec) = secondary {
        // netsh interface ip add dns "Wi-Fi" 1.0.0.1 index=2
        let _ = netsh::run_command(&["interface", "ip", "add", "dns", iface, sec, "index=2"]);
    }

    let response = SetDnsResponse {
        success: true,
        message: "DNS servers updated".to_string(),
        data: SetDnsData {
            interface: iface.to_string(),
            primary: primary.to_string(),
            secondary: secondary.map(String::from),
        },
    };

    print_output(&response, format)?;
    Ok(ExitCodes::Success as u8)
}

/// Reset DNS to automatic (DHCP)
pub fn reset(format: OutputFormat, interface: Option<&str>) -> Result<u8, NactlError> {
    // Check for admin privileges
    if !admin::is_elevated() {
        return Err(NactlError::permission_denied(
            "Resetting DNS requires administrator privileges",
        ));
    }

    // Get the interface name (default to Wi-Fi)
    let iface = interface.unwrap_or("Wi-Fi");

    // Reset to DHCP
    // netsh interface ip set dns "Wi-Fi" dhcp
    let result = netsh::run_command(&["interface", "ip", "set", "dns", iface, "dhcp"]);

    if let Err(e) = result {
        let err_str = e.to_string();
        if err_str.contains("not found") || err_str.contains("does not exist") {
            return Err(NactlError::interface_not_found(iface));
        }
        return Err(e);
    }

    let response = ResetResponse {
        success: true,
        message: "DNS reset to automatic (DHCP)".to_string(),
    };

    print_output(&response, format)?;
    Ok(ExitCodes::Success as u8)
}
