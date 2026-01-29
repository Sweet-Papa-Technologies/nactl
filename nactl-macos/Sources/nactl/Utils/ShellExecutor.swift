import Foundation

/// Shell command execution utilities
struct ShellExecutor {
    /// Result of a shell command execution
    struct CommandResult {
        let output: String
        let errorOutput: String
        let exitCode: Int32

        var succeeded: Bool {
            return exitCode == 0
        }
    }

    /// Execute a shell command and return the result
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Arguments for the command
    ///   - timeout: Timeout in seconds (default 30)
    /// - Returns: CommandResult with output, error output, and exit code
    static func execute(
        _ command: String,
        arguments: [String] = [],
        timeout: TimeInterval = 30
    ) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            // Set up timeout
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if process.isRunning {
                process.terminate()
                return CommandResult(
                    output: "",
                    errorOutput: "Command timed out",
                    exitCode: -1
                )
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            return CommandResult(
                output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                errorOutput: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                exitCode: process.terminationStatus
            )
        } catch {
            return CommandResult(
                output: "",
                errorOutput: error.localizedDescription,
                exitCode: -1
            )
        }
    }

    /// Execute a command using /bin/sh
    static func shell(_ command: String, timeout: TimeInterval = 30) -> CommandResult {
        return execute("/bin/sh", arguments: ["-c", command], timeout: timeout)
    }

    /// Execute a command and stream output line by line
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Arguments for the command
    ///   - timeout: Timeout in seconds
    ///   - onLine: Callback for each line of output
    /// - Returns: Exit code
    static func executeWithStreaming(
        _ command: String,
        arguments: [String] = [],
        timeout: TimeInterval = 60,
        onLine: @escaping (String) -> Void
    ) -> Int32 {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var outputBuffer = ""
        let outputHandle = outputPipe.fileHandleForReading

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0, let str = String(data: data, encoding: .utf8) {
                outputBuffer += str
                while let range = outputBuffer.range(of: "\n") {
                    let line = String(outputBuffer[..<range.lowerBound])
                    onLine(line)
                    outputBuffer = String(outputBuffer[range.upperBound...])
                }
            }
        }

        do {
            try process.run()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if process.isRunning {
                process.terminate()
                return -1
            }

            // Process any remaining buffer
            if !outputBuffer.isEmpty {
                onLine(outputBuffer)
            }

            outputHandle.readabilityHandler = nil
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

// MARK: - Input Validation

extension String {
    /// Validate that a string is a valid SSID (no dangerous characters)
    var isValidSSID: Bool {
        // SSIDs can be up to 32 bytes
        guard self.utf8.count <= 32 else { return false }
        // Check for dangerous characters that could be used for command injection
        let dangerousChars = CharacterSet(charactersIn: "\"'\\`$\n\r\0")
        return self.rangeOfCharacter(from: dangerousChars) == nil
    }

    /// Validate that a string is a valid hostname
    var isValidHostname: Bool {
        // Basic hostname validation
        let hostnameRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-\\.]*[a-zA-Z0-9])?$"
        return self.range(of: hostnameRegex, options: .regularExpression) != nil
    }

    /// Validate that a string is a valid IP address
    var isValidIPAddress: Bool {
        // IPv4
        let ipv4Regex = "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        if self.range(of: ipv4Regex, options: .regularExpression) != nil {
            return true
        }
        // IPv6 (simplified check)
        let ipv6Regex = "^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$"
        return self.range(of: ipv6Regex, options: .regularExpression) != nil
    }

    /// Shell-escaped version of the string
    var shellEscaped: String {
        // Escape single quotes by ending the single-quoted string, adding an escaped single quote, and starting a new single-quoted string
        return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
