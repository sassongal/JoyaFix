import Foundation
import os.log

/// Crash reporting and error tracking
enum CrashReporter {
    private static let log = OSLog(subsystem: "com.joyafix.app", category: "crash")
    
    /// Reports a non-fatal error
    static func reportError(_ error: Error, context: String = "", userInfo: [String: Any] = [:]) {
        let errorDescription = error.localizedDescription
        Logger.critical("Error in \(context): \(errorDescription)", category: log)
        
        // In production, send to crash reporting service (Firebase, Sentry, etc.)
        #if DEBUG
        print("🔴 Error Report:")
        print("  Context: \(context)")
        print("  Error: \(errorDescription)")
        print("  UserInfo: \(userInfo)")
        #endif
    }
    
    /// Reports a fatal error
    static func reportFatalError(_ message: String, context: String = "") {
        Logger.critical("Fatal error in \(context): \(message)", category: log)
        
        // In production, send to crash reporting service
        #if DEBUG
        fatalError("\(context): \(message)")
        #else
        // Log and continue in production
        #endif
    }
    
    /// Sets up crash reporting
    static func setup() {
        // Setup NSSetUncaughtExceptionHandler if needed
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }
}

/// Global exception handler (must be a free function for C interop)
private func uncaughtExceptionHandler(_ exception: NSException) {
    let reason = exception.reason ?? "Unknown"
    let name = exception.name.rawValue
    let log = OSLog(subsystem: "com.joyafix.app", category: "crash")
    Logger.critical("Uncaught exception: \(name) - \(reason)", category: log)
}

