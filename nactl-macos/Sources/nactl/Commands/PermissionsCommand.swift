import ArgumentParser
import Foundation
import CoreLocation

/// nactl permissions - Check Location Services permission status (informational only)
/// Note: CLI tools cannot obtain Location Services permission on macOS - this command
/// reports the current status for diagnostic purposes.
struct PermissionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "permissions",
        abstract: "Check Location Services permission status (informational)"
    )

    @OptionGroup var globalOptions: GlobalOptions

    mutating func run() throws {
        let result = checkPermissions()

        if globalOptions.shouldOutputJSON {
            JSONOutput.success(result, pretty: globalOptions.pretty)
        } else {
            printHumanReadable(result)
        }

        // Always exit successfully - this is an informational command
        Darwin.exit(NactlExitCode.success.rawValue)
    }

    private func checkPermissions() -> PermissionsData {
        let locationStatus = checkLocationServices()
        return PermissionsData(
            locationServices: locationStatus,
            allGranted: locationStatus.granted
        )
    }

    private func checkLocationServices() -> LocationServicesStatus {
        let terminalApp = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "Terminal"

        // Check if Location Services is enabled system-wide
        let systemEnabled = CLLocationManager.locationServicesEnabled()

        if !systemEnabled {
            return LocationServicesStatus(
                granted: false,
                status: "disabled_system",
                message: "Location Services is disabled system-wide",
                terminalApp: terminalApp,
                suggestion: nil  // No actionable suggestion for CLI tools
            )
        }

        // Check authorization status for this app/terminal
        let manager = CLLocationManager()
        let authStatus = manager.authorizationStatus

        switch authStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return LocationServicesStatus(
                granted: true,
                status: "authorized",
                message: "Location Services permission granted",
                terminalApp: terminalApp,
                suggestion: nil
            )
        case .authorized:
            return LocationServicesStatus(
                granted: true,
                status: "authorized",
                message: "Location Services permission granted",
                terminalApp: terminalApp,
                suggestion: nil
            )
        case .denied:
            return LocationServicesStatus(
                granted: false,
                status: "denied",
                message: "Location Services not available for CLI tools",
                terminalApp: terminalApp,
                suggestion: nil  // CLI tools cannot obtain this permission
            )
        case .restricted:
            return LocationServicesStatus(
                granted: false,
                status: "restricted",
                message: "Location Services is restricted (parental controls or MDM)",
                terminalApp: terminalApp,
                suggestion: nil
            )
        case .notDetermined:
            return LocationServicesStatus(
                granted: false,
                status: "not_determined",
                message: "Location Services not available for CLI tools",
                terminalApp: terminalApp,
                suggestion: nil  // CLI tools cannot request this permission
            )
        @unknown default:
            return LocationServicesStatus(
                granted: false,
                status: "unknown",
                message: "Location Services status unknown",
                terminalApp: terminalApp,
                suggestion: nil
            )
        }
    }

    private func printHumanReadable(_ data: PermissionsData) {
        print("nactl Permissions Status")
        print("========================")
        print("")
        print("Location Services:")
        print("  Status: \(data.locationServices.status)")
        print("  Terminal App: \(data.locationServices.terminalApp)")

        if data.locationServices.granted {
            print("  ✓ Permission granted - full Wi-Fi information available")
        } else {
            print("  ○ Not available - using fallback methods for Wi-Fi data")
            print("")
            print("  Note: CLI tools cannot obtain Location Services permission on macOS.")
            print("  This is expected behavior. nactl will use system_profiler for SSID")
            print("  and return limited Wi-Fi data where full access is unavailable.")
        }
    }
}

// MARK: - Data Models

struct PermissionsData: Encodable {
    let locationServices: LocationServicesStatus
    let allGranted: Bool

    enum CodingKeys: String, CodingKey {
        case locationServices = "location_services"
        case allGranted = "all_granted"
    }
}

struct LocationServicesStatus: Encodable {
    let granted: Bool
    let status: String
    let message: String
    let terminalApp: String
    let suggestion: String?

    enum CodingKeys: String, CodingKey {
        case granted
        case status
        case message
        case terminalApp = "terminal_app"
        case suggestion
    }
}

// Note: PermissionsHelper for opening System Settings has been intentionally removed.
// CLI tools/daemons cannot obtain Location Services permission on macOS - they don't
// appear in System Preferences > Location Services. Opening the settings pane would
// only confuse users since there's no action they can take.
