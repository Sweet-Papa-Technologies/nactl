import ArgumentParser
import Foundation
import CoreWLAN
import CoreLocation

/// nactl wifi - Wi-Fi management commands
struct WifiCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wifi",
        abstract: "Wi-Fi management commands",
        subcommands: [Scan.self, Forget.self]
    )

    // MARK: - wifi scan
    struct Scan: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "scan",
            abstract: "Scan for available Wi-Fi networks"
        )

        @OptionGroup var globalOptions: GlobalOptions

        mutating func run() throws {
            let startTime = Date()

            // Check Location Services authorization
            let locationManager = CLLocationManager()
            let authStatus = locationManager.authorizationStatus
            if authStatus == .denied || authStatus == .restricted {
                exitWithError(.locationServicesDenied, json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Get Wi-Fi client and interface
            let client = CWWiFiClient.shared()
            guard let interface = client.interface() else {
                exitWithError(.interfaceNotFound("No Wi-Fi interface found"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Check if Wi-Fi is powered on
            guard interface.powerOn() else {
                exitWithError(.notAvailable("Wi-Fi is turned off"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Get list of known networks for the "known" flag
            let knownNetworks = getKnownNetworkSSIDs(interface: interface)

            // Perform scan
            do {
                let networks = try interface.scanForNetworks(withName: nil)
                let scanTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

                // Convert to our data model
                var networkList: [WifiNetworkData] = []

                for network in networks {
                    let ssid = network.ssid ?? "<Hidden>"
                    let bssid = network.bssid ?? "Unknown"
                    let rssi = network.rssiValue
                    let channel = network.wlanChannel?.channelNumber ?? 0
                    let freq = frequencyBand(for: channel)

                    // Determine security type
                    let security = getSecurityString(from: network)

                    // Check if this is a known network
                    let isKnown = knownNetworks.contains(ssid)

                    // Convert RSSI to percentage
                    let signalStrength = max(0, min(100, 2 * (rssi + 100)))

                    networkList.append(WifiNetworkData(
                        ssid: ssid,
                        bssid: bssid,
                        signalStrength: signalStrength,
                        signalRssi: rssi,
                        channel: channel,
                        frequency: freq,
                        security: security,
                        known: isKnown
                    ))
                }

                // Sort by signal strength (strongest first)
                networkList.sort { $0.signalStrength > $1.signalStrength }

                let data = WifiScanData(networks: networkList, scanTimeMs: scanTimeMs)

                if globalOptions.shouldOutputJSON {
                    JSONOutput.success(data, pretty: globalOptions.pretty)
                } else {
                    printHumanReadable(data)
                }

            } catch let error as NSError {
                // Check for specific error codes
                if error.code == -3931 { // kCWErrNotAuthorized or similar
                    exitWithError(.locationServicesDenied, json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
                }
                exitWithError(.commandFailed("Wi-Fi scan failed: \(error.localizedDescription)"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }
        }

        private func getKnownNetworkSSIDs(interface: CWInterface) -> Set<String> {
            var knownSSIDs = Set<String>()

            // Get preferred networks from the interface configuration
            if let config = interface.configuration() {
                let profiles = config.networkProfiles
                for case let profile as CWNetworkProfile in profiles {
                    if let ssid = profile.ssid {
                        knownSSIDs.insert(ssid)
                    }
                }
            }

            return knownSSIDs
        }

        private func getSecurityString(from network: CWNetwork) -> String {
            // Check security bitmask - CWNetwork provides security property
            // This is a simplified approach based on available information

            // supportsSecurity checks for specific security types
            if network.supportsSecurity(.wpa3Personal) || network.supportsSecurity(.wpa3Enterprise) {
                if network.supportsSecurity(.wpa3Enterprise) {
                    return "WPA3-Enterprise"
                }
                return "WPA3-Personal"
            }

            if network.supportsSecurity(.wpa2Personal) || network.supportsSecurity(.wpa2Enterprise) {
                if network.supportsSecurity(.wpa2Enterprise) {
                    return "WPA2-Enterprise"
                }
                return "WPA2-Personal"
            }

            if network.supportsSecurity(.wpaPersonal) || network.supportsSecurity(.wpaEnterprise) {
                if network.supportsSecurity(.wpaEnterprise) {
                    return "WPA-Enterprise"
                }
                return "WPA-Personal"
            }

            if network.supportsSecurity(.dynamicWEP) {
                return "WEP"
            }

            if network.supportsSecurity(.none) {
                return "Open"
            }

            return "Unknown"
        }

        private func printHumanReadable(_ data: WifiScanData) {
            print("Wi-Fi Networks Found: \(data.networks.count)")
            print("Scan time: \(data.scanTimeMs)ms")
            print("")

            // Table header
            print(String(format: "%-32s  %-17s  %6s  %4s  %8s  %-15s  %s",
                "SSID", "BSSID", "Signal", "Ch", "Freq", "Security", "Known"))
            print(String(repeating: "-", count: 100))

            for network in data.networks {
                let ssidDisplay = network.ssid.count > 30 ? String(network.ssid.prefix(30)) + ".." : network.ssid
                let knownDisplay = network.known ? "Yes" : ""

                print(String(format: "%-32s  %-17s  %5d%%  %4d  %8s  %-15s  %s",
                    ssidDisplay,
                    network.bssid,
                    network.signalStrength,
                    network.channel,
                    network.frequency,
                    network.security,
                    knownDisplay
                ))
            }
        }
    }

    // MARK: - wifi forget
    struct Forget: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "forget",
            abstract: "Remove a saved Wi-Fi network profile"
        )

        @Argument(help: "SSID of the network to forget")
        var ssid: String

        @OptionGroup var globalOptions: GlobalOptions

        mutating func run() throws {
            // Validate SSID
            guard ssid.isValidSSID else {
                exitWithError(.invalidArguments("Invalid SSID format"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Forgetting networks requires sudo
            guard NetworkSetup.isRoot else {
                exitWithError(.permissionDenied("Forgetting Wi-Fi networks requires administrator privileges"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Get the Wi-Fi interface name
            guard let wifiInterface = NetworkSetup.getWiFiInterfaceName() else {
                exitWithError(.interfaceNotFound("No Wi-Fi interface found"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Check if currently connected to this network
            let client = CWWiFiClient.shared()
            let interface = client.interface()
            let wasConnected = interface?.ssid() == ssid

            // Remove from preferred networks
            let removeResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-removepreferredwirelessnetwork", wifiInterface, ssid]
            )

            if !removeResult.succeeded {
                // Check if the error is "not in the preferred networks list"
                if removeResult.errorOutput.contains("not in the preferred networks list") ||
                   removeResult.output.contains("not in the preferred networks list") {
                    exitWithError(.generalError("Network '\(ssid)' is not in the preferred networks list"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
                }
                exitWithError(.commandFailed("Failed to remove network: \(removeResult.errorOutput)"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Try to remove from keychain (best effort)
            var keychainCleared = false
            let keychainResult = ShellExecutor.execute(
                "/usr/bin/security",
                arguments: ["delete-generic-password", "-l", ssid, "/Library/Keychains/System.keychain"]
            )
            if keychainResult.succeeded {
                keychainCleared = true
            }

            // Also try user keychain
            let userKeychainResult = ShellExecutor.execute(
                "/usr/bin/security",
                arguments: ["delete-generic-password", "-l", ssid]
            )
            if userKeychainResult.succeeded {
                keychainCleared = true
            }

            let data = WifiForgetData(
                ssid: ssid,
                wasConnected: wasConnected,
                keychainCleared: keychainCleared
            )

            if globalOptions.shouldOutputJSON {
                JSONOutput.success(data, message: "Network '\(ssid)' forgotten", pretty: globalOptions.pretty)
            } else {
                print("Network '\(ssid)' forgotten")
                if wasConnected {
                    print("  Note: You were connected to this network and may have been disconnected")
                }
                if keychainCleared {
                    print("  Keychain credentials cleared")
                }
            }
        }
    }
}
