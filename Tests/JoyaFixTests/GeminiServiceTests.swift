import XCTest
@testable import JoyaFix

@MainActor
final class GeminiServiceTests: XCTestCase {
    
    var geminiService: GeminiService!
    
    override func setUp() {
        super.setUp()
        geminiService = GeminiService.shared
    }
    
    override func tearDown() {
        geminiService = nil
        super.tearDown()
    }
    
    // MARK: - URL Construction Tests
    
    func testURLConstructionWithAPIKey() {
        // This test verifies that URLComponents is used correctly
        // We can't test the actual API call without a valid key, but we can test URL construction
        
        let baseURL = JoyaFixConstants.API.geminiBaseURL
        guard var urlComponents = URLComponents(string: baseURL) else {
            XCTFail("Failed to create URLComponents from base URL")
            return
        }
        
        let testAPIKey = "test_api_key_12345"
        urlComponents.queryItems = [URLQueryItem(name: "key", value: testAPIKey)]
        
        guard let url = urlComponents.url else {
            XCTFail("Failed to construct URL from components")
            return
        }
        
        // Verify URL contains the key
        XCTAssertTrue(url.absoluteString.contains("key=\(testAPIKey)"), "URL should contain API key")
        XCTAssertTrue(url.absoluteString.contains(baseURL), "URL should contain base URL")
    }
    
    func testURLConstructionWithoutAPIKey() {
        let baseURL = JoyaFixConstants.API.geminiBaseURL
        guard let urlComponents = URLComponents(string: baseURL),
              let url = urlComponents.url else {
            XCTFail("Failed to create URL from base URL")
            return
        }
        
        // Verify URL doesn't contain key parameter
        XCTAssertFalse(url.absoluteString.contains("key="), "URL should not contain key parameter when not set")
    }
    
    // MARK: - Error Handling Tests
    
    func testGeminiServiceErrorDescriptions() {
        let apiKeyError = GeminiServiceError.apiKeyNotFound
        XCTAssertNotNil(apiKeyError.errorDescription, "Error should have description")
        XCTAssertTrue(apiKeyError.errorDescription?.contains("API key") ?? false, "Error description should mention API key")
        
        let networkError = GeminiServiceError.networkError(NSError(domain: "test", code: -1))
        XCTAssertNotNil(networkError.errorDescription, "Network error should have description")
        
        let httpError = GeminiServiceError.httpError(404, "Not Found")
        XCTAssertNotNil(httpError.errorDescription, "HTTP error should have description")
        XCTAssertTrue(httpError.errorDescription?.contains("404") ?? false, "Error description should contain status code")
    }
    
    // MARK: - Backward Compatibility Tests
    
    func testLegacyAPICompatibility() {
        // Test that legacy String? API still works
        let expectation = XCTestExpectation(description: "Legacy completion called")
        
        // This will fail without a valid API key, but we're testing the API signature
        geminiService.sendPrompt("test") { (result: String?) in
            // Legacy API returns String?
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
}

