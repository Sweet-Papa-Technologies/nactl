# nactl - Network Admin Control (macOS)

A native Swift CLI tool for network diagnostics, Wi-Fi management, and network stack operations on macOS.

## Overview

`nactl` is a cross-platform network administration CLI designed for FoFo Lifeline. This is the macOS implementation, built in Swift to leverage the CoreWLAN framework for reliable Wi-Fi scanning and management.

## Requirements

- macOS 12 (Monterey) or later
- Xcode Command Line Tools

## Building

```bash
# Debug build
swift build

# Release build (native architecture)
swift build -c release
# Binary: .build/release/nactl

# Universal binary (arm64 + x86_64) - works on both Apple Silicon and Intel Macs
swift build -c release --arch arm64 --arch x86_64
# Binary: .build/apple/Products/Release/nactl

# Verify universal binary architectures
lipo -info .build/apple/Products/Release/nactl
# Output: Architectures in the fat file: nactl are: x86_64 arm64
```

## Installation

```bash
# Install native build
sudo cp .build/release/nactl /usr/local/bin/

# Or install universal binary (recommended for distribution)
sudo cp .build/apple/Products/Release/nactl /usr/local/bin/
```

## Commands

### Permissions
Check Location Services permission status (informational):
```bash
# Check current permission status
nactl permissions
nactl permissions --json
```

**Note:** CLI tools cannot obtain Location Services permission on macOS—they don't appear in System Preferences > Location Services. This command reports the current status for diagnostic purposes. nactl uses fallback methods when Location Services is unavailable.

### Status
Get comprehensive network connection status:
```bash
nactl status
nactl status --json
```

### Ping
Test connectivity to a host:
```bash
nactl ping google.com
nactl ping 8.8.8.8 --count 10 --timeout 2000
nactl ping google.com --json
```

### Trace
Trace route to destination:
```bash
nactl trace google.com
nactl trace 8.8.8.8 --max-hops 20
nactl trace google.com --timeout 30000    # 30 second timeout
nactl trace google.com --timeout 0        # No timeout
nactl trace google.com --json
```

### DNS
DNS management commands:
```bash
# Flush DNS cache (requires sudo)
sudo nactl dns flush

# Set custom DNS servers (requires sudo)
sudo nactl dns set 1.1.1.1 1.0.0.1

# Reset DNS to DHCP (requires sudo)
sudo nactl dns reset
```

### Stack
Network stack reset:
```bash
# Soft reset - flush caches and restart adapter (requires sudo)
sudo nactl stack reset

# Hard reset - remove network configuration files (requires sudo, reboot required)
sudo nactl stack reset --level hard
```

### Wi-Fi
Wi-Fi management commands:
```bash
# Scan for networks
# Note: Returns empty results in limited mode (Location Services unavailable)
nactl wifi scan
nactl wifi scan --json

# Forget a saved network (requires sudo)
sudo nactl wifi forget "NetworkName"
```

**Limited Mode:** WiFi network scanning requires Location Services, which CLI tools cannot obtain on macOS. When unavailable, `wifi scan` returns a successful response with `scan_available: false` and an empty networks array. Use `nactl status` to get current connection info via fallback methods.

### Proxy
Proxy management commands:
```bash
# Get current proxy configuration
nactl proxy get
nactl proxy get --json

# Clear all proxy settings (requires sudo)
sudo nactl proxy clear
```

## Global Options

| Flag | Short | Description |
|------|-------|-------------|
| `--json` | `-j` | Force JSON output |
| `--pretty` | `-p` | Pretty-print JSON output |
| `--interface` | `-i` | Specify network interface |
| `--help` | `-h` | Show help |
| `--version` | `-v` | Show version |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (needs sudo) |
| 4 | Network interface not found |
| 5 | Operation timed out |
| 6 | Feature not available |
| 7 | Location Services denied (reserved, rarely used—commands degrade gracefully) |

## JSON Output

All commands support JSON output for integration with other tools. JSON is automatically enabled when stdout is not a TTY (e.g., when piping to another command).

### Success Response
```json
{
  "success": true,
  "data": { ... }
}
```

### Error Response
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "suggestion": "How to fix the issue"
  }
}
```

## Location Services & Limited Mode

Some Wi-Fi operations require Location Services permission on macOS. However, **CLI tools and daemons cannot obtain this permission**—they don't appear in System Preferences > Location Services. This is an intentional Apple privacy restriction.

### Graceful Degradation

nactl handles this gracefully by using fallback methods:

| Operation | With Location Services | Without (Limited Mode) |
|-----------|----------------------|------------------------|
| Current SSID | CoreWLAN | `system_profiler` fallback |
| WiFi scan | Full network list | Empty array, `scan_available: false` |
| BSSID | Available | `null` |
| Signal strength (RSSI) | Available | `null` |
| WiFi power on/off | Works | Works |
| IP/gateway/DNS | Works | Works |

### Response Structure in Limited Mode

When Location Services is unavailable, responses include:
```json
{
  "success": true,
  "data": {
    "limited_mode": true,
    "limited_reason": "Location Services not available for CLI tools",
    "scan_available": false,
    ...
  }
}
```

### Checking Permission Status
```bash
# Check current status (informational only)
nactl permissions
```

This reports the current Location Services status for diagnostic purposes. No user action is required or possible—nactl will use fallback methods automatically.

## Code Signing & Notarization

For distribution, the binary should be signed and notarized:

```bash
# Build universal binary first
swift build -c release --arch arm64 --arch x86_64

# Sign for distribution
codesign --sign "Developer ID Application: Your Name" \
         --options runtime \
         .build/apple/Products/Release/nactl

# Create zip for notarization
zip nactl.zip .build/apple/Products/Release/nactl

# Submit for notarization
xcrun notarytool submit nactl.zip --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

## License

Copyright (c) 2026 Sweet Papa Technologies LLC. All rights reserved.
