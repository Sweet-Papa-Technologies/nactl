import ArgumentParser
import Foundation

/// nactl trace - Trace route to destination
struct TraceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trace",
        abstract: "Trace route to destination"
    )

    @Argument(help: "Host to trace route to")
    var host: String

    @Option(name: .customLong("max-hops"), help: "Maximum number of hops")
    var maxHops: Int = 30

    @Option(name: [.short, .customLong("timeout")], help: "Timeout in milliseconds (0 for no timeout)")
    var timeout: Int = 60000

    @OptionGroup var globalOptions: GlobalOptions

    mutating func run() throws {
        // Validate host
        guard host.isValidHostname || host.isValidIPAddress else {
            exitWithError(.invalidArguments("Invalid host format: \(host)"), json: globalOptions.shouldOutputJSON, pretty: globalOptions.pretty)
        }

        let result = executeTraceroute(host: host, maxHops: maxHops, timeout: timeout)

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

    private func executeTraceroute(host: String, maxHops: Int, timeout: Int) -> Result<TraceResultData, NactlError> {
        var hops: [TraceHop] = []
        var destinationReached = false

        // Calculate timeout: use user-specified value, or calculate based on hops if 0
        let effectiveTimeout: Double
        if timeout == 0 {
            // No timeout - use a very large value (1 hour)
            effectiveTimeout = 3600.0
        } else {
            effectiveTimeout = Double(timeout) / 1000.0  // Convert ms to seconds
        }

        // Execute traceroute with max hops
        // -m = max TTL, -q 3 = 3 queries per hop, -w = wait time per probe
        let waitTimePerProbe = min(5, max(1, Int(effectiveTimeout) / maxHops / 3))
        let result = ShellExecutor.execute(
            "/usr/sbin/traceroute",
            arguments: ["-m", String(maxHops), "-q", "3", "-w", String(waitTimePerProbe), host],
            timeout: effectiveTimeout
        )

        // Parse output line by line
        // Format: N  hostname (ip)  time1 ms  time2 ms  time3 ms
        // or: N  * * *
        let lines = result.output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip header line: "traceroute to host (ip), maxhops hops max, ..."
            if trimmed.hasPrefix("traceroute to") { continue }
            if trimmed.isEmpty { continue }

            // Parse hop number at the beginning
            let parts = trimmed.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2, let hopNum = Int(parts[0]) else { continue }

            // Check if this is a timeout line (* * *)
            let restOfLine = parts.dropFirst().joined(separator: " ")
            if restOfLine.hasPrefix("*") && !restOfLine.contains("(") {
                hops.append(TraceHop(hop: hopNum, ip: "*", hostname: nil, timeMs: nil))
                continue
            }

            // Parse hostname and IP
            var hostname: String?
            var ip: String?
            var times: [Double] = []

            // Look for (ip) pattern
            if let ipMatch = restOfLine.range(of: "\\(([0-9\\.]+)\\)", options: .regularExpression) {
                var ipStr = String(restOfLine[ipMatch])
                ipStr.removeFirst()
                ipStr.removeLast()
                ip = ipStr

                // Get hostname before the IP
                if let ipStart = restOfLine.range(of: "(") {
                    let hostnameStr = String(restOfLine[..<ipStart.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !hostnameStr.isEmpty && hostnameStr != ip {
                        hostname = hostnameStr
                    }
                }
            }

            // Parse time values (N.NNN ms)
            let timeRegex = try? NSRegularExpression(pattern: "([0-9]+\\.?[0-9]*)\\s*ms", options: [])
            if let regex = timeRegex {
                let nsRange = NSRange(restOfLine.startIndex..., in: restOfLine)
                let matches = regex.matches(in: restOfLine, options: [], range: nsRange)
                for match in matches {
                    if let range = Range(match.range(at: 1), in: restOfLine) {
                        if let time = Double(restOfLine[range]) {
                            times.append(time)
                        }
                    }
                }
            }

            // Check if destination is reached
            if let resolvedIp = ip {
                // Check if this is the destination
                if resolvedIp == host || hostname == host {
                    destinationReached = true
                }
            }

            hops.append(TraceHop(
                hop: hopNum,
                ip: ip,
                hostname: hostname,
                timeMs: times.isEmpty ? nil : times
            ))
        }

        // If last hop shows destination IP, mark as reached
        if let lastHop = hops.last {
            if lastHop.hostname == host || lastHop.ip == host {
                destinationReached = true
            }
        }

        return .success(TraceResultData(
            host: host,
            hops: hops,
            destinationReached: destinationReached,
            totalHops: hops.count
        ))
    }

    private func printHumanReadable(_ data: TraceResultData) {
        print("Traceroute to \(data.host)")
        print("")

        for hop in data.hops {
            var line = String(format: "%2d  ", hop.hop)

            if hop.ip == "*" {
                line += "* * *"
            } else {
                if let hostname = hop.hostname {
                    line += "\(hostname) "
                }
                if let ip = hop.ip {
                    line += "(\(ip)) "
                }
                if let times = hop.timeMs {
                    line += times.map { String(format: "%.3f ms", $0) }.joined(separator: "  ")
                }
            }

            print(line)
        }

        print("")
        if data.destinationReached {
            print("Destination reached in \(data.totalHops) hops")
        } else {
            print("Destination not reached after \(data.totalHops) hops")
        }
    }
}
