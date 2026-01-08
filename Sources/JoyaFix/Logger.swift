import Foundation
import os.log

/// Centralized logging system for JoyaFix
/// Uses OSLog for efficient, structured logging
enum Logger {
    // MARK: - Log Categories
    
    private static let subsystem = "com.joyafix.app"
    
    static let general = OSLog(subsystem: subsystem, category: "general")
    static let network = OSLog(subsystem: subsystem, category: "network")
    static let ocr = OSLog(subsystem: subsystem, category: "ocr")
    static let clipboard = OSLog(subsystem: subsystem, category: "clipboard")
    static let hotkeys = OSLog(subsystem: subsystem, category: "hotkeys")
    static let snippets = OSLog(subsystem: subsystem, category: "snippets")
    static let security = OSLog(subsystem: subsystem, category: "security")
    static let performance = OSLog(subsystem: subsystem, category: "performance")
    static let database = OSLog(subsystem: subsystem, category: "database")
    
    // MARK: - Log Levels
    
    /// Logs a debug message (only in debug builds)
    static func debug(_ message: String, category: OSLog = general, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        os_log("%{public}@ [%{public}@:%{public}@:%d]", log: category, type: .debug, message, fileName, function, line)
        #endif
    }
    
    /// Logs an info message
    static func info(_ message: String, category: OSLog = general, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        os_log("%{public}@ [%{public}@:%{public}@:%d]", log: category, type: .info, message, fileName, function, line)
    }
    
    /// Logs a warning message
    static func warning(_ message: String, category: OSLog = general, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        os_log("%{public}@ [%{public}@:%{public}@:%d]", log: category, type: .default, message, fileName, function, line)
    }
    
    /// Logs an error message
    static func error(_ message: String, category: OSLog = general, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        os_log("%{public}@ [%{public}@:%{public}@:%d]", log: category, type: .error, message, fileName, function, line)
    }
    
    /// Logs a critical error message
    static func critical(_ message: String, category: OSLog = general, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        os_log("%{public}@ [%{public}@:%{public}@:%d]", log: category, type: .fault, message, fileName, function, line)
    }
    
    // MARK: - Convenience Methods
    
    /// Logs network-related messages
    static func network(_ message: String, level: LogLevel = .info) {
        log(message, category: network, level: level)
    }
    
    /// Logs OCR-related messages
    static func ocr(_ message: String, level: LogLevel = .info) {
        log(message, category: ocr, level: level)
    }
    
    /// Logs clipboard-related messages
    static func clipboard(_ message: String, level: LogLevel = .info) {
        log(message, category: clipboard, level: level)
    }
    
    /// Logs hotkey-related messages
    static func hotkey(_ message: String, level: LogLevel = .info) {
        log(message, category: hotkeys, level: level)
    }
    
    /// Logs snippet-related messages
    static func snippet(_ message: String, level: LogLevel = .info) {
        log(message, category: snippets, level: level)
    }
    
    /// Logs security-related messages
    static func security(_ message: String, level: LogLevel = .warning) {
        log(message, category: security, level: level)
    }
    
    /// Logs performance-related messages
    static func performance(_ message: String, level: LogLevel = .info) {
        log(message, category: performance, level: level)
    }
    
    /// Logs database-related messages
    static func database(_ message: String, level: LogLevel = .info) {
        log(message, category: database, level: level)
    }
    
    // MARK: - Private Helpers
    
    enum LogLevel {
        case debug, info, warning, error, critical
    }
    
    private static func log(_ message: String, category: OSLog, level: LogLevel, file: String = #file, function: String = #function, line: Int = #line) {
        switch level {
        case .debug:
            debug(message, category: category, file: file, function: function, line: line)
        case .info:
            info(message, category: category, file: file, function: function, line: line)
        case .warning:
            warning(message, category: category, file: file, function: function, line: line)
        case .error:
            error(message, category: category, file: file, function: function, line: line)
        case .critical:
            critical(message, category: category, file: file, function: function, line: line)
        }
    }
}

