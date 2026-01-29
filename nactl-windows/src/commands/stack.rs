//! Network stack reset command implementation

use crate::errors::{ExitCodes, NactlError};
use crate::utils::admin;
use crate::utils::netsh;
use crate::utils::output::{print_output, OutputFormat};
use crate::utils::powershell;
use crate::utils::validation;
use serde::Serialize;
use std::process::Command;

#[derive(Debug, Serialize)]
struct StackResetData {
    level: String,
    actions_performed: Vec<String>,
    reboot_required: bool,
}

#[derive(Debug, Serialize)]
struct StackResetResponse {
    success: bool,
    message: String,
    data: StackResetData,
}

pub fn reset(level: &str, format: OutputFormat, interface: Option<&str>) -> Result<u8, NactlError> {
    // Validate level
    let level = level.to_lowercase();
    if level != "soft" && level != "hard" {
        return Err(NactlError::invalid_arguments(
            "Level must be 'soft' or 'hard'",
        ));
    }

    // Check for admin privileges
    if !admin::is_elevated() {
        return Err(NactlError::permission_denied(
            "Network stack reset requires administrator privileges",
        ));
    }

    let mut actions: Vec<String> = Vec::new();

    let success = if level == "soft" {
        // Soft reset: flush caches, release/renew IP, restart adapter
        perform_soft_reset(&mut actions, interface)
    } else {
        // Hard reset: Winsock and TCP/IP reset
        perform_hard_reset(&mut actions)
    };

    let response = StackResetResponse {
        success,
        message: if success {
            "Network stack reset complete".to_string()
        } else {
            "Network stack reset completed with some errors".to_string()
        },
        data: StackResetData {
            level: level.clone(),
            actions_performed: actions,
            reboot_required: level == "hard",
        },
    };

    print_output(&response, format)?;
    Ok(ExitCodes::Success as u8)
}

fn perform_soft_reset(actions: &mut Vec<String>, interface: Option<&str>) -> bool {
    let mut all_success = true;

    // 1. Flush DNS cache
    if let Ok(output) = Command::new("ipconfig").arg("/flushdns").output() {
        if output.status.success() {
            actions.push("Flushed DNS cache".to_string());
        } else {
            all_success = false;
        }
    }

    // 2. Release IP address
    if let Ok(output) = Command::new("ipconfig").arg("/release").output() {
        if output.status.success() {
            actions.push("Released IP address".to_string());
        } else {
            // Release might fail if no DHCP lease, continue anyway
        }
    }

    // 3. Flush ARP cache
    if let Ok(_) = netsh::run_command(&["interface", "ip", "delete", "arpcache"]) {
        actions.push("Flushed ARP cache".to_string());
    }

    // 4. Renew IP address
    if let Ok(output) = Command::new("ipconfig").arg("/renew").output() {
        if output.status.success() {
            actions.push("Renewed IP address".to_string());
        } else {
            // Renew might take time or fail if no DHCP server
        }
    }

    // 5. Restart network adapter
    let adapter_name = interface.unwrap_or("Wi-Fi");
    if restart_network_adapter(adapter_name) {
        actions.push(format!("Restarted network adapter '{}'", adapter_name));
    } else {
        // Try Ethernet if Wi-Fi fails
        if interface.is_none() && restart_network_adapter("Ethernet") {
            actions.push("Restarted network adapter 'Ethernet'".to_string());
        }
    }

    all_success
}

fn perform_hard_reset(actions: &mut Vec<String>) -> bool {
    let mut all_success = true;

    // 1. Reset Winsock catalog
    if let Ok(_) = netsh::run_command(&["winsock", "reset"]) {
        actions.push("Reset Winsock catalog".to_string());
    } else {
        all_success = false;
    }

    // 2. Reset TCP/IP stack
    // Note: This writes a log file but we'll ignore the path
    if let Ok(_) = netsh::run_command(&["int", "ip", "reset"]) {
        actions.push("Reset TCP/IP stack".to_string());
    } else {
        all_success = false;
    }

    // 3. Reset IPv6
    if let Ok(_) = netsh::run_command(&["int", "ipv6", "reset"]) {
        actions.push("Reset IPv6 stack".to_string());
    }

    // 4. Flush DNS
    if let Ok(output) = Command::new("ipconfig").arg("/flushdns").output() {
        if output.status.success() {
            actions.push("Flushed DNS cache".to_string());
        }
    }

    // 5. Reset firewall rules (optional, might be risky)
    // Skipping this as it could cause security issues

    all_success
}

fn restart_network_adapter(adapter_name: &str) -> bool {
    // Use PowerShell to restart the adapter
    // Restart-NetAdapter -Name "Wi-Fi" -Confirm:$false
    // Sanitize the adapter name to prevent command injection
    let sanitized_name = validation::sanitize_for_command(adapter_name);
    let script = format!(
        "Restart-NetAdapter -Name \"{}\" -Confirm:$false",
        sanitized_name
    );

    powershell::run_script_status(&script)
}
