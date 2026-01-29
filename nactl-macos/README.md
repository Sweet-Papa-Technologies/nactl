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
Check and manage required permissions (Location Services for Wi-Fi scanning):
```bash
# Check current permission status
nactl permissions
nactl permissions --json

# Check and open System Settings to fix permissions
nactl permissions --fix
```

**Important:** For CLI tools on macOS, Location Services permission is granted to your **terminal app** (Terminal, iTerm, etc.), not to nactl itself. The `permissions` command will tell you which app needs the permission.

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

Wi-Fi scanning requires Location Services permission. **Important:** On macOS, this permission is granted to your **terminal application** (Terminal, iTerm, VS Code, etc.), not to nactl itself.

### Checking Permission Status
```bash
# Check if Location Services is properly configured
nactl permissions

# If permission is missing, open System Settings automatically
nactl permissions --fix
```

### Granting Permission Manually
1. Open **System Settings > Privacy & Security > Location Services**
2. Find your terminal app (e.g., "Terminal", "iTerm", "Visual Studio Code")
3. Enable Location Services for that app
4. Run `nactl wifi scan` again

### Why Location Services?
Apple requires Location Services permission for Wi-Fi scanning because:
- Wi-Fi network information can be used to determine physical location
- This is a privacy protection built into macOS
- Without permission, network names (SSIDs) will appear as `<Hidden>`

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
