import ArgumentParser
import Foundation
import CoreLocation
import AppKit

/// nactl permissions - Check and manage required permissions
struct PermissionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "permissions",
        abstract: "Check and manage required permissions (Location Services)"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Flag(name: [.long], help: "Open System Settings to grant permissions")
    var fix: Bool = false

    mutating func run() throws {
        let result = checkPermissions()

        if globalOptions.shouldOutputJSON {
            JSONOutput.success(result, pretty: globalOptions.pretty)
        } else {
            printHumanReadable(result)
        }

        // If --fix flag and permissions not granted, open settings
        if fix && !result.locationServices.granted {
            if !globalOptions.shouldOutputJSON {
                print("")
                print("Opening System Settings to Location Services...")
                print("Please enable Location Services for: \(result.locationServices.terminalApp)")
            }
            PermissionsHelper.openLocationSettings()
        }

        // Exit with appropriate code
        if result.allGranted {
            Darwin.exit(NactlExitCode.success.rawValue)
        } else {
            Darwin.exit(NactlExitCode.locationServicesDenied.rawValue)
        }
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
                suggestion: "Enable Location Services in System Settings > Privacy & Security > Location Services"
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
                message: "Location Services permission denied for \(terminalApp)",
                terminalApp: terminalApp,
                suggestion: "Enable Location Services for \(terminalApp) in System Settings > Privacy & Security > Location Services"
            )
        case .restricted:
            return LocationServicesStatus(
                granted: false,
                status: "restricted",
                message: "Location Services is restricted (parental controls or MDM)",
                terminalApp: terminalApp,
                suggestion: "Contact your administrator to enable Location Services"
            )
        case .notDetermined:
            return LocationServicesStatus(
                granted: false,
                status: "not_determined",
                message: "Location Services permission not yet requested",
                terminalApp: terminalApp,
                suggestion: "Run 'nactl permissions --fix' to open System Settings, then enable Location Services for \(terminalApp)"
            )
        @unknown default:
            return LocationServicesStatus(
                granted: false,
                status: "unknown",
                message: "Location Services status unknown",
                terminalApp: terminalApp,
                suggestion: "Check System Settings > Privacy & Security > Location Services"
            )
        }
    }

    private func printHumanReadable(_ data: PermissionsData) {
        print("nactl Permissions Check")
        print("=======================")
        print("")
        print("Location Services (required for Wi-Fi scanning):")
        print("  Status: \(data.locationServices.status)")
        print("  Terminal App: \(data.locationServices.terminalApp)")

        if data.locationServices.granted {
            print("  ✓ Permission granted - Wi-Fi scanning will show network names")
        } else {
            print("  ✗ Permission NOT granted - Wi-Fi networks will appear as '<Hidden>'")
            if let suggestion = data.locationServices.suggestion {
                print("")
                print("  How to fix:")
                print("  \(suggestion)")
            }
            print("")
            print("  Tip: Run 'nactl permissions --fix' to open System Settings automatically")
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

// MARK: - Helper

struct PermissionsHelper {
    /// Open System Settings to Location Services pane
    static func openLocationSettings() {
        // macOS Ventura and later
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}
