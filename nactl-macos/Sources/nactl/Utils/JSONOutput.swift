import Foundation

// MARK: - JSON Output Utilities

/// Protocol for types that can be output as JSON
protocol JSONOutputable: Encodable {}

/// Success response wrapper
struct SuccessResponse<T: Encodable>: Encodable {
    let success: Bool = true
    let data: T?
    let message: String?

    init(data: T) {
        self.data = data
        self.message = nil
    }

    init(message: String) {
        self.data = nil
        self.message = message
    }

    init(data: T, message: String) {
        self.data = data
        self.message = message
    }
}

/// Simple success response with just a message
struct SimpleSuccessResponse: Encodable {
    let success: Bool = true
    let message: String
}

/// Error details for JSON output
struct ErrorDetails: Encodable {
    let code: String
    let message: String
    let suggestion: String?
}

/// Error response wrapper
struct ErrorResponse: Encodable {
    let success: Bool = false
    let error: ErrorDetails
}

/// Nactl error types with associated exit codes and JSON representation
enum NactlError: Error {
    case generalError(String)
    case invalidArguments(String)
    case permissionDenied(String)
    case interfaceNotFound(String)
    case timeout(String)
    case notAvailable(String)
    case locationServicesDenied
    case commandFailed(String)
    case parseError(String)

    var exitCode: NactlExitCode {
        switch self {
        case .generalError: return .generalError
        case .invalidArguments: return .invalidArguments
        case .permissionDenied: return .permissionDenied
        case .interfaceNotFound: return .interfaceNotFound
        case .timeout: return .timeout
        case .notAvailable: return .notAvailable
        case .locationServicesDenied: return .locationServicesDenied
        case .commandFailed: return .generalError
        case .parseError: return .generalError
        }
    }

    var errorCode: String {
        switch self {
        case .generalError: return "GENERAL_ERROR"
        case .invalidArguments: return "INVALID_ARGUMENTS"
        case .permissionDenied: return "PERMISSION_DENIED"
        case .interfaceNotFound: return "INTERFACE_NOT_FOUND"
        case .timeout: return "TIMEOUT"
        case .notAvailable: return "NOT_AVAILABLE"
        case .locationServicesDenied: return "LOCATION_SERVICES_DENIED"
        case .commandFailed: return "COMMAND_FAILED"
        case .parseError: return "PARSE_ERROR"
        }
    }

    var message: String {
        switch self {
        case .generalError(let msg): return msg
        case .invalidArguments(let msg): return msg
        case .permissionDenied(let msg): return msg
        case .interfaceNotFound(let msg): return msg
        case .timeout(let msg): return msg
        case .notAvailable(let msg): return msg
        case .locationServicesDenied: return "Location Services permission denied. Wi-Fi scanning requires Location Services access."
        case .commandFailed(let msg): return msg
        case .parseError(let msg): return msg
        }
    }

    var suggestion: String? {
        switch self {
        case .permissionDenied:
            return "Run with elevated permissions using sudo"
        case .locationServicesDenied:
            return "Grant Location Services permission in System Preferences > Security & Privacy > Privacy > Location Services"
        case .interfaceNotFound:
            return "Check available interfaces with 'networksetup -listallhardwareports'"
        default:
            return nil
        }
    }

    func toErrorResponse() -> ErrorResponse {
        return ErrorResponse(error: ErrorDetails(
            code: errorCode,
            message: message,
            suggestion: suggestion
        ))
    }
}

/// JSON output helper
struct JSONOutput {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// Output a success response with data
    static func success<T: Encodable>(_ data: T, pretty: Bool = false) {
        let response = SuccessResponse(data: data)
        output(response, pretty: pretty)
    }

    /// Output a success response with just a message
    static func successMessage(_ message: String, pretty: Bool = false) {
        let response = SimpleSuccessResponse(message: message)
        output(response, pretty: pretty)
    }

    /// Output a success response with data and message
    static func success<T: Encodable>(_ data: T, message: String, pretty: Bool = false) {
        let response = SuccessResponse(data: data, message: message)
        output(response, pretty: pretty)
    }

    /// Output an error response
    static func error(_ error: NactlError, pretty: Bool = false) {
        let response = error.toErrorResponse()
        outputToStderr(response, pretty: pretty)
    }

    /// Output any encodable value
    static func output<T: Encodable>(_ value: T, pretty: Bool = false) {
        let selectedEncoder = pretty ? prettyEncoder : encoder
        do {
            let data = try selectedEncoder.encode(value)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            fputs("{\"success\":false,\"error\":{\"code\":\"ENCODING_ERROR\",\"message\":\"Failed to encode response\"}}\n", stderr)
        }
    }

    /// Output to stderr
    static func outputToStderr<T: Encodable>(_ value: T, pretty: Bool = false) {
        let selectedEncoder = pretty ? prettyEncoder : encoder
        do {
            let data = try selectedEncoder.encode(value)
            if let jsonString = String(data: data, encoding: .utf8) {
                fputs(jsonString + "\n", stderr)
            }
        } catch {
            fputs("{\"success\":false,\"error\":{\"code\":\"ENCODING_ERROR\",\"message\":\"Failed to encode response\"}}\n", stderr)
        }
    }

    /// Print human-readable output (non-JSON mode)
    static func printText(_ text: String) {
        print(text)
    }

    /// Print error text to stderr
    static func printError(_ text: String) {
        fputs(text + "\n", stderr)
    }
}

/// Exit with error, outputting JSON if needed
func exitWithError(_ error: NactlError, json: Bool = true, pretty: Bool = false) -> Never {
    if json {
        JSONOutput.error(error, pretty: pretty)
    } else {
        JSONOutput.printError("Error: \(error.message)")
        if let suggestion = error.suggestion {
            JSONOutput.printError("Suggestion: \(suggestion)")
        }
    }
    Darwin.exit(error.exitCode.rawValue)
}
