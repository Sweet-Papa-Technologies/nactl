import ArgumentParser
import Foundation

/// nactl stack - Network stack management commands
struct StackCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stack",
        abstract: "Network stack management commands",
        subcommands: [Reset.self]
    )

    // MARK: - stack reset
    struct Reset: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reset",
            abstract: "Reset network stack to fix connectivity issues"
        )

        @Option(name: .customLong("level"), help: "Reset level: soft (default) or hard")
        var level: String = "soft"

        @OptionGroup var globalOptions: GlobalOptions

        mutating func run() throws {
            // Validate level
            guard level == "soft" || level == "hard" else {
                exitWithError(.invalidArguments("Invalid reset level: \(level). Must be 'soft' or 'hard'"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Stack reset requires sudo
            guard NetworkSetup.isRoot else {
                exitWithError(.permissionDenied("Network stack reset requires administrator privileges"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            if level == "soft" {
                performSoftReset()
            } else {
                performHardReset()
            }
        }

        private func performSoftReset() {
            var actionsPerformed: [String] = []
            var errors: [String] = []

            // Get the primary interface
            let wifiInterface = NetworkSetup.getWiFiInterfaceName() ?? "en0"

            // 1. Flush DNS cache
            let dnsResult = ShellExecutor.execute("/usr/bin/dscacheutil", arguments: ["-flushcache"])
            if dnsResult.succeeded {
                actionsPerformed.append("Flushed DNS cache")
            } else {
                errors.append("Failed to flush DNS cache")
            }

            // 2. Restart mDNSResponder
            let mdnsResult = ShellExecutor.execute("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
            if mdnsResult.succeeded {
                actionsPerformed.append("Restarted mDNSResponder")
            } else {
                errors.append("Failed to restart mDNSResponder")
            }

            // 3. Bring interface down
            let downResult = ShellExecutor.execute("/sbin/ifconfig", arguments: [wifiInterface, "down"])
            if downResult.succeeded {
                actionsPerformed.append("Disabled network interface \(wifiInterface)")
            } else {
                errors.append("Failed to disable interface: \(downResult.errorOutput)")
            }

            // 4. Wait a moment
            Thread.sleep(forTimeInterval: 1.0)

            // 5. Bring interface up
            let upResult = ShellExecutor.execute("/sbin/ifconfig", arguments: [wifiInterface, "up"])
            if upResult.succeeded {
                actionsPerformed.append("Re-enabled network interface \(wifiInterface)")
            } else {
                errors.append("Failed to re-enable interface: \(upResult.errorOutput)")
            }

            // Output result
            let data = StackResetData(
                level: "soft",
                actionsPerformed: actionsPerformed,
                rebootRequired: false
            )

            if globalOptions.shouldOutputJSON {
                JSONOutput.success(data, message: "Network stack reset complete", pretty: globalOptions.pretty)
            } else {
                print("Network stack reset complete (soft)")
                print("")
                print("Actions performed:")
                for action in actionsPerformed {
                    print("  - \(action)")
                }
                if !errors.isEmpty {
                    print("")
                    print("Warnings:")
                    for error in errors {
                        print("  - \(error)")
                    }
                }
            }
        }

        private func performHardReset() {
            var actionsPerformed: [String] = []

            // CRITICAL: Warn about data loss
            if !globalOptions.shouldOutputJSON {
                print("WARNING: Hard reset will delete network configuration files.")
                print("VPN configurations and custom network settings will be lost.")
                print("A reboot will be required after this operation.")
                print("")
            }

            // Define the files to remove
            let filesToRemove = [
                "/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist",
                "/Library/Preferences/SystemConfiguration/preferences.plist",
                "/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist"
            ]

            // Remove each file
            for file in filesToRemove {
                let result = ShellExecutor.execute("/bin/rm", arguments: ["-f", file])
                if result.succeeded {
                    actionsPerformed.append("Removed \(file)")
                }
            }

            actionsPerformed.append("Network configuration will regenerate on next boot")

            let data = StackResetData(
                level: "hard",
                actionsPerformed: actionsPerformed,
                rebootRequired: true
            )

            if globalOptions.shouldOutputJSON {
                JSONOutput.success(data, message: "Network stack reset complete - reboot required", pretty: globalOptions.pretty)
            } else {
                print("Network stack reset complete (hard)")
                print("")
                print("Actions performed:")
                for action in actionsPerformed {
                    print("  - \(action)")
                }
                print("")
                print("IMPORTANT: Please reboot your computer to complete the reset.")
            }
        }
    }
}
