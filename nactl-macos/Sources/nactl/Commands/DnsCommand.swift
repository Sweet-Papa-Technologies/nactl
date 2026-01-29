import ArgumentParser
import Foundation

/// nactl dns - DNS management commands
struct DnsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dns",
        abstract: "DNS management commands",
        subcommands: [Flush.self, Set.self, Reset.self]
    )

    // MARK: - dns flush
    struct Flush: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "flush",
            abstract: "Flush DNS resolver cache"
        )

        @OptionGroup var globalOptions: GlobalOptions

        mutating func run() throws {
            // DNS flush on macOS requires sudo
            guard NetworkSetup.isRoot else {
                exitWithError(.permissionDenied("Flushing DNS cache requires administrator privileges"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            var actions: [String] = []
            var errors: [String] = []

            // Flush dscacheutil
            let dscacheResult = ShellExecutor.execute("/usr/bin/dscacheutil", arguments: ["-flushcache"])
            if dscacheResult.succeeded {
                actions.append("Flushed dscacheutil")
            } else {
                errors.append("Failed to flush dscacheutil: \(dscacheResult.errorOutput)")
            }

            // Restart mDNSResponder
            let killallResult = ShellExecutor.execute("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
            if killallResult.succeeded {
                actions.append("Restarted mDNSResponder")
            } else {
                errors.append("Failed to restart mDNSResponder: \(killallResult.errorOutput)")
            }

            if !errors.isEmpty && actions.isEmpty {
                exitWithError(.commandFailed(errors.joined(separator: "; ")), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            if globalOptions.shouldOutputJSON {
                JSONOutput.successMessage("DNS cache flushed successfully", pretty: globalOptions.pretty)
            } else {
                print("DNS cache flushed successfully")
                for action in actions {
                    print("  - \(action)")
                }
            }
        }
    }

    // MARK: - dns set
    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set custom DNS servers"
        )

        @Argument(help: "Primary DNS server")
        var primary: String

        @Argument(help: "Secondary DNS server (optional)")
        var secondary: String?

        @OptionGroup var globalOptions: GlobalOptions

        mutating func run() throws {
            // Validate DNS server addresses
            guard primary.isValidIPAddress else {
                exitWithError(.invalidArguments("Invalid primary DNS server: \(primary)"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            if let sec = secondary, !sec.isValidIPAddress {
                exitWithError(.invalidArguments("Invalid secondary DNS server: \(sec)"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Setting DNS requires sudo
            guard NetworkSetup.isRoot else {
                exitWithError(.permissionDenied("Setting DNS servers requires administrator privileges"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Get the target interface/service
            let serviceName: String
            if let iface = globalOptions.interface {
                if let name = NetworkSetup.getServiceName(for: iface) {
                    serviceName = name
                } else {
                    // Try using the interface name directly as service name
                    serviceName = iface
                }
            } else {
                // Default to Wi-Fi service
                serviceName = "Wi-Fi"
            }

            // Build DNS servers list
            var servers = [primary]
            if let sec = secondary {
                servers.append(sec)
            }

            // Set DNS servers
            let result = NetworkSetup.setDNSServers(service: serviceName, servers: servers)

            switch result {
            case .success:
                let data = DnsSetData(
                    interface: serviceName,
                    primary: primary,
                    secondary: secondary
                )
                if globalOptions.shouldOutputJSON {
                    JSONOutput.success(data, message: "DNS servers updated", pretty: globalOptions.pretty)
                } else {
                    print("DNS servers updated for \(serviceName)")
                    print("  Primary: \(primary)")
                    if let sec = secondary {
                        print("  Secondary: \(sec)")
                    }
                }
            case .failure(let error):
                exitWithError(error, json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }
        }
    }

    // MARK: - dns reset
    struct Reset: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reset",
            abstract: "Reset DNS to automatic (DHCP)"
        )

        @OptionGroup var globalOptions: GlobalOptions

        mutating func run() throws {
            // Resetting DNS requires sudo
            guard NetworkSetup.isRoot else {
                exitWithError(.permissionDenied("Resetting DNS servers requires administrator privileges"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Get the target interface/service
            let serviceName: String
            if let iface = globalOptions.interface {
                if let name = NetworkSetup.getServiceName(for: iface) {
                    serviceName = name
                } else {
                    serviceName = iface
                }
            } else {
                serviceName = "Wi-Fi"
            }

            // Set DNS to empty (DHCP)
            let result = NetworkSetup.setDNSServers(service: serviceName, servers: [])

            switch result {
            case .success:
                if globalOptions.shouldOutputJSON {
                    JSONOutput.successMessage("DNS reset to automatic (DHCP)", pretty: globalOptions.pretty)
                } else {
                    print("DNS reset to automatic (DHCP) for \(serviceName)")
                }
            case .failure(let error):
                exitWithError(error, json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }
        }
    }
}
