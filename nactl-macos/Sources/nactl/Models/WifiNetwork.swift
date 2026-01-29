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

/// Security type enumeration
enum WifiSecurityType: String {
    case open = "Open"
    case wep = "WEP"
    case wpaPsk = "WPA-Personal"
    case wpa2Psk = "WPA2-Personal"
    case wpa3Psk = "WPA3-Personal"
    case wpaEnterprise = "WPA-Enterprise"
    case wpa2Enterprise = "WPA2-Enterprise"
    case wpa3Enterprise = "WPA3-Enterprise"
    case wpa3Sae = "WPA3-SAE"
    case unknown = "Unknown"

    init(fromCWSecurityMode mode: Int) {
        // CWSecurity enum values
        // 0 = None, 1 = WEP, 2 = WPA Personal, 3 = WPA Personal Mixed
        // 4 = WPA2 Personal, 5 = Personal, 6 = Dynamic WEP
        // 7 = WPA Enterprise, 8 = WPA Enterprise Mixed, 9 = WPA2 Enterprise
        // 10 = Enterprise, 11 = WPA3 Personal, 12 = WPA3 Enterprise
        // 13 = WPA3 Transition
        switch mode {
        case 0: self = .open
        case 1: self = .wep
        case 2, 3: self = .wpaPsk
        case 4, 5: self = .wpa2Psk
        case 6: self = .wep
        case 7, 8: self = .wpaEnterprise
        case 9, 10: self = .wpa2Enterprise
        case 11, 13: self = .wpa3Psk
        case 12: self = .wpa3Enterprise
        default: self = .unknown
        }
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
