import Foundation
import SystemConfiguration

/// Wrapper for networksetup CLI and network configuration operations
struct NetworkSetup {
    /// Get the primary Wi-Fi interface name (e.g., "en0")
    static func getWiFiInterfaceName() -> String? {
        let result = ShellExecutor.execute(
            "/usr/sbin/networksetup",
            arguments: ["-listallhardwareports"]
        )

        guard result.succeeded else { return nil }

        let lines = result.output.components(separatedBy: "\n")
        var foundWiFi = false

        for line in lines {
            if line.contains("Wi-Fi") || line.contains("AirPort") {
                foundWiFi = true
            } else if foundWiFi && line.hasPrefix("Device:") {
                let device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                return device
            }
        }

        return nil
    }

    /// Get the network service name for a given interface (e.g., "Wi-Fi" for en0)
    static func getServiceName(for interface: String) -> String? {
        let result = ShellExecutor.execute(
            "/usr/sbin/networksetup",
            arguments: ["-listallhardwareports"]
        )

        guard result.succeeded else { return nil }

        let lines = result.output.components(separatedBy: "\n")
        var currentService: String?

        for line in lines {
            if line.hasPrefix("Hardware Port:") {
                currentService = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:") {
                let device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                if device == interface {
                    return currentService
                }
            }
        }

        return nil
    }

    /// Get all network services
    static func listNetworkServices() -> [String] {
        let result = ShellExecutor.execute(
            "/usr/sbin/networksetup",
            arguments: ["-listallnetworkservices"]
        )

        guard result.succeeded else { return [] }

        return result.output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("*") && !$0.hasPrefix("An asterisk") }
    }

    /// Get network info for a service
    static func getNetworkInfo(service: String) -> [String: String] {
        let result = ShellExecutor.execute(
            "/usr/sbin/networksetup",
            arguments: ["-getinfo", service]
        )

        guard result.succeeded else { return [:] }

        var info: [String: String] = [:]
        for line in result.output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ": ")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts.dropFirst().joined(separator: ": ").trimmingCharacters(in: .whitespaces)
                info[key] = value
            }
        }
        return info
    }

    /// Get DNS servers for a service
    static func getDNSServers(service: String) -> [String] {
        let result = ShellExecutor.execute(
            "/usr/sbin/networksetup",
            arguments: ["-getdnsservers", service]
        )

        guard result.succeeded else { return [] }

        // "There aren't any DNS Servers set on Wi-Fi." means DHCP
        if result.output.contains("There aren't any") {
            return []
        }

        return result.output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }

    /// Set DNS servers for a service (requires sudo)
    static func setDNSServers(service: String, servers: [String]) -> Result<Void, NactlError> {
        var arguments = ["-setdnsservers", service]
        if servers.isEmpty {
            arguments.append("Empty")
        } else {
            arguments.append(contentsOf: servers)
        }

        let result = ShellExecutor.execute(
            "/usr/sbin/networksetup",
            arguments: arguments
        )

        if !result.succeeded {
            if result.errorOutput.contains("requires Authorization") ||
               result.errorOutput.contains("Operation not permitted") {
                return .failure(.permissionDenied("Setting DNS servers requires administrator privileges"))
            }
            return .failure(.commandFailed(result.errorOutput))
        }

        return .success(())
    }

    /// Get the primary active network interface
    static func getPrimaryInterface() -> String? {
        // Use route to find the default gateway interface
        let result = ShellExecutor.shell("route -n get default 2>/dev/null | grep interface | awk '{print $2}'")
        guard result.succeeded && !result.output.isEmpty else { return nil }
        return result.output
    }

    /// Get the MAC address of an interface
    static func getMACAddress(interface: String) -> String? {
        let result = ShellExecutor.execute(
            "/sbin/ifconfig",
            arguments: [interface]
        )

        guard result.succeeded else { return nil }

        // Parse ether line
        for line in result.output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ether ") {
                return trimmed.replacingOccurrences(of: "ether ", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Check if running as root
    static var isRoot: Bool {
        return getuid() == 0
    }

    /// Get the active connection type
    static func getConnectionType() -> String? {
        // Check Wi-Fi first
        let wifiResult = ShellExecutor.execute(
            "/usr/sbin/networksetup",
            arguments: ["-getairportnetwork", getWiFiInterfaceName() ?? "en0"]
        )

        if wifiResult.succeeded && !wifiResult.output.contains("not associated") {
            return "wifi"
        }

        // Check for active Ethernet
        let primaryInterface = getPrimaryInterface()
        if let iface = primaryInterface {
            if iface.hasPrefix("en") && iface != getWiFiInterfaceName() {
                return "ethernet"
            }
            if iface.hasPrefix("utun") || iface.hasPrefix("ppp") {
                return "vpn"
            }
        }

        return nil
    }
}
