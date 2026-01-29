import Foundation

/// Wi-Fi network data model
struct WifiNetworkData: Encodable {
    let ssid: String
    let bssid: String
    let signalStrength: Int
    let signalRssi: Int
    let channel: Int
    let frequency: String
    let security: String
    let known: Bool

    enum CodingKeys: String, CodingKey {
        case ssid
        case bssid
        case signalStrength = "signal_strength"
        case signalRssi = "signal_rssi"
        case channel
        case frequency
        case security
        case known
    }
}

/// Wi-Fi scan result wrapper
struct WifiScanData: Encodable {
    let networks: [WifiNetworkData]
    let scanTimeMs: Int

    enum CodingKeys: String, CodingKey {
        case networks
        case scanTimeMs = "scan_time_ms"
    }
}

/// Wi-Fi forget result
struct WifiForgetData: Encodable {
    let ssid: String
    let wasConnected: Bool
    let keychainCleared: Bool

    enum CodingKeys: String, CodingKey {
        case ssid
        case wasConnected = "was_connected"
        case keychainCleared = "keychain_cleared"
    }
}

/// Helper to convert channel number to frequency band
func frequencyBand(for channel: Int) -> String {
    if channel >= 1 && channel <= 14 {
        return "2.4GHz"
    } else if channel >= 32 && channel <= 177 {
        return "5GHz"
    } else if channel >= 1 && channel <= 233 {
        // 6GHz channels start at 1 but use different numbers
        return "6GHz"
    }
    return "Unknown"
}
