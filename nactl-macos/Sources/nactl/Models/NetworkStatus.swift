import Foundation

/// Network status data model
struct NetworkStatusData: Encodable {
    let connected: Bool
    let type: String?
    let interface: String?
    let ssid: String?
    let bssid: String?
    let signalStrength: Int?
    let signalRssi: Int?
    let channel: Int?
    let frequency: String?
    let linkSpeed: String?
    let ipAddress: String?
    let subnetMask: String?
    let gateway: String?
    let dnsServers: [String]
    let macAddress: String?
    let limitedMode: Bool
    let limitedReason: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case type
        case interface
        case ssid
        case bssid
        case signalStrength = "signal_strength"
        case signalRssi = "signal_rssi"
        case channel
        case frequency
        case linkSpeed = "link_speed"
        case ipAddress = "ip_address"
        case subnetMask = "subnet_mask"
        case gateway
        case dnsServers = "dns_servers"
        case macAddress = "mac_address"
        case limitedMode = "limited_mode"
        case limitedReason = "limited_reason"
    }
}

/// Ping result data model
struct PingResultData: Encodable {
    let host: String
    let resolvedIp: String?
    let packetsSent: Int
    let packetsReceived: Int
    let packetLossPercent: Double
    let minMs: Double?
    let avgMs: Double?
    let maxMs: Double?
    let results: [PingResult]

    enum CodingKeys: String, CodingKey {
        case host
        case resolvedIp = "resolved_ip"
        case packetsSent = "packets_sent"
        case packetsReceived = "packets_received"
        case packetLossPercent = "packet_loss_percent"
        case minMs = "min_ms"
        case avgMs = "avg_ms"
        case maxMs = "max_ms"
        case results
    }
}

struct PingResult: Encodable {
    let seq: Int
    let ttl: Int?
    let timeMs: Double?

    enum CodingKeys: String, CodingKey {
        case seq
        case ttl
        case timeMs = "time_ms"
    }
}

/// Traceroute data model
struct TraceResultData: Encodable {
    let host: String
    let hops: [TraceHop]
    let destinationReached: Bool
    let totalHops: Int

    enum CodingKeys: String, CodingKey {
        case host
        case hops
        case destinationReached = "destination_reached"
        case totalHops = "total_hops"
    }
}

struct TraceHop: Encodable {
    let hop: Int
    let ip: String?
    let hostname: String?
    let timeMs: [Double]?

    enum CodingKeys: String, CodingKey {
        case hop
        case ip
        case hostname
        case timeMs = "time_ms"
    }
}

/// DNS operation result
struct DnsSetData: Encodable {
    let interface: String
    let primary: String
    let secondary: String?
}

/// Stack reset result
struct StackResetData: Encodable {
    let level: String
    let actionsPerformed: [String]
    let rebootRequired: Bool

    enum CodingKeys: String, CodingKey {
        case level
        case actionsPerformed = "actions_performed"
        case rebootRequired = "reboot_required"
    }
}
