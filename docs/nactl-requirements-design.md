# nactl - Network Admin Control
## Requirements & Design Document

**Version:** 1.0  
**Date:** January 28, 2026  
**Project:** FoFo Lifeline Network Tools Migration  
**Author:** Sweet Papa Technologies LLC

---

## 1. Executive Summary

This document specifies the requirements and design for `nactl`, a cross-platform CLI utility that consolidates all network administration functionality for FoFo Lifeline. Similar to the successful `startctl` implementation for startup item management, `nactl` will provide a reliable, native interface for network diagnostics, Wi-Fi management, and network stack operations.

### 1.1 Problem Statement

The current FoFo Lifeline network tools suffer from several critical issues:

| Tool | Platform | Issue |
|------|----------|-------|
| `getWifiNetworks` | Both | OSQuery `wifi_networks` table unreliable; returns empty on both platforms |
| `forgetWifiNetwork` | Windows | Fails to delete Wi-Fi profiles |
| `resetNetworkStack` | macOS | Tool works but causes temporary disconnection, UI interprets as error |

### 1.2 Solution Overview

Build two native CLI applications with identical command interfaces:
- **Windows:** Rust-based executable (following `startctl` patterns)
- **macOS:** Swift-based executable (using CoreWLAN framework)

Both will output JSON for seamless integration with FoFo Lifeline's Node.js backend.

---

## 2. Platform Architecture

### 2.1 Why Different Languages?

| Platform | Language | Rationale |
|----------|----------|-----------|
| **Windows** | Rust | Matches `startctl` patterns; excellent FFI with Windows APIs; static compilation eliminates DLL hell |
| **macOS** | Swift | **Required** for CoreWLAN framework access; Apple deprecated all CLI alternatives (airport removed in macOS 14.4); Swift is the only reliable path for Wi-Fi scanning |

### 2.2 The macOS "Sonoma Crisis"

As of macOS Sonoma 14.4, Apple deprecated the `airport` utility that was the industry standard for CLI Wi-Fi management. The replacement (`wdutil`) has severe limitations:
- Requires sudo for basic info
- Outputs redacted data (SSID/BSSID hidden)
- No scan functionality in non-privileged mode

**The Only Solution:** A compiled Swift binary using CoreWLAN framework, which properly integrates with macOS's Location Services permission model. When first run, macOS prompts: "nactl would like to use your current location" - upon approval, full SSID/BSSID data is accessible.

---

## 3. Functional Requirements

### 3.1 Complete Command Matrix

`nactl` must support all 11 network-related tools from FoFo Lifeline:

| # | Command | FoFo Tool | Tier | Elevation Required |
|---|---------|-----------|------|-------------------|
| 1 | `status` | getNetworkStatus | Free | No |
| 2 | `ping` | pingHost | Free | No |
| 3 | `trace` | traceroute | Paid | No |
| 4 | `dns flush` | flushDns | Free | macOS: Yes |
| 5 | `dns set` | setDnsServers | Paid | Yes |
| 6 | `dns reset` | resetDnsToDefault | Free | Yes |
| 7 | `stack reset` | resetNetworkStack | Paid | Yes |
| 8 | `wifi scan` | getWifiNetworks | Free | No* |
| 9 | `wifi forget` | forgetWifiNetwork | Paid | Yes |
| 10 | `proxy get` | checkProxySettings | Free | No |
| 11 | `proxy clear` | clearProxySettings | Paid | Yes |

*macOS requires Location Services permission for Wi-Fi scanning

### 3.2 Command Specifications

#### 3.2.1 `nactl status`
**Purpose:** Get comprehensive network connection status  
**Elevation:** None  
**Output Schema:**
```json
{
  "success": true,
  "data": {
    "connected": true,
    "type": "wifi|ethernet|cellular",
    "interface": "en0|Wi-Fi|Ethernet",
    "ssid": "NetworkName",
    "bssid": "AA:BB:CC:DD:EE:FF",
    "signal_strength": 85,
    "signal_rssi": -55,
    "channel": 36,
    "frequency": "5GHz",
    "link_speed": "866 Mbps",
    "ip_address": "192.168.1.100",
    "subnet_mask": "255.255.255.0",
    "gateway": "192.168.1.1",
    "dns_servers": ["8.8.8.8", "8.8.4.4"],
    "mac_address": "AA:BB:CC:DD:EE:FF"
  }
}
```

**Windows Implementation:**
```
netsh wlan show interfaces
ipconfig /all
```

**macOS Implementation:**
```swift
CWWiFiClient.shared().interface()  // For Wi-Fi details
networksetup -getinfo "Wi-Fi"       // For IP configuration
```

---

#### 3.2.2 `nactl ping <host> [--count N] [--timeout MS]`
**Purpose:** Test connectivity to a host  
**Elevation:** None  
**Default:** 4 packets, 1000ms timeout  
**Output Schema:**
```json
{
  "success": true,
  "data": {
    "host": "google.com",
    "resolved_ip": "142.250.80.46",
    "packets_sent": 4,
    "packets_received": 4,
    "packet_loss_percent": 0,
    "min_ms": 12.5,
    "avg_ms": 15.2,
    "max_ms": 18.1,
    "results": [
      {"seq": 1, "ttl": 117, "time_ms": 12.5},
      {"seq": 2, "ttl": 117, "time_ms": 14.2},
      {"seq": 3, "ttl": 117, "time_ms": 15.8},
      {"seq": 4, "ttl": 117, "time_ms": 18.1}
    ]
  }
}
```

**Implementation:** Native system `ping` command with output parsing

---

#### 3.2.3 `nactl trace <host> [--max-hops N]`
**Purpose:** Trace route to destination  
**Elevation:** None  
**Default:** 30 max hops  
**Output Schema:**
```json
{
  "success": true,
  "data": {
    "host": "google.com",
    "hops": [
      {"hop": 1, "ip": "192.168.1.1", "hostname": "router.local", "time_ms": [1.2, 1.1, 1.3]},
      {"hop": 2, "ip": "10.0.0.1", "hostname": null, "time_ms": [8.5, 9.2, 8.8]},
      {"hop": 3, "ip": "*", "hostname": null, "time_ms": null}
    ],
    "destination_reached": true,
    "total_hops": 12
  }
}
```

**Windows:** `tracert`  
**macOS:** `traceroute`

---

#### 3.2.4 `nactl dns flush`
**Purpose:** Flush DNS resolver cache  
**Elevation:** macOS: Yes, Windows: No (but runs better elevated)  
**Output Schema:**
```json
{
  "success": true,
  "message": "DNS cache flushed successfully"
}
```

**Windows Implementation:**
```batch
ipconfig /flushdns
```

**macOS Implementation:**
```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

---

#### 3.2.5 `nactl dns set <primary> [secondary]`
**Purpose:** Set custom DNS servers  
**Elevation:** Yes  
**Output Schema:**
```json
{
  "success": true,
  "message": "DNS servers updated",
  "data": {
    "interface": "Wi-Fi",
    "primary": "1.1.1.1",
    "secondary": "1.0.0.1"
  }
}
```

**Windows Implementation:**
```batch
netsh interface ip set dns "Wi-Fi" static 1.1.1.1
netsh interface ip add dns "Wi-Fi" 1.0.0.1 index=2
```

**macOS Implementation:**
```bash
networksetup -setdnsservers "Wi-Fi" 1.1.1.1 1.0.0.1
```

---

#### 3.2.6 `nactl dns reset`
**Purpose:** Reset DNS to automatic (DHCP)  
**Elevation:** Yes  
**Output Schema:**
```json
{
  "success": true,
  "message": "DNS reset to automatic (DHCP)"
}
```

**Windows Implementation:**
```batch
netsh interface ip set dns "Wi-Fi" dhcp
```

**macOS Implementation:**
```bash
networksetup -setdnsservers "Wi-Fi" Empty
```

---

#### 3.2.7 `nactl stack reset [--level soft|hard]`
**Purpose:** Reset network stack to fix connectivity issues  
**Elevation:** Yes  
**Levels:**
- `soft` (default): Flush caches, restart adapter
- `hard`: Full TCP/IP and Winsock reset (requires reboot)

**Output Schema:**
```json
{
  "success": true,
  "message": "Network stack reset complete",
  "data": {
    "level": "soft",
    "actions_performed": [
      "Flushed DNS cache",
      "Released IP address",
      "Renewed IP address",
      "Restarted network adapter"
    ],
    "reboot_required": false
  }
}
```

**Windows Soft Reset:**
```batch
ipconfig /flushdns
ipconfig /release
ipconfig /renew
Restart-NetAdapter -Name "Wi-Fi"
```

**Windows Hard Reset:**
```batch
netsh winsock reset
netsh int ip reset c:\resetlog.txt
:: Reboot required
```

**macOS Soft Reset:**
```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
sudo ifconfig en0 down
sleep 1
sudo ifconfig en0 up
```

**macOS Hard Reset:**
```bash
sudo rm /Library/Preferences/SystemConfiguration/NetworkInterfaces.plist
sudo rm /Library/Preferences/SystemConfiguration/preferences.plist
sudo rm /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist
# Reboot required - files regenerate on boot
```

**CRITICAL:** For hard reset, the tool must:
1. Warn user that VPN configs and custom settings will be lost
2. Return `reboot_required: true` so UI can handle gracefully
3. NOT automatically reboot - leave that to calling code

---

#### 3.2.8 `nactl wifi scan [--json]`
**Purpose:** Scan for available Wi-Fi networks  
**Elevation:** No (but macOS requires Location Services permission)  
**Output Schema:**
```json
{
  "success": true,
  "data": {
    "networks": [
      {
        "ssid": "HomeNetwork",
        "bssid": "AA:BB:CC:DD:EE:FF",
        "signal_strength": 92,
        "signal_rssi": -45,
        "channel": 6,
        "frequency": "2.4GHz",
        "security": "WPA2-Personal",
        "known": true
      },
      {
        "ssid": "Neighbor5G",
        "bssid": "11:22:33:44:55:66",
        "signal_strength": 65,
        "signal_rssi": -68,
        "channel": 149,
        "frequency": "5GHz",
        "security": "WPA3-SAE",
        "known": false
      }
    ],
    "scan_time_ms": 3500
  }
}
```

**Windows Implementation:**
```batch
netsh wlan show networks mode=bssid
```
Parse the multi-line output. **Note:** Scan takes 3-5 seconds as radio dwells on each channel.

**macOS Implementation (Swift - CRITICAL):**
```swift
import CoreWLAN

let client = CWWiFiClient.shared()
guard let interface = client.interface() else {
    // Error: No Wi-Fi interface
}

do {
    let networks = try interface.scanForNetworks(withName: nil)
    for network in networks {
        // Output: ssid, bssid, rssiValue, wlanChannel, etc.
    }
} catch {
    // Handle scan error
}
```

**IMPORTANT macOS Notes:**
1. First run triggers Location Services prompt
2. If denied, scan returns empty - include helpful error message
3. Binary must be signed/notarized for Gatekeeper

---

#### 3.2.9 `nactl wifi forget <ssid>`
**Purpose:** Remove a saved Wi-Fi network profile  
**Elevation:** Yes  
**Output Schema:**
```json
{
  "success": true,
  "message": "Network 'CoffeeShopWifi' forgotten",
  "data": {
    "ssid": "CoffeeShopWifi",
    "was_connected": false,
    "keychain_cleared": true
  }
}
```

**Windows Implementation:**
```batch
netsh wlan delete profile name="CoffeeShopWifi"
```

**macOS Implementation:**
```bash
# Get Wi-Fi interface name first
WIFI_IF=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')

# Remove from preferred networks
networksetup -removepreferredwirelessnetwork $WIFI_IF "CoffeeShopWifi"

# Also clear from Keychain (optional but thorough)
security delete-generic-password -l "CoffeeShopWifi" /Library/Keychains/System.keychain 2>/dev/null
```

---

#### 3.2.10 `nactl proxy get`
**Purpose:** Get current proxy configuration  
**Elevation:** No  
**Output Schema:**
```json
{
  "success": true,
  "data": {
    "http_proxy": {
      "enabled": true,
      "server": "proxy.company.com",
      "port": 8080
    },
    "https_proxy": {
      "enabled": true,
      "server": "proxy.company.com",
      "port": 8080
    },
    "socks_proxy": {
      "enabled": false,
      "server": null,
      "port": null
    },
    "auto_config_url": null,
    "bypass_list": ["localhost", "127.0.0.1", "*.local"]
  }
}
```

**Windows Implementation:**
```batch
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer
netsh winhttp show proxy
```

**macOS Implementation:**
```bash
networksetup -getwebproxy "Wi-Fi"
networksetup -getsecurewebproxy "Wi-Fi"
networksetup -getsocksfirewallproxy "Wi-Fi"
networksetup -getautoproxyurl "Wi-Fi"
networksetup -getproxybypassdomains "Wi-Fi"
```

---

#### 3.2.11 `nactl proxy clear`
**Purpose:** Clear all proxy settings  
**Elevation:** Yes  
**Output Schema:**
```json
{
  "success": true,
  "message": "Proxy settings cleared"
}
```

**Windows Implementation:**
```batch
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f
netsh winhttp reset proxy
```

**macOS Implementation:**
```bash
networksetup -setwebproxystate "Wi-Fi" off
networksetup -setsecurewebproxystate "Wi-Fi" off
networksetup -setsocksfirewallproxystate "Wi-Fi" off
networksetup -setautoproxystate "Wi-Fi" off
```

---

## 4. CLI Interface Design

### 4.1 General Patterns

```
nactl <command> [subcommand] [arguments] [--flags]
```

### 4.2 Global Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--json` | `-j` | Force JSON output (default when stdout is not a TTY) |
| `--pretty` | `-p` | Pretty-print JSON output |
| `--help` | `-h` | Show help for command |
| `--version` | `-v` | Show version information |
| `--interface` | `-i` | Specify network interface (e.g., `en0`, `Wi-Fi`) |

### 4.3 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied (needs elevation) |
| 4 | Network interface not found |
| 5 | Operation timed out |
| 6 | Feature not available on this platform |
| 7 | Location Services denied (macOS Wi-Fi scan) |

### 4.4 Error Output Schema

```json
{
  "success": false,
  "error": {
    "code": "PERMISSION_DENIED",
    "message": "This operation requires administrator privileges",
    "suggestion": "Run with elevated permissions or use sudo"
  }
}
```

---

## 5. Technical Implementation

### 5.1 Windows (Rust)

#### 5.1.1 Repository Structure
Clone pattern from `startctl`: `git@github.com:Sweet-Papa-Technologies/startctl.git`

```
nactl-windows/
├── Cargo.toml
├── build.rs
├── src/
│   ├── main.rs
│   ├── lib.rs
│   ├── commands/
│   │   ├── mod.rs
│   │   ├── status.rs
│   │   ├── ping.rs
│   │   ├── trace.rs
│   │   ├── dns.rs
│   │   ├── stack.rs
│   │   ├── wifi.rs
│   │   └── proxy.rs
│   ├── utils/
│   │   ├── mod.rs
│   │   ├── netsh.rs       // netsh command wrapper
│   │   ├── registry.rs    // Registry operations
│   │   ├── powershell.rs  // PowerShell execution
│   │   └── output.rs      // JSON serialization
│   └── errors.rs
├── tests/
└── README.md
```

#### 5.1.2 Key Dependencies (Cargo.toml)
```toml
[package]
name = "nactl"
version = "1.0.0"
edition = "2021"

[dependencies]
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
windows = { version = "0.52", features = [
    "Win32_NetworkManagement_WiFi",
    "Win32_NetworkManagement_IpHelper",
    "Win32_System_Registry",
    "Win32_Foundation"
]}
winreg = "0.52"
regex = "1"

[profile.release]
opt-level = "z"
lto = true
strip = true
```

#### 5.1.3 Build Settings
- Target: `x86_64-pc-windows-msvc`
- Static linking for VC++ runtime
- Include manifest for admin elevation detection
- Code signing with company certificate

#### 5.1.4 Windows API Usage

For Wi-Fi scanning, use the Native WiFi API directly instead of parsing netsh output:

```rust
use windows::Win32::NetworkManagement::WiFi::*;

// WlanOpenHandle, WlanEnumInterfaces, WlanGetAvailableNetworkList
// This provides structured data without text parsing
```

However, for simplicity and consistency with existing patterns, netsh parsing is acceptable for V1.

---

### 5.2 macOS (Swift)

#### 5.2.1 Project Structure
```
nactl-macos/
├── Package.swift
├── Sources/
│   └── nactl/
│       ├── main.swift
│       ├── Commands/
│       │   ├── StatusCommand.swift
│       │   ├── PingCommand.swift
│       │   ├── TraceCommand.swift
│       │   ├── DnsCommand.swift
│       │   ├── StackCommand.swift
│       │   ├── WifiCommand.swift
│       │   └── ProxyCommand.swift
│       ├── Utils/
│       │   ├── NetworkSetup.swift    // networksetup wrapper
│       │   ├── ShellExecutor.swift   // Shell command execution
│       │   └── JSONOutput.swift
│       └── Models/
│           ├── NetworkStatus.swift
│           ├── WifiNetwork.swift
│           └── ProxyConfig.swift
├── Tests/
└── README.md
```

#### 5.2.2 Package.swift
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nactl",
    platforms: [.macOS(.v12)],  // Minimum macOS 12 for stable CoreWLAN
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "nactl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
)
```

#### 5.2.3 CoreWLAN Wi-Fi Scanning (Critical Code)

```swift
import CoreWLAN
import CoreLocation

class WifiScanner {
    private let locationManager = CLLocationManager()
    
    func scan() -> Result<[WifiNetwork], NactlError> {
        // Check Location Services authorization
        let authStatus = locationManager.authorizationStatus
        if authStatus == .denied || authStatus == .restricted {
            return .failure(.locationServicesDenied)
        }
        
        guard let client = CWWiFiClient.shared(),
              let interface = client.interface() else {
            return .failure(.noWifiInterface)
        }
        
        do {
            let networks = try interface.scanForNetworks(withName: nil)
            let results = networks.map { network -> WifiNetwork in
                WifiNetwork(
                    ssid: network.ssid ?? "<Hidden>",
                    bssid: network.bssid ?? "Unknown",
                    rssi: network.rssiValue,
                    channel: network.wlanChannel?.channelNumber ?? 0,
                    security: securityString(from: network)
                )
            }
            return .success(results)
        } catch {
            return .failure(.scanFailed(error.localizedDescription))
        }
    }
    
    private func securityString(from network: CWNetwork) -> String {
        // Map security mode to human-readable string
        // WPA2, WPA3, WEP, Open, etc.
    }
}
```

#### 5.2.4 Entitlements (nactl.entitlements)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.device.wifi-info</key>
    <true/>
</dict>
</plist>
```

#### 5.2.5 Build & Distribution
```bash
# Build release binary
swift build -c release

# Sign for distribution
codesign --sign "Developer ID Application: Sweet Papa Technologies" \
         --options runtime \
         --entitlements nactl.entitlements \
         .build/release/nactl

# Notarize for Gatekeeper
xcrun notarytool submit nactl.zip --apple-id ... --team-id ...
```

---

## 6. Integration with FoFo Lifeline

### 6.1 Binary Location
```
FoFo Lifeline.app/
├── Contents/
│   └── Resources/
│       └── bin/
│           ├── nactl           (macOS)
│           └── nactl.exe       (Windows - in Windows build)
```

### 6.2 Calling Pattern (Node.js Backend)

```javascript
const { execFile } = require('child_process');
const path = require('path');

class NactlWrapper {
    constructor() {
        this.binary = process.platform === 'darwin' 
            ? path.join(__dirname, 'bin', 'nactl')
            : path.join(__dirname, 'bin', 'nactl.exe');
    }

    async execute(args) {
        return new Promise((resolve, reject) => {
            execFile(this.binary, args, { timeout: 30000 }, (error, stdout, stderr) => {
                if (error && error.code) {
                    // Handle specific exit codes
                    return reject(this.parseError(error.code, stderr));
                }
                try {
                    resolve(JSON.parse(stdout));
                } catch (e) {
                    reject(new Error(`Invalid JSON output: ${stdout}`));
                }
            });
        });
    }

    async getWifiNetworks() {
        return this.execute(['wifi', 'scan', '--json']);
    }

    async forgetWifiNetwork(ssid) {
        return this.execute(['wifi', 'forget', ssid, '--json']);
    }

    async resetNetworkStack(level = 'soft') {
        return this.execute(['stack', 'reset', '--level', level, '--json']);
    }
}
```

### 6.3 Tool Migration Mapping

| Current FoFo Tool | nactl Command | Notes |
|-------------------|---------------|-------|
| `getNetworkStatus` | `nactl status` | Direct replacement |
| `pingHost` | `nactl ping <host>` | Add structured output |
| `traceroute` | `nactl trace <host>` | Add structured output |
| `flushDns` | `nactl dns flush` | Works on both platforms |
| `setDnsServers` | `nactl dns set <ip> [ip2]` | New structured approach |
| `resetDnsToDefault` | `nactl dns reset` | Cleaner implementation |
| `resetNetworkStack` | `nactl stack reset` | **FIXES macOS issue** |
| `getWifiNetworks` | `nactl wifi scan` | **FIXES both platforms** |
| `forgetWifiNetwork` | `nactl wifi forget <ssid>` | **FIXES Windows issue** |
| `checkProxySettings` | `nactl proxy get` | Enhanced output |
| `clearProxySettings` | `nactl proxy clear` | Direct replacement |

---

## 7. Testing Requirements

### 7.1 Test Matrix

| Test Case | Windows | macOS |
|-----------|---------|-------|
| `status` returns valid JSON | ☐ | ☐ |
| `status` includes IP, gateway, DNS | ☐ | ☐ |
| `ping` returns timing data | ☐ | ☐ |
| `ping` handles unreachable host | ☐ | ☐ |
| `trace` completes within timeout | ☐ | ☐ |
| `dns flush` succeeds | ☐ | ☐ |
| `dns set` changes DNS servers | ☐ | ☐ |
| `dns reset` restores DHCP | ☐ | ☐ |
| `wifi scan` returns networks | ☐ | ☐ |
| `wifi scan` includes RSSI | ☐ | ☐ |
| `wifi forget` removes profile | ☐ | ☐ |
| `stack reset --level soft` works | ☐ | ☐ |
| `stack reset --level hard` reports reboot_required | ☐ | ☐ |
| `proxy get` shows current config | ☐ | ☐ |
| `proxy clear` disables proxy | ☐ | ☐ |
| Exit code 3 when elevation needed | ☐ | ☐ |
| Exit code 7 on Location denied (macOS) | N/A | ☐ |

### 7.2 Edge Cases to Test

1. **No Wi-Fi interface present** (Ethernet-only machine)
2. **Wi-Fi disabled** (airplane mode)
3. **No networks in range** (Faraday cage scenario)
4. **Hidden SSID networks**
5. **Unicode SSIDs** (emoji, CJK characters)
6. **Very long SSIDs** (32 characters max per spec)
7. **Multiple network interfaces** (Wi-Fi + Ethernet + VPN)
8. **Rapid sequential scans** (debounce handling)
9. **Timeout scenarios** (slow network responses)
10. **Concurrent execution** (multiple nactl instances)

---

## 8. Security Considerations

### 8.1 Privilege Handling

| Operation | Windows | macOS |
|-----------|---------|-------|
| Read-only operations | User | User |
| DNS modification | Admin | root (sudo) |
| Network reset | Admin | root (sudo) |
| Wi-Fi profile deletion | Admin | root (sudo) |

### 8.2 Input Validation

**CRITICAL:** All user input must be validated to prevent command injection.

```rust
// WRONG - Direct string interpolation
let cmd = format!("netsh wlan delete profile name=\"{}\"", ssid);

// RIGHT - Validate and escape
fn validate_ssid(ssid: &str) -> Result<&str, Error> {
    if ssid.len() > 32 {
        return Err(Error::InvalidSSID("SSID too long"));
    }
    if ssid.contains(&['\"', '\'', '\\', '\n', '\r', '\0'][..]) {
        return Err(Error::InvalidSSID("SSID contains invalid characters"));
    }
    Ok(ssid)
}
```

### 8.3 Data Privacy

- Never log full Wi-Fi passwords
- Sanitize BSSIDs in logs (can be used for geolocation)
- Don't store scan results persistently
- Respect system keychain security

---

## 9. Offline Mode Compatibility

`nactl` is designed to work in FoFo Lifeline's offline mode. The following commands work without internet:

| Command | Works Offline | Notes |
|---------|---------------|-------|
| `status` | ✅ | Shows local interface state |
| `ping` | ⚠️ | Only for local network targets |
| `trace` | ⚠️ | Only for local network targets |
| `dns flush` | ✅ | Local cache operation |
| `dns set/reset` | ✅ | Local config change |
| `wifi scan` | ✅ | Radio-based, no internet needed |
| `wifi forget` | ✅ | Local profile management |
| `stack reset` | ✅ | Local stack operation |
| `proxy get/clear` | ✅ | Local config |

This is critical because network tools are often needed precisely when internet is broken.

---

## 10. Deliverables Checklist

### 10.1 Windows (Rust)

- [ ] Cargo project with documented dependencies
- [ ] All 11 commands implemented
- [ ] JSON output for all commands
- [ ] Exit codes per spec
- [ ] Admin elevation detection
- [ ] Unit tests for parsing logic
- [ ] Integration tests for each command
- [ ] Release build with static linking
- [ ] Code signed executable
- [ ] README with build instructions

### 10.2 macOS (Swift)

- [ ] Swift Package Manager project
- [ ] All 11 commands implemented
- [ ] CoreWLAN integration for Wi-Fi scanning
- [ ] Location Services permission handling
- [ ] JSON output for all commands
- [ ] Exit codes per spec
- [ ] Root privilege detection
- [ ] Unit tests
- [ ] Integration tests
- [ ] Signed and notarized binary
- [ ] README with build instructions

### 10.3 Integration

- [ ] Node.js wrapper class
- [ ] Updated FoFo tool implementations
- [ ] Documentation for tool migration
- [ ] Test coverage for all 11 tools on both platforms

---

## 11. Timeline Estimate

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| **Phase 1:** Windows Rust Implementation | 3-4 days | Working nactl.exe |
| **Phase 2:** macOS Swift Implementation | 3-4 days | Working nactl binary |
| **Phase 3:** Testing & Bug Fixes | 2-3 days | Validated on real hardware |
| **Phase 4:** FoFo Integration | 1-2 days | Migrated tool implementations |
| **Total** | **9-13 days** | Complete nactl solution |

---

## 12. References

### 12.1 Windows
- [netsh wlan commands](https://learn.microsoft.com/en-us/windows-server/networking/technologies/netsh/netsh-wlan)
- [Native WiFi API](https://learn.microsoft.com/en-us/windows/win32/nativewifi/portal)
- [TCP/IP Stack Reset](https://learn.microsoft.com/en-us/troubleshoot/windows-client/networking/reset-tcp-ip-stack)

### 12.2 macOS
- [CoreWLAN Framework](https://developer.apple.com/documentation/corewlan)
- [networksetup man page](https://www.unix.com/man-page/osx/8/networksetup/)
- [macOS Network Configuration](https://support.apple.com/guide/mac-help/use-wlan-diagnostics-on-mac-mchl81ac7ef9/mac)

### 12.3 FoFo Internal
- `startctl` repository: `git@github.com:Sweet-Papa-Technologies/startctl.git`
- CLI WiFi Management Research document
- FoFo Lifeline Tool Testing Tracker

---

**Document Version:** 1.0  
**Last Updated:** January 28, 2026  
**Approved By:** [Pending Review]
