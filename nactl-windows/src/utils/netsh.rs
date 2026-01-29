//! Wrapper for netsh command execution

use crate::errors::NactlError;
use std::process::Command;

/// Run a netsh command with the given arguments
pub fn run_command(args: &[&str]) -> Result<String, NactlError> {
    let output = Command::new("netsh")
        .args(args)
        .output()
        .map_err(|e| NactlError::command_failed(format!("Failed to run netsh: {}", e)))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        // Check for common error patterns
        let combined = format!("{}{}", stdout, stderr);
        let combined_lower = combined.to_lowercase();

        // Be more specific about elevation errors to avoid false positives
        if combined_lower.contains("requires elevation")
            || combined_lower.contains("access is denied")
            || combined_lower.contains("run as administrator")
            || combined_lower.contains("elevated permissions")
        {
            return Err(NactlError::permission_denied(
                "This operation requires administrator privileges",
            ));
        }

        if combined_lower.contains("is not found")
            || combined_lower.contains("does not exist")
            || combined_lower.contains("not found")
        {
            return Err(NactlError::general_error(combined.trim().to_string()));
        }

        // Check for WLAN service issues
        if combined_lower.contains("wireless autoconfig")
            || combined_lower.contains("wlan autoconfig")
            || combined_lower.contains("service is not running")
        {
            return Err(NactlError::not_available(
                "The Wireless AutoConfig Service is not running. Start it with: net start WlanSvc",
            ));
        }

        // Check for no wireless interface
        if combined_lower.contains("no wireless interface")
            || combined_lower.contains("wireless lan interface")
        {
            return Err(NactlError::interface_not_found("Wi-Fi"));
        }

        return Err(NactlError::command_failed(format!(
            "netsh command failed: {}",
            combined.trim()
        )));
    }

    Ok(stdout)
}

/// Run a netsh command and check if it succeeds
#[allow(dead_code)]
pub fn run_command_status(args: &[&str]) -> bool {
    Command::new("netsh")
        .args(args)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
