import Foundation

/// Centralized logging utility for the HyperliquidSDK.
///
/// All SDK log messages are prefixed with `[HLSDK]` for easy console filtering.
/// Logging is enabled by default but can be toggled via `HLLog.enabled`.
///
/// Usage:
/// ```
/// HLLog.info("Connected to WebSocket")
/// HLLog.error("Failed to decode response: \(error)")
/// HLLog.debug("Raw response: \(data)")
/// ```
public struct HLLog {

    /// Controls whether SDK log messages are printed to the console.
    /// Default is `true`. Set to `false` to suppress all SDK logs.
    public static var enabled: Bool = true

    /// Log level filter. Only messages at or above this level are printed.
    /// Default is `.debug` (all messages).
    public static var level: LogLevel = .debug

    /// Log levels in ascending order of severity.
    public enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// Logs a debug-level message. Used for verbose output like raw data and internal state.
    public static func debug(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        log(level: .debug, message: message(), file: file, function: function)
    }

    /// Logs an info-level message. Used for key flow milestones like connection events and API calls.
    public static func info(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        log(level: .info, message: message(), file: file, function: function)
    }

    /// Logs a warning-level message. Used for recoverable issues like deprecated APIs or unexpected data.
    public static func warning(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        log(level: .warning, message: message(), file: file, function: function)
    }

    /// Logs an error-level message. Used for failures like network errors and decoding issues.
    public static func error(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        log(level: .error, message: message(), file: file, function: function)
    }

    // MARK: - Private

    private static func log(level: LogLevel, message: String, file: String, function: String) {
        guard enabled, level >= HLLog.level else { return }
        let fileName = (file as NSString).lastPathComponent
        let funcName = function
        let tag: String
        switch level {
        case .debug: tag = "DEBUG"
        case .info: tag = "INFO"
        case .warning: tag = "WARN"
        case .error: tag = "ERROR"
        }
        print("[HLSDK] [\(tag)] [\(fileName):\(funcName)] \(message)")
    }
}
