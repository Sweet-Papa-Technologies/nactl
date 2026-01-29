//! PowerShell execution utilities

use crate::errors::NactlError;
use std::process::Command;

/// Run a PowerShell script
pub fn run_script(script: &str) -> Result<String, NactlError> {
    let output = Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ])
        .output()
        .map_err(|e| NactlError::command_failed(format!("Failed to run PowerShell: {}", e)))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        let combined = format!("{}{}", stdout, stderr);

        if combined.contains("Access is denied")
            || combined.contains("requires elevation")
            || combined.contains("Administrator")
        {
            return Err(NactlError::permission_denied(
                "This operation requires administrator privileges",
            ));
        }

        return Err(NactlError::command_failed(format!(
            "PowerShell command failed: {}",
            combined.trim()
        )));
    }

    Ok(stdout)
}

/// Run a PowerShell command and check if it succeeds
pub fn run_script_status(script: &str) -> bool {
    Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Get PowerShell to return JSON output
pub fn run_script_json(script: &str) -> Result<String, NactlError> {
    let json_script = format!("{} | ConvertTo-Json -Compress", script);
    run_script(&json_script)
}
