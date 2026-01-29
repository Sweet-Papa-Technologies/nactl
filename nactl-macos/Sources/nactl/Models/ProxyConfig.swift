import Foundation

/// Proxy configuration data model
struct ProxyConfigData: Encodable {
    let httpProxy: ProxySettings?
    let httpsProxy: ProxySettings?
    let socksProxy: ProxySettings?
    let autoConfigUrl: String?
    let bypassList: [String]

    enum CodingKeys: String, CodingKey {
        case httpProxy = "http_proxy"
        case httpsProxy = "https_proxy"
        case socksProxy = "socks_proxy"
        case autoConfigUrl = "auto_config_url"
        case bypassList = "bypass_list"
    }
}

/// Individual proxy settings
struct ProxySettings: Encodable {
    let enabled: Bool
    let server: String?
    let port: Int?
}

/// Parser for networksetup proxy output
struct ProxyParser {
    /// Parse web proxy output from networksetup
    static func parseWebProxy(output: String) -> ProxySettings {
        var enabled = false
        var server: String?
        var port: Int?

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Enabled:") {
                enabled = trimmed.contains("Yes")
            } else if trimmed.hasPrefix("Server:") {
                let value = trimmed.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
                server = value.isEmpty ? nil : value
            } else if trimmed.hasPrefix("Port:") {
                let value = trimmed.replacingOccurrences(of: "Port:", with: "").trimmingCharacters(in: .whitespaces)
                port = Int(value)
            }
        }

        return ProxySettings(enabled: enabled, server: server, port: port)
    }

    /// Parse SOCKS proxy output from networksetup
    static func parseSOCKSProxy(output: String) -> ProxySettings {
        // Same format as web proxy
        return parseWebProxy(output: output)
    }

    /// Parse auto proxy URL output from networksetup
    static func parseAutoProxyUrl(output: String) -> (enabled: Bool, url: String?) {
        var enabled = false
        var url: String?

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Enabled:") {
                enabled = trimmed.contains("Yes")
            } else if trimmed.hasPrefix("URL:") {
                let value = trimmed.replacingOccurrences(of: "URL:", with: "").trimmingCharacters(in: .whitespaces)
                url = value.isEmpty || value == "(null)" ? nil : value
            }
        }

        return (enabled, url)
    }

    /// Parse bypass domains output from networksetup
    static func parseBypassDomains(output: String) -> [String] {
        // Output is one domain per line, or "There aren't any bypass domains set..."
        if output.contains("There aren't any") {
            return []
        }

        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
