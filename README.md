# nactl - Network Admin Control

[![macOS CI](https://github.com/Sweet-Papa-Technologies/nactl/actions/workflows/macos-ci.yml/badge.svg)](https://github.com/Sweet-Papa-Technologies/nactl/actions/workflows/macos-ci.yml)
[![Windows CI](https://github.com/Sweet-Papa-Technologies/nactl/actions/workflows/windows-ci.yml/badge.svg)](https://github.com/Sweet-Papa-Technologies/nactl/actions/workflows/windows-ci.yml)

A cross-platform CLI tool for network administration, designed for FoFo Lifeline.

## Overview

`nactl` provides comprehensive network diagnostics and management through a unified command-line interface. It replaces unreliable OSQuery-based network tools with native implementations that work consistently across platforms.

## Platforms

| Platform | Language | Directory |
|----------|----------|-----------|
| macOS | Swift | [nactl-macos](./nactl-macos/) |
| Windows | Rust | [nactl-windows](./nactl-windows/) |

## Commands

All 11 network administration commands with identical interfaces on both platforms:

| Command | Description | Elevation Required |
|---------|-------------|-------------------|
| `nactl status` | Get network connection status | No |
| `nactl ping <host>` | Test connectivity to a host | No |
| `nactl trace <host>` | Trace route to destination | No |
| `nactl dns flush` | Flush DNS cache | macOS: Yes |
| `nactl dns set <ip> [ip2]` | Set custom DNS servers | Yes |
| `nactl dns reset` | Reset DNS to DHCP | Yes |
| `nactl stack reset` | Reset network stack | Yes |
| `nactl wifi scan` | Scan for Wi-Fi networks | No* |
| `nactl wifi forget <ssid>` | Forget saved network | Yes |
| `nactl proxy get` | Get proxy configuration | No |
| `nactl proxy clear` | Clear proxy settings | Yes |

*macOS requires Location Services permission for Wi-Fi scanning

## Quick Start

### macOS

```bash
cd nactl-macos
swift build -c release
.build/release/nactl status
```

### Windows

```powershell
cd nactl-windows
cargo build --release
.\target\release\nactl.exe status
```

## JSON Output

All commands output JSON for integration with other tools:

```bash
nactl status --json --pretty
```

```json
{
  "success": true,
  "data": {
    "connected": true,
    "type": "wifi",
    "ip_address": "192.168.1.100",
    "gateway": "192.168.1.1",
    ...
  }
}
```

## Testing

Each platform includes a test script that runs safe commands automatically and echoes disruptive commands for manual testing:

```bash
# macOS
./nactl-macos/test_nactl.sh

# Windows (PowerShell)
.\nactl-windows\test_nactl.ps1
```

## Documentation

- [macOS Implementation](./nactl-macos/README.md)
- [Windows Implementation](./nactl-windows/README.md)
- [Requirements & Design Document](./docs/nactl-requirements-design.md)

## CI/CD

GitHub Actions workflows automatically:
- Build debug and release binaries
- Run test suites
- Upload artifacts
- Create releases on tag push

## License

Copyright 2026 Sweet Papa Technologies LLC. All rights reserved.
