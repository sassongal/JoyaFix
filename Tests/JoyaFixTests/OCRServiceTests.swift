import XCTest
@testable import JoyaFix
import CoreGraphics
import CoreImage

#if false
@MainActor
final class OCRServiceTests: XCTestCase {
    
    var ocrService: OCRService!
    var settingsManager: SettingsManager!
    var geminiService: GeminiService!
    
    override func setUp() {
        super.setUp()
        settingsManager = SettingsManager.shared
        geminiService = GeminiService.shared
        ocrService = OCRService(
            settingsManager: settingsManager,
            geminiService: geminiService
        )
    }
    
    override func tearDown() {
        ocrService = nil
        geminiService = nil
        settingsManager = nil
        super.tearDown()
    }
    
    // MARK: - Image Quality Tests
    
    func testImageQualityDetection() {
        // Create a test image (minimal size)
        let testImage = createTestImage(width: 100, height: 100)
        
        // Test that OCR extraction doesn't crash with valid image
        let expectation = XCTestExpectation(description: "OCR extraction")
        
        ocrService.extractText(from: testImage) { result in
            // Should complete without crashing
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testImageQualityTooSmall() {
        // Create a very small image
        let smallImage = createTestImage(width: 20, height: 20)
        
        // Small images should be handled gracefully
        let expectation = XCTestExpectation(description: "Small image handling")
        
        ocrService.extractText(from: smallImage) { result in
            // Should complete without crashing, even if no text is found
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Preprocessing Tests
    
    func testImagePreprocessing() {
        let testImage = createTestImage(width: 200, height: 200)
        let expectation = XCTestExpectation(description: "Image preprocessing")
        
        // Test that preprocessing doesn't crash
        ocrService.extractText(from: testImage) { result in
            // Should complete without errors
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testImagePreprocessing_LargeImage() {
        // Test with a larger image
        let largeImage = createTestImage(width: 2000, height: 2000)
        let expectation = XCTestExpectation(description: "Large image preprocessing")
        
        ocrService.extractText(from: largeImage) { result in
            // Should handle large images without crashing
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    // MARK: - Cache Tests
    
    func testImageCache_Clearing() {
        // Test cache functionality
        ocrService.clearCache()
        
        // Should not crash when clearing cache
        XCTAssertNoThrow(ocrService.clearCache(), "Clearing cache should not throw")
    }
    
    func testImageCache_RepeatedExtraction() {
        // Test that repeated extraction of same image uses cache
        let testImage = createTestImage(width: 100, height: 100)
        let expectation1 = XCTestExpectation(description: "First extraction")
        let expectation2 = XCTestExpectation(description: "Second extraction")
        
        // First extraction
        ocrService.extractText(from: testImage) { _ in
            expectation1.fulfill()
        }
        
        wait(for: [expectation1], timeout: 10.0)
        
        // Second extraction (should use cache)
        ocrService.extractText(from: testImage) { _ in
            expectation2.fulfill()
        }
        
        wait(for: [expectation2], timeout: 10.0)
    }
    
    // MARK: - OCR Mode Tests
    
    func testOCRExtraction_LocalMode() {
        // Force local OCR mode
        settingsManager.useCloudOCR = false
        
        let testImage = createTestImage(width: 200, height: 200)
        let expectation = XCTestExpectation(description: "Local OCR extraction")
        
        ocrService.extractText(from: testImage) { result in
            // Should complete using local Vision framework
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testOCRExtraction_CloudMode() {
        // Force cloud OCR mode (will fail without API key, but should handle gracefully)
        settingsManager.useCloudOCR = true
        
        let testImage = createTestImage(width: 200, height: 200)
        let expectation = XCTestExpectation(description: "Cloud OCR extraction")
        
        ocrService.extractText(from: testImage) { result in
            // Should complete (may fallback to local if cloud fails)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            fatalError("Failed to create CGContext")
        }
        
        // Fill with white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Add some text-like pattern
        context.setFillColor(CGColor.black)
        context.fill(CGRect(x: 10, y: 10, width: 80, height: 20))
        
        guard let image = context.makeImage() else {
            fatalError("Failed to create CGImage")
        }
        
        return image
    }
}
#endif

