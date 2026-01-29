import ArgumentParser
import Foundation
import CoreWLAN

/// nactl status - Get comprehensive network connection status
struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Get comprehensive network connection status"
    )

    @OptionGroup var globalOptions: GlobalOptions

    mutating func run() throws {
        let status = gatherNetworkStatus()

        if globalOptions.shouldOutputJSON {
            JSONOutput.success(status, pretty: globalOptions.pretty)
        } else {
            printHumanReadable(status)
        }
    }

    private func gatherNetworkStatus() -> NetworkStatusData {
        // Get Wi-Fi interface
        let client = CWWiFiClient.shared()
        let wifiInterface = client.interface()

        // Determine connection type and interface
        let primaryInterface = NetworkSetup.getPrimaryInterface()
        let wifiInterfaceName = NetworkSetup.getWiFiInterfaceName()

        var connected = false
        var connectionType: String?
        var activeInterface: String?
        var ssid: String?
        var bssid: String?
        var signalStrength: Int?
        var signalRssi: Int?
        var channel: Int?
        var frequency: String?
        var linkSpeed: String?

        // Check if Wi-Fi is the primary connection
        if let wifi = wifiInterface, wifi.powerOn() {
            if let currentSSID = wifi.ssid() {
                connected = true
                connectionType = "wifi"
                activeInterface = wifiInterfaceName ?? wifi.interfaceName ?? "en0"
                ssid = currentSSID
                bssid = wifi.bssid()
                signalRssi = wifi.rssiValue()
                // Convert RSSI to percentage (approximate)
                // RSSI typically ranges from -100 (weak) to -30 (strong)
                if let rssi = signalRssi {
                    signalStrength = max(0, min(100, 2 * (rssi + 100)))
                }
                if let wlanChannel = wifi.wlanChannel() {
                    channel = wlanChannel.channelNumber
                    frequency = frequencyBand(for: wlanChannel.channelNumber)
                }
                if let rate = wifi.transmitRate() as Double? {
                    linkSpeed = "\(Int(rate)) Mbps"
                }
            }
        }

        // If not Wi-Fi, check for other connection types
        if !connected, let primary = primaryInterface {
            if primary.hasPrefix("en") {
                connected = true
                connectionType = "ethernet"
                activeInterface = primary
            } else if primary.hasPrefix("utun") || primary.hasPrefix("ppp") {
                connected = true
                connectionType = "vpn"
                activeInterface = primary
            }
        }

        // Get IP configuration from the appropriate service
        var ipAddress: String?
        var subnetMask: String?
        var gateway: String?
        var dnsServers: [String] = []
        var macAddress: String?

        if let iface = activeInterface {
            // Get service name for this interface
            if let serviceName = NetworkSetup.getServiceName(for: iface) {
                let info = NetworkSetup.getNetworkInfo(service: serviceName)
                ipAddress = info["IP address"]
                subnetMask = info["Subnet mask"]
                gateway = info["Router"]
                dnsServers = NetworkSetup.getDNSServers(service: serviceName)

                // If DNS is empty (DHCP), try to get from network info
                if dnsServers.isEmpty {
                    // Use scutil to get DNS from DHCP
                    let dnsResult = ShellExecutor.shell("scutil --dns | grep 'nameserver\\[' | head -4 | awk '{print $3}'")
                    if dnsResult.succeeded {
                        dnsServers = dnsResult.output
                            .components(separatedBy: "\n")
                            .filter { !$0.isEmpty }
                    }
                }
            }

            macAddress = NetworkSetup.getMACAddress(interface: iface)
        }

        return NetworkStatusData(
            connected: connected,
            type: connectionType,
            interface: activeInterface,
            ssid: ssid,
            bssid: bssid,
            signalStrength: signalStrength,
            signalRssi: signalRssi,
            channel: channel,
            frequency: frequency,
            linkSpeed: linkSpeed,
            ipAddress: ipAddress,
            subnetMask: subnetMask,
            gateway: gateway,
            dnsServers: dnsServers,
            macAddress: macAddress
        )
    }

    private func printHumanReadable(_ status: NetworkStatusData) {
        if !status.connected {
            print("Status: Not connected")
            return
        }

        print("Status: Connected")
        if let type = status.type {
            print("Type: \(type)")
        }
        if let iface = status.interface {
            print("Interface: \(iface)")
        }
        if let ssid = status.ssid {
            print("SSID: \(ssid)")
        }
        if let bssid = status.bssid {
            print("BSSID: \(bssid)")
        }
        if let strength = status.signalStrength {
            print("Signal Strength: \(strength)%")
        }
        if let rssi = status.signalRssi {
            print("RSSI: \(rssi) dBm")
        }
        if let channel = status.channel, let freq = status.frequency {
            print("Channel: \(channel) (\(freq))")
        }
        if let speed = status.linkSpeed {
            print("Link Speed: \(speed)")
        }
        if let ip = status.ipAddress {
            print("IP Address: \(ip)")
        }
        if let mask = status.subnetMask {
            print("Subnet Mask: \(mask)")
        }
        if let gw = status.gateway {
            print("Gateway: \(gw)")
        }
        if !status.dnsServers.isEmpty {
            print("DNS Servers: \(status.dnsServers.joined(separator: ", "))")
        }
        if let mac = status.macAddress {
            print("MAC Address: \(mac)")
        }
    }
}
