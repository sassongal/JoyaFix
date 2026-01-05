import Foundation

/// Manages rate limiting for Cloud OCR API calls
@MainActor
class OCRRateLimiter {
    static let shared = OCRRateLimiter()
    
    private var requestTimestamps: [Date] = []
    private let rateLimitQueue = DispatchQueue(label: "com.joyafix.ocrratelimit", attributes: .concurrent)
    
    private init() {}
    
    /// Checks if a new request can be made based on rate limits
    func canMakeRequest() -> Bool {
        return rateLimitQueue.sync {
            let now = Date()
            let windowStart = now.addingTimeInterval(-JoyaFixConstants.rateLimitWindow)
            
            // Remove timestamps outside the window
            requestTimestamps.removeAll { $0 < windowStart }
            
            // Check if we're under the limit
            return requestTimestamps.count < JoyaFixConstants.maxCloudOCRRequestsPerMinute
        }
    }
    
    /// Records a new request timestamp
    func recordRequest() {
        rateLimitQueue.async(flags: .barrier) {
            self.requestTimestamps.append(Date())
        }
    }
    
    /// Returns the number of seconds until the next request can be made
    func timeUntilNextRequest() -> TimeInterval {
        return rateLimitQueue.sync {
            guard !requestTimestamps.isEmpty else { return 0 }
            
            let sortedTimestamps = requestTimestamps.sorted()
            let oldestInWindow = sortedTimestamps.first!
            let windowStart = oldestInWindow.addingTimeInterval(JoyaFixConstants.rateLimitWindow)
            let now = Date()
            
            return max(0, windowStart.timeIntervalSince(now))
        }
    }
    
    /// Returns the number of requests made in the current window
    var currentRequestCount: Int {
        return rateLimitQueue.sync {
            let now = Date()
            let windowStart = now.addingTimeInterval(-JoyaFixConstants.rateLimitWindow)
            requestTimestamps.removeAll { $0 < windowStart }
            return requestTimestamps.count
        }
    }
}

