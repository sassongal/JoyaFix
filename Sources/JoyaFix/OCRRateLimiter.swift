#if false
import Foundation

@MainActor
class OCRRateLimiter {
    static let shared = OCRRateLimiter()
    private init() {}
    
    var currentRequestCount: Int { 0 }
    
    func canMakeRequest() -> Bool { true }
    func recordRequest() {}
    func timeUntilNextRequest() -> TimeInterval { 0 }
}
#endif
