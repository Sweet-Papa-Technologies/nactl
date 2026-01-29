import ArgumentParser
import Foundation

/// nactl proxy - Proxy management commands
struct ProxyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "proxy",
        abstract: "Proxy management commands",
        subcommands: [Get.self, Clear.self]
    )

    // MARK: - proxy get
    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get current proxy configuration"
        )

        @OptionGroup var globalOptions: GlobalOptions

        mutating func run() throws {
            // Get the target service
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

            // Get HTTP proxy (web proxy)
            let httpResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-getwebproxy", serviceName]
            )
            let httpProxy = ProxyParser.parseWebProxy(output: httpResult.output)

            // Get HTTPS proxy (secure web proxy)
            let httpsResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-getsecurewebproxy", serviceName]
            )
            let httpsProxy = ProxyParser.parseWebProxy(output: httpsResult.output)

            // Get SOCKS proxy
            let socksResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-getsocksfirewallproxy", serviceName]
            )
            let socksProxy = ProxyParser.parseSOCKSProxy(output: socksResult.output)

            // Get auto proxy URL
            let autoResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-getautoproxyurl", serviceName]
            )
            let (autoEnabled, autoUrl) = ProxyParser.parseAutoProxyUrl(output: autoResult.output)
            let autoConfigUrl = autoEnabled ? autoUrl : nil

            // Get bypass domains
            let bypassResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-getproxybypassdomains", serviceName]
            )
            let bypassList = ProxyParser.parseBypassDomains(output: bypassResult.output)

            let data = ProxyConfigData(
                httpProxy: httpProxy.enabled ? httpProxy : ProxySettings(enabled: false, server: nil, port: nil),
                httpsProxy: httpsProxy.enabled ? httpsProxy : ProxySettings(enabled: false, server: nil, port: nil),
                socksProxy: socksProxy.enabled ? socksProxy : ProxySettings(enabled: false, server: nil, port: nil),
                autoConfigUrl: autoConfigUrl,
                bypassList: bypassList
            )

            if globalOptions.shouldOutputJSON {
                JSONOutput.success(data, pretty: globalOptions.pretty)
            } else {
                printHumanReadable(data, serviceName: serviceName)
            }
        }

        private func printHumanReadable(_ data: ProxyConfigData, serviceName: String) {
            print("Proxy Configuration for \(serviceName)")
            print("")

            // HTTP Proxy
            print("HTTP Proxy:")
            if let http = data.httpProxy, http.enabled {
                print("  Enabled: Yes")
                print("  Server: \(http.server ?? "none")")
                print("  Port: \(http.port.map { String($0) } ?? "none")")
            } else {
                print("  Enabled: No")
            }
            print("")

            // HTTPS Proxy
            print("HTTPS Proxy:")
            if let https = data.httpsProxy, https.enabled {
                print("  Enabled: Yes")
                print("  Server: \(https.server ?? "none")")
                print("  Port: \(https.port.map { String($0) } ?? "none")")
            } else {
                print("  Enabled: No")
            }
            print("")

            // SOCKS Proxy
            print("SOCKS Proxy:")
            if let socks = data.socksProxy, socks.enabled {
                print("  Enabled: Yes")
                print("  Server: \(socks.server ?? "none")")
                print("  Port: \(socks.port.map { String($0) } ?? "none")")
            } else {
                print("  Enabled: No")
            }
            print("")

            // Auto Config URL
            print("Auto Config URL:")
            if let url = data.autoConfigUrl {
                print("  URL: \(url)")
            } else {
                print("  Not configured")
            }
            print("")

            // Bypass List
            print("Bypass Domains:")
            if data.bypassList.isEmpty {
                print("  None")
            } else {
                for domain in data.bypassList {
                    print("  - \(domain)")
                }
            }
        }
    }

    // MARK: - proxy clear
    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear all proxy settings"
        )

        @OptionGroup var globalOptions: GlobalOptions

        mutating func run() throws {
            // Clearing proxy requires sudo
            guard NetworkSetup.isRoot else {
                exitWithError(.permissionDenied("Clearing proxy settings requires administrator privileges"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
            }

            // Get the target service
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

            var errors: [String] = []

            // Disable HTTP proxy
            let httpResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-setwebproxystate", serviceName, "off"]
            )
            if !httpResult.succeeded {
                errors.append("Failed to disable HTTP proxy: \(httpResult.errorOutput)")
            }

            // Disable HTTPS proxy
            let httpsResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-setsecurewebproxystate", serviceName, "off"]
            )
            if !httpsResult.succeeded {
                errors.append("Failed to disable HTTPS proxy: \(httpsResult.errorOutput)")
            }

            // Disable SOCKS proxy
            let socksResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-setsocksfirewallproxystate", serviceName, "off"]
            )
            if !socksResult.succeeded {
                errors.append("Failed to disable SOCKS proxy: \(socksResult.errorOutput)")
            }

            // Disable auto proxy
            let autoResult = ShellExecutor.execute(
                "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", serviceName, "off"]
            )
            if !autoResult.succeeded {
                errors.append("Failed to disable auto proxy: \(autoResult.errorOutput)")
            }

            if !errors.isEmpty {
                // Report partial failure
                if globalOptions.shouldOutputJSON {
                    JSONOutput.successMessage("Proxy settings partially cleared. Some errors: \(errors.joined(separator: "; "))", pretty: globalOptions.pretty)
                } else {
                    print("Proxy settings partially cleared")
                    print("Warnings:")
                    for error in errors {
                        print("  - \(error)")
                    }
                }
            } else {
                if globalOptions.shouldOutputJSON {
                    JSONOutput.successMessage("Proxy settings cleared", pretty: globalOptions.pretty)
                } else {
                    print("Proxy settings cleared for \(serviceName)")
                }
            }
        }
    }
}
