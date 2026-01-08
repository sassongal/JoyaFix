import Foundation
import os.signpost

/// Performance monitoring utilities
enum PerformanceMonitor {
    private static let log = OSLog(subsystem: "com.joyafix.app", category: .pointsOfInterest)
    
    /// Measures execution time of a block
    static func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.performance("\(name) took \(String(format: "%.3f", timeElapsed))s", level: .info)
        }
        
        return try operation()
    }
    
    /// Measures execution time of an async block
    static func measureAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            Logger.performance("\(name) took \(String(format: "%.3f", timeElapsed))s", level: .info)
        }
        
        return try await operation()
    }
}

