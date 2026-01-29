import ArgumentParser
import Foundation

/// nactl ping - Test connectivity to a host
struct PingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ping",
        abstract: "Test connectivity to a host"
    )

    @Argument(help: "Host to ping (hostname or IP address)")
    var host: String

    @Option(name: [.short, .customLong("count")], help: "Number of packets to send")
    var count: Int = 4

    @Option(name: [.short, .customLong("timeout")], help: "Timeout in milliseconds")
    var timeout: Int = 1000

    @OptionGroup var globalOptions: GlobalOptions

    mutating func run() throws {
        // Validate host
        guard host.isValidHostname || host.isValidIPAddress else {
            exitWithError(.invalidArguments("Invalid host format: \(host)"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
        }

        // Calculate timeout in seconds (ping uses seconds)
        let timeoutSecs = max(1, timeout / 1000)

        // Execute ping
        let result = executePing(host: host, count: count, timeoutSecs: timeoutSecs)

        switch result {
        case .success(let data):
            if globalOptions.shouldOutputJSON {
                JSONOutput.success(data, pretty: globalOptions.pretty)
            } else {
                printHumanReadable(data)
            }
        case .failure(let error):
            exitWithError(error, json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
        }
    }

    private func executePing(host: String, count: Int, timeoutSecs: Int) -> Result<PingResultData, NactlError> {
        var pingResults: [PingResult] = []
        var resolvedIp: String?
        var ttlValue: Int?

        // Use the system ping command
        // -c = count, -W = timeout in ms (macOS uses milliseconds)
        let pingResult = ShellExecutor.execute(
            "/sbin/ping",
            arguments: ["-c", String(count), "-W", String(timeoutSecs * 1000), host],
            timeout: Double(count * timeoutSecs + 5)
        )

        // Parse the output regardless of exit code (ping returns 1 for partial loss)
        let output = pingResult.output

        // Parse resolved IP from first line: PING host (ip): ...
        if let ipMatch = output.range(of: "\\(([0-9\\.]+)\\)", options: .regularExpression) {
            var ip = String(output[ipMatch])
            ip.removeFirst() // Remove (
            ip.removeLast()  // Remove )
            resolvedIp = ip
        }

        // Parse individual ping responses
        // Format: 64 bytes from ip: icmp_seq=N ttl=N time=N.N ms
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains("bytes from") && line.contains("icmp_seq=") {
                var seq: Int?
                var ttl: Int?
                var time: Double?

                // Extract seq
                if let seqMatch = line.range(of: "icmp_seq=(\\d+)", options: .regularExpression) {
                    let seqStr = String(line[seqMatch]).replacingOccurrences(of: "icmp_seq=", with: "")
                    seq = Int(seqStr)
                }

                // Extract ttl
                if let ttlMatch = line.range(of: "ttl=(\\d+)", options: .regularExpression) {
                    let ttlStr = String(line[ttlMatch]).replacingOccurrences(of: "ttl=", with: "")
                    ttl = Int(ttlStr)
                    if ttlValue == nil { ttlValue = ttl }
                }

                // Extract time
                if let timeMatch = line.range(of: "time=([0-9\\.]+)", options: .regularExpression) {
                    let timeStr = String(line[timeMatch]).replacingOccurrences(of: "time=", with: "")
                    time = Double(timeStr)
                }

                if let s = seq {
                    pingResults.append(PingResult(seq: s, ttl: ttl, timeMs: time))
                }
            }
        }

        // Parse statistics
        // Format: N packets transmitted, N received, N% packet loss
        var packetsSent = count
        var packetsReceived = 0
        var packetLoss = 100.0

        for line in lines {
            if line.contains("packets transmitted") {
                // Parse: "4 packets transmitted, 4 received, 0% packet loss"
                // or "4 packets transmitted, 4 packets received, 0.0% packet loss"
                let parts = line.components(separatedBy: ", ")
                for part in parts {
                    if part.contains("transmitted") {
                        if let num = Int(part.components(separatedBy: " ").first ?? "") {
                            packetsSent = num
                        }
                    } else if part.contains("received") {
                        if let num = Int(part.components(separatedBy: " ").first ?? "") {
                            packetsReceived = num
                        }
                    } else if part.contains("packet loss") {
                        let lossStr = part.replacingOccurrences(of: "% packet loss", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if let loss = Double(lossStr) {
                            packetLoss = loss
                        }
                    }
                }
            }
        }

        // Calculate min/avg/max from results
        let times = pingResults.compactMap { $0.timeMs }
        let minMs = times.min()
        let maxMs = times.max()
        let avgMs = times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)

        // Check for errors
        if pingResult.exitCode != 0 && packetsReceived == 0 {
            if pingResult.errorOutput.contains("Unknown host") || output.contains("Unknown host") {
                return .failure(.generalError("Unknown host: \(host)"))
            }
            if pingResult.exitCode == 2 {
                return .failure(.timeout("All packets timed out"))
            }
        }

        return .success(PingResultData(
            host: host,
            resolvedIp: resolvedIp,
            packetsSent: packetsSent,
            packetsReceived: packetsReceived,
            packetLossPercent: packetLoss,
            minMs: minMs,
            avgMs: avgMs,
            maxMs: maxMs,
            results: pingResults
        ))
    }

    private func printHumanReadable(_ data: PingResultData) {
        print("Pinging \(data.host)", terminator: "")
        if let ip = data.resolvedIp, ip != data.host {
            print(" [\(ip)]", terminator: "")
        }
        print(":")
        print("")

        for result in data.results {
            if let time = result.timeMs {
                var line = "Reply from \(data.resolvedIp ?? data.host): seq=\(result.seq)"
                if let ttl = result.ttl {
                    line += " ttl=\(ttl)"
                }
                line += " time=\(String(format: "%.1f", time))ms"
                print(line)
            } else {
                print("Request timeout for seq=\(result.seq)")
            }
        }

        print("")
        print("--- \(data.host) ping statistics ---")
        print("\(data.packetsSent) packets transmitted, \(data.packetsReceived) received, \(String(format: "%.0f", data.packetLossPercent))% packet loss")

        if let min = data.minMs, let avg = data.avgMs, let max = data.maxMs {
            print("round-trip min/avg/max = \(String(format: "%.1f", min))/\(String(format: "%.1f", avg))/\(String(format: "%.1f", max)) ms")
        }
    }
}
