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

        if combined.contains("requires elevation")
            || combined.contains("Access is denied")
            || combined.contains("Administrator")
        {
            return Err(NactlError::permission_denied(
                "This operation requires administrator privileges",
            ));
        }

        if combined.contains("is not found")
            || combined.contains("does not exist")
            || combined.contains("not found")
        {
            return Err(NactlError::general_error(combined.trim().to_string()));
        }

        return Err(NactlError::command_failed(format!(
            "netsh command failed: {}",
            combined.trim()
        )));
    }

    Ok(stdout)
}

/// Run a netsh command and check if it succeeds
pub fn run_command_status(args: &[&str]) -> bool {
    Command::new("netsh")
        .args(args)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
