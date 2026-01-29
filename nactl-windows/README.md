# nactl - Network Admin Control (Windows)

A Rust-based CLI network administration tool for Windows, part of the FoFo Lifeline Network Tools suite.

## Overview

`nactl` provides comprehensive network diagnostics and management capabilities through a unified command-line interface. All commands output JSON for seamless integration with FoFo Lifeline's Node.js backend.

## Commands

| Command | Description | Elevation Required |
|---------|-------------|-------------------|
| `status` | Get comprehensive network connection status | No |
| `ping <host>` | Test connectivity to a host | No |
| `trace <host>` | Trace route to destination | No |
| `dns flush` | Flush DNS resolver cache | No (better with admin) |
| `dns set <primary> [secondary]` | Set custom DNS servers | Yes |
| `dns reset` | Reset DNS to automatic (DHCP) | Yes |
| `stack reset` | Reset network stack | Yes |
| `wifi scan` | Scan for available Wi-Fi networks | No |
| `wifi forget <ssid>` | Remove a saved Wi-Fi network | Yes |
| `proxy get` | Get current proxy configuration | No |
| `proxy clear` | Clear all proxy settings | Yes |

## Installation

### Build from Source

```bash
# Requires Rust toolchain (https://rustup.rs)
cargo build --release

# Binary will be at target/release/nactl.exe
```

### Build for Distribution

```bash
# Release build with optimizations
cargo build --release --target x86_64-pc-windows-msvc
```

## Usage

### Global Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--json` | `-j` | Force JSON output |
| `--pretty` | `-p` | Pretty-print JSON output |
| `--interface` | `-i` | Specify network interface |
| `--help` | `-h` | Show help |
| `--version` | `-v` | Show version |

### Examples

```bash
# Get network status
nactl status

# Ping with custom count and timeout
nactl ping google.com --count 10 --timeout 2000

# Trace route with max hops
nactl trace cloudflare.com --max-hops 20

# Flush DNS cache
nactl dns flush

# Set custom DNS (requires admin)
nactl dns set 1.1.1.1 1.0.0.1

# Reset DNS to DHCP (requires admin)
nactl dns reset

# Reset network stack (soft reset)
nactl stack reset --level soft

# Reset network stack (hard reset, requires reboot)
nactl stack reset --level hard

# Scan for Wi-Fi networks
nactl wifi scan

# Forget a Wi-Fi network (requires admin)
nactl wifi forget "CoffeeShopWifi"

# Get proxy settings
nactl proxy get

# Clear proxy settings
nactl proxy clear
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (needs elevation) |
| 4 | Network interface not found |
| 5 | Operation timed out |
| 6 | Feature not available |

## JSON Output Schema

All commands output JSON with consistent structure:

### Success Response
```json
{
  "success": true,
  "data": { ... },
  "message": "Optional message"
}
```

### Error Response
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "suggestion": "Optional suggestion for resolution"
  }
}
```

## Security Considerations

### Input Validation

All user input is validated to prevent command injection:
- SSIDs: Max 32 characters, no shell metacharacters
- Hostnames: Valid DNS format or IP address
- IP addresses: Valid IPv4/IPv6 format

### Privilege Handling

Operations requiring elevation will return exit code 3 with a helpful message when run without administrator privileges.

## Integration with FoFo Lifeline

Place the compiled binary in:
```
FoFo Lifeline.app/Contents/Resources/bin/nactl.exe
```

Node.js wrapper example:
```javascript
const { execFile } = require('child_process');
const path = require('path');

class NactlWrapper {
    constructor() {
        this.binary = path.join(__dirname, 'bin', 'nactl.exe');
    }

    async execute(args) {
        return new Promise((resolve, reject) => {
            execFile(this.binary, args, { timeout: 30000 }, (error, stdout, stderr) => {
                if (error && error.code) {
                    return reject(this.parseError(error.code, stderr));
                }
                try {
                    resolve(JSON.parse(stdout));
                } catch (e) {
                    reject(new Error(`Invalid JSON: ${stdout}`));
                }
            });
        });
    }

    async getWifiNetworks() {
        return this.execute(['wifi', 'scan']);
    }

    async forgetWifiNetwork(ssid) {
        return this.execute(['wifi', 'forget', ssid]);
    }
}
```

## Development

### Project Structure

```
nactl-windows/
├── Cargo.toml           # Dependencies and build config
├── build.rs             # Build script for Windows manifest
├── nactl.manifest       # Windows application manifest
├── nactl.rc             # Resource file
├── src/
│   ├── main.rs          # CLI entry point
│   ├── lib.rs           # Library exports
│   ├── errors.rs        # Error types and exit codes
│   ├── commands/
│   │   ├── mod.rs
│   │   ├── status.rs    # Network status
│   │   ├── ping.rs      # Ping command
│   │   ├── trace.rs     # Traceroute
│   │   ├── dns.rs       # DNS management
│   │   ├── stack.rs     # Network stack reset
│   │   ├── wifi.rs      # Wi-Fi management
│   │   └── proxy.rs     # Proxy configuration
│   └── utils/
│       ├── mod.rs
│       ├── admin.rs     # Elevation detection
│       ├── netsh.rs     # netsh wrapper
│       ├── registry.rs  # Registry operations
│       ├── powershell.rs# PowerShell execution
│       ├── output.rs    # JSON output
│       └── validation.rs# Input validation
└── README.md
```

### Dependencies

- `clap` - Command-line argument parsing
- `serde` / `serde_json` - JSON serialization
- `windows` - Windows API bindings
- `winreg` - Windows Registry access
- `regex` - Output parsing

### Running Tests

```bash
cargo test
```

## License

MIT License - Sweet Papa Technologies LLC

## Version

1.0.0
