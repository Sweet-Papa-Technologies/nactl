//! Input validation utilities to prevent command injection

use crate::errors::NactlError;
use regex::Regex;

/// Maximum SSID length per Wi-Fi specification
const MAX_SSID_LENGTH: usize = 32;

/// Maximum hostname length per DNS specification
const MAX_HOSTNAME_LENGTH: usize = 253;

/// Validate an SSID to prevent command injection
pub fn validate_ssid(ssid: &str) -> Result<(), NactlError> {
    if ssid.is_empty() {
        return Err(NactlError::invalid_input("SSID cannot be empty"));
    }

    if ssid.len() > MAX_SSID_LENGTH {
        return Err(NactlError::invalid_input(format!(
            "SSID too long (max {} characters)",
            MAX_SSID_LENGTH
        )));
    }

    // Check for dangerous characters that could be used for command injection
    let dangerous_chars = ['\"', '\'', '\\', '\n', '\r', '\0', '`', '$', '|', ';', '&', '<', '>'];
    for c in dangerous_chars {
        if ssid.contains(c) {
            return Err(NactlError::invalid_input(format!(
                "SSID contains invalid character: {:?}",
                c
            )));
        }
    }

    Ok(())
}

/// Validate a hostname to prevent command injection
pub fn validate_hostname(hostname: &str) -> Result<(), NactlError> {
    if hostname.is_empty() {
        return Err(NactlError::invalid_input("Hostname cannot be empty"));
    }

    if hostname.len() > MAX_HOSTNAME_LENGTH {
        return Err(NactlError::invalid_input(format!(
            "Hostname too long (max {} characters)",
            MAX_HOSTNAME_LENGTH
        )));
    }

    // Valid hostname pattern: alphanumeric, hyphens, dots
    // Also allow IPv4 and IPv6 addresses
    let hostname_pattern = Regex::new(
        r"^([a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$"
    ).unwrap();

    let ipv4_pattern = Regex::new(
        r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"
    ).unwrap();

    let ipv6_pattern = Regex::new(
        r"^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$|^::1$|^::$"
    ).unwrap();

    if !hostname_pattern.is_match(hostname)
        && !ipv4_pattern.is_match(hostname)
        && !ipv6_pattern.is_match(hostname)
    {
        return Err(NactlError::invalid_input(format!(
            "Invalid hostname format: {}",
            hostname
        )));
    }

    // Additional check for dangerous patterns
    let dangerous_patterns = ["&&", "||", ";", "|", "`", "$(", "${", "\n", "\r"];
    for pattern in dangerous_patterns {
        if hostname.contains(pattern) {
            return Err(NactlError::invalid_input(
                "Hostname contains invalid characters",
            ));
        }
    }

    Ok(())
}

/// Validate an IP address
pub fn validate_ip_address(ip: &str) -> Result<(), NactlError> {
    if ip.is_empty() {
        return Err(NactlError::invalid_input("IP address cannot be empty"));
    }

    // IPv4 validation
    let ipv4_pattern = Regex::new(
        r"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    ).unwrap();

    // IPv6 validation (simplified)
    let ipv6_pattern = Regex::new(
        r"^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$|^::1$|^::$"
    ).unwrap();

    if !ipv4_pattern.is_match(ip) && !ipv6_pattern.is_match(ip) {
        return Err(NactlError::invalid_input(format!(
            "Invalid IP address: {}",
            ip
        )));
    }

    Ok(())
}

/// Sanitize a string for use in command arguments (escaping special characters)
pub fn sanitize_for_command(input: &str) -> String {
    // For Windows, we escape double quotes by doubling them
    input.replace('"', "\"\"")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_ssid_valid() {
        assert!(validate_ssid("MyNetwork").is_ok());
        assert!(validate_ssid("Network-5G").is_ok());
        assert!(validate_ssid("Guest WiFi").is_ok());
    }

    #[test]
    fn test_validate_ssid_invalid() {
        assert!(validate_ssid("").is_err());
        assert!(validate_ssid("Net\"work").is_err());
        assert!(validate_ssid("Net;work").is_err());
        assert!(validate_ssid("a".repeat(33).as_str()).is_err());
    }

    #[test]
    fn test_validate_hostname_valid() {
        assert!(validate_hostname("google.com").is_ok());
        assert!(validate_hostname("192.168.1.1").is_ok());
        assert!(validate_hostname("sub.domain.example.com").is_ok());
    }

    #[test]
    fn test_validate_hostname_invalid() {
        assert!(validate_hostname("").is_err());
        assert!(validate_hostname("host;rm -rf").is_err());
        assert!(validate_hostname("host|cat /etc/passwd").is_err());
    }

    #[test]
    fn test_validate_ip_valid() {
        assert!(validate_ip_address("192.168.1.1").is_ok());
        assert!(validate_ip_address("8.8.8.8").is_ok());
        assert!(validate_ip_address("255.255.255.255").is_ok());
    }

    #[test]
    fn test_validate_ip_invalid() {
        assert!(validate_ip_address("").is_err());
        assert!(validate_ip_address("256.1.1.1").is_err());
        assert!(validate_ip_address("not.an.ip").is_err());
    }
}
