# nactl - Network Admin Control (macOS)

A native Swift CLI tool for network diagnostics, Wi-Fi management, and network stack operations on macOS.

## Overview

`nactl` is a cross-platform network administration CLI designed for FoFo Lifeline. This is the macOS implementation, built in Swift to leverage the CoreWLAN framework for reliable Wi-Fi scanning and management.

## Requirements

- macOS 12 (Monterey) or later
- Xcode Command Line Tools
- Location Services permission (for Wi-Fi scanning)

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# The binary will be at .build/release/nactl
```

## Installation

```bash
# Copy to a location in your PATH
sudo cp .build/release/nactl /usr/local/bin/
```

## Commands

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
# Scan for networks (requires Location Services permission)
nactl wifi scan
nactl wifi scan --json

# Forget a saved network (requires sudo)
sudo nactl wifi forget "NetworkName"
```

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
| 7 | Location Services denied (Wi-Fi scan) |

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

## Location Services

Wi-Fi scanning requires Location Services permission. On first run, macOS will prompt:
> "nactl would like to use your current location"

Click "Allow" to enable Wi-Fi scanning. If denied, the `wifi scan` command will return exit code 7.

To grant permission after initial denial:
1. Open System Preferences > Security & Privacy > Privacy
2. Select "Location Services" in the sidebar
3. Find "nactl" or your terminal app and enable it

## Code Signing & Notarization

For distribution, the binary should be signed and notarized:

```bash
# Sign for distribution
codesign --sign "Developer ID Application: Your Name" \
         --options runtime \
         .build/release/nactl

# Create zip for notarization
zip nactl.zip .build/release/nactl

# Submit for notarization
xcrun notarytool submit nactl.zip --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

## License

Copyright (c) 2026 Sweet Papa Technologies LLC. All rights reserved.
