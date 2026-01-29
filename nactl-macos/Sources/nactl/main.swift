import ArgumentParser
import Foundation

/// nactl - Network Admin Control CLI for macOS
/// A native CLI tool for network diagnostics, Wi-Fi management, and network stack operations.
let APP_VERSION = "1.0.0"

@main
struct Nactl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nactl",
        abstract: "Network administration CLI tool for macOS",
        version: APP_VERSION,
        subcommands: [
            VersionCommand.self,
            StatusCommand.self,
            PingCommand.self,
            TraceCommand.self,
            DnsCommand.self,
            StackCommand.self,
            WifiCommand.self,
            ProxyCommand.self,
        ]
    )
}

// MARK: - Version Command
struct VersionData: Encodable {
    let name: String
    let version: String
    let platform: String
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print version information"
    )

    @OptionGroup var globalOptions: GlobalOptions

    mutating func run() throws {
        if globalOptions.shouldOutputJSON {
            let data = VersionData(name: "nactl", version: APP_VERSION, platform: "macos")
            JSONOutput.success(data, pretty: globalOptions.pretty)
        } else {
            print("nactl \(APP_VERSION) (macos)")
        }
    }
}

// MARK: - Exit Codes
enum NactlExitCode: Int32 {
    case success = 0
    case generalError = 1
    case invalidArguments = 2
    case permissionDenied = 3
    case interfaceNotFound = 4
    case timeout = 5
    case notAvailable = 6
    case locationServicesDenied = 7
}

// MARK: - Global Options
struct GlobalOptions: ParsableArguments {
    @Flag(name: [.short, .customLong("json")], help: "Output in JSON format")
    var json: Bool = false

    @Flag(name: [.short, .customLong("pretty")], help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: [.short, .customLong("interface")], help: "Specify network interface (e.g., en0, Wi-Fi)")
    var interface: String?

    /// Returns true if JSON output should be used (explicit flag or non-TTY stdout)
    var shouldOutputJSON: Bool {
        return json || !isatty(STDOUT_FILENO).boolValue
    }
}

extension Int32 {
    var boolValue: Bool {
        return self != 0
    }
}
