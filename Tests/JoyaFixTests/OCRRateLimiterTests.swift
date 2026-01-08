import XCTest
@testable import JoyaFix

#if false
@MainActor
final class OCRRateLimiterTests: XCTestCase {
    
    var rateLimiter: OCRRateLimiter!
    
    override func setUp() {
        super.setUp()
        rateLimiter = OCRRateLimiter.shared
        // Clear any existing timestamps
        clearRateLimiter()
    }
    
    override func tearDown() {
        clearRateLimiter()
        rateLimiter = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func clearRateLimiter() {
        // Record requests to fill up the window, then wait for it to expire
        // This is a workaround since we can't directly access private properties
        // In a real scenario, we'd add a test-only reset method
        let maxRequests = JoyaFixConstants.maxCloudOCRRequestsPerMinute
        for _ in 0..<maxRequests {
            rateLimiter.recordRequest()
        }
        // Wait for window to expire
        Thread.sleep(forTimeInterval: JoyaFixConstants.rateLimitWindow + 1)
    }
    
    // MARK: - Rate Limiting Tests
    
    func testCanMakeRequest_WhenUnderLimit_ReturnsTrue() {
        // Initially, should be able to make requests
        XCTAssertTrue(rateLimiter.canMakeRequest(), "Should allow requests when under limit")
    }
    
    func testCanMakeRequest_WhenAtLimit_ReturnsFalse() {
        // Fill up to the limit
        let maxRequests = JoyaFixConstants.maxCloudOCRRequestsPerMinute
        for _ in 0..<maxRequests {
            rateLimiter.recordRequest()
        }
        
        // Should not allow more requests
        XCTAssertFalse(rateLimiter.canMakeRequest(), "Should reject requests when at limit")
    }
    
    func testCanMakeRequest_AfterWindowExpires_ReturnsTrue() {
        // Fill up to the limit
        let maxRequests = JoyaFixConstants.maxCloudOCRRequestsPerMinute
        for _ in 0..<maxRequests {
            rateLimiter.recordRequest()
        }
        
        // Wait for window to expire
        let expectation = XCTestExpectation(description: "Wait for rate limit window")
        DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.rateLimitWindow + 1) {
            XCTAssertTrue(self.rateLimiter.canMakeRequest(), "Should allow requests after window expires")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: JoyaFixConstants.rateLimitWindow + 2)
    }
    
    func testRecordRequest_IncrementsCount() {
        let initialCount = rateLimiter.currentRequestCount
        rateLimiter.recordRequest()
        let newCount = rateLimiter.currentRequestCount
        
        XCTAssertEqual(newCount, initialCount + 1, "Request count should increment")
    }
    
    func testTimeUntilNextRequest_WhenNoRequests_ReturnsZero() {
        clearRateLimiter()
        let waitTime = rateLimiter.timeUntilNextRequest()
        XCTAssertEqual(waitTime, 0, "Should return 0 when no requests")
    }
    
    func testTimeUntilNextRequest_WhenAtLimit_ReturnsPositiveValue() {
        // Fill up to the limit
        let maxRequests = JoyaFixConstants.maxCloudOCRRequestsPerMinute
        for _ in 0..<maxRequests {
            rateLimiter.recordRequest()
        }
        
        let waitTime = rateLimiter.timeUntilNextRequest()
        XCTAssertGreaterThan(waitTime, 0, "Should return positive wait time when at limit")
        XCTAssertLessThanOrEqual(waitTime, JoyaFixConstants.rateLimitWindow, "Wait time should not exceed window")
    }
    
    func testCurrentRequestCount_Accurate() {
        clearRateLimiter()
        
        // Record some requests
        let requestCount = 5
        for _ in 0..<requestCount {
            rateLimiter.recordRequest()
        }
        
        XCTAssertEqual(rateLimiter.currentRequestCount, requestCount, "Request count should be accurate")
    }
    
    func testCurrentRequestCount_RemovesOldRequests() {
        // Record requests
        let maxRequests = JoyaFixConstants.maxCloudOCRRequestsPerMinute
        for _ in 0..<maxRequests {
            rateLimiter.recordRequest()
        }
        
        let initialCount = rateLimiter.currentRequestCount
        XCTAssertEqual(initialCount, maxRequests, "Should have max requests")
        
        // Wait for window to expire
        let expectation = XCTestExpectation(description: "Wait for window expiration")
        DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.rateLimitWindow + 1) {
            let newCount = self.rateLimiter.currentRequestCount
            XCTAssertLessThan(newCount, initialCount, "Should remove old requests after window expires")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: JoyaFixConstants.rateLimitWindow + 2)
    }
}
#endif
