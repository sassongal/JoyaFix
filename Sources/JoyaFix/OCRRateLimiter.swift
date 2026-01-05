import Foundation

/// Manages rate limiting for Cloud OCR API calls
@MainActor
class OCRRateLimiter {
    static let shared = OCRRateLimiter()
    
    private var requestTimestamps: [Date] = []
    // No DispatchQueue needed - @MainActor already provides synchronization
    
    private init() {}
    
    /// Checks if a new request can be made based on rate limits
    func canMakeRequest() -> Bool {
        let now = Date()
        let windowStart = now.addingTimeInterval(-JoyaFixConstants.rateLimitWindow)
        
        // Remove timestamps outside the window
        requestTimestamps.removeAll { $0 < windowStart }
        
        // Check if we're under the limit
        return requestTimestamps.count < JoyaFixConstants.maxCloudOCRRequestsPerMinute
    }
    
    /// Records a new request timestamp
    func recordRequest() {
        self.requestTimestamps.append(Date())
    }
    
    /// Returns the number of seconds until the next request can be made
    func timeUntilNextRequest() -> TimeInterval {
        guard !requestTimestamps.isEmpty else { return 0 }
        
        let sortedTimestamps = requestTimestamps.sorted()
        let oldestInWindow = sortedTimestamps.first!
        let windowStart = oldestInWindow.addingTimeInterval(JoyaFixConstants.rateLimitWindow)
        let now = Date()
        
        return max(0, windowStart.timeIntervalSince(now))
    }
    
    /// Returns the number of requests made in the current window
    var currentRequestCount: Int {
        let now = Date()
        let windowStart = now.addingTimeInterval(-JoyaFixConstants.rateLimitWindow)
        requestTimestamps.removeAll { $0 < windowStart }
        return requestTimestamps.count
    }
}

