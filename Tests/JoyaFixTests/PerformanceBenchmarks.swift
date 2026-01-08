import XCTest
@testable import JoyaFix
import CoreGraphics

#if false

/// Performance benchmarks for critical operations
@MainActor
final class PerformanceBenchmarks: XCTestCase {
    
    var ocrService: OCRService!
    var clipboardManager: ClipboardHistoryManager!
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
        clipboardManager = ClipboardHistoryManager.shared
    }
    
    override func tearDown() {
        ocrService.clearCache()
        ocrService = nil
        clipboardManager = nil
        geminiService = nil
        settingsManager = nil
        super.tearDown()
    }
    
#if false
    // MARK: - OCR Performance Benchmarks
    
    /// Benchmarks OCR extraction performance
    func testOCRExtraction_Performance() {
        let testImage = createTestImage(width: 800, height: 600)
        
        measure {
            let expectation = XCTestExpectation(description: "OCR")
            ocrService.extractText(from: testImage) { _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    /// Benchmarks OCR with small image
    func testOCRExtraction_SmallImage_Performance() {
        let smallImage = createTestImage(width: 200, height: 200)
        
        measure {
            let expectation = XCTestExpectation(description: "OCR small")
            ocrService.extractText(from: smallImage) { _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    /// Benchmarks OCR with large image
    func testOCRExtraction_LargeImage_Performance() {
        let largeImage = createTestImage(width: 2000, height: 1500)
        
        measure {
            let expectation = XCTestExpectation(description: "OCR large")
            ocrService.extractText(from: largeImage) { _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 15.0)
        }
    }
    
    /// Benchmarks OCR cache performance
    func testOCRCache_Performance() {
        let testImage = createTestImage(width: 400, height: 400)
        
        // First extraction (no cache)
        let expectation1 = XCTestExpectation(description: "OCR first")
        ocrService.extractText(from: testImage) { _ in
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 10.0)
        
        // Second extraction (should use cache)
        measure {
            let expectation2 = XCTestExpectation(description: "OCR cached")
            ocrService.extractText(from: testImage) { _ in
                expectation2.fulfill()
            }
            wait(for: [expectation2], timeout: 10.0)
        }
    }
#endif
    
    // MARK: - Clipboard Performance Benchmarks
    
    /// Benchmarks clipboard history addition
    func testClipboardHistory_AddItem_Performance() {
        let item = ClipboardItem(text: "Performance test item", timestamp: Date())
        
        measure {
            clipboardManager.addToHistory(item)
        }
    }
    
    /// Benchmarks clipboard history retrieval
    func testClipboardHistory_Retrieve_Performance() {
        // Add some items first
        for i in 0..<10 {
            let item = ClipboardItem(text: "Item \(i)", timestamp: Date())
            clipboardManager.addToHistory(item)
        }
        
        measure {
            _ = clipboardManager.history
        }
    }
    
    /// Benchmarks clipboard deduplication
    func testClipboardHistory_Deduplication_Performance() {
        let item = ClipboardItem(text: "Duplicate test", timestamp: Date())
        
        measure {
            clipboardManager.addToHistory(item)
            clipboardManager.addToHistory(item) // Duplicate
        }
    }
    
    // MARK: - Text Conversion Performance Benchmarks
    
    /// Benchmarks English to Hebrew conversion
    func testTextConversion_EnglishToHebrew_Performance() {
        let text = String(repeating: "hello world ", count: 100)
        
        measure {
            _ = TextConverter.convertToHebrew(text)
        }
    }
    
    /// Benchmarks Hebrew to English conversion
    func testTextConversion_HebrewToEnglish_Performance() {
        let text = String(repeating: "שלום עולם ", count: 100)
        
        measure {
            _ = TextConverter.convertToEnglish(text)
        }
    }
    
#if false
    // MARK: - Rate Limiter Performance Benchmarks
    
    /// Benchmarks rate limiter check
    func testRateLimiter_Check_Performance() {
        let rateLimiter = OCRRateLimiter.shared
        
        measure {
            _ = rateLimiter.canMakeRequest()
        }
    }
    
    /// Benchmarks rate limiter record
    func testRateLimiter_Record_Performance() {
        let rateLimiter = OCRRateLimiter.shared
        
        measure {
            rateLimiter.recordRequest()
        }
    }
#endif
    
    // MARK: - Keychain Performance Benchmarks
    
    /// Benchmarks Keychain store operation
    func testKeychain_Store_Performance() {
        let testKey = "perf_test_key_\(UUID().uuidString)"
        let testValue = "Performance test value"
        
        measure {
            _ = try? KeychainHelper.store(key: testKey, value: testValue)
        }
        
        // Cleanup
        _ = try? KeychainHelper.delete(key: testKey)
    }
    
    /// Benchmarks Keychain retrieve operation
    func testKeychain_Retrieve_Performance() {
        let testKey = "perf_test_key_\(UUID().uuidString)"
        let testValue = "Performance test value"
        
        _ = try? KeychainHelper.store(key: testKey, value: testValue)
        
        measure {
            _ = try? KeychainHelper.retrieve(key: testKey)
        }
        
        // Cleanup
        _ = try? KeychainHelper.delete(key: testKey)
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
        
        // Add text-like pattern
        context.setFillColor(CGColor.black)
        for i in 0..<10 {
            let y = height / 2 + (i - 5) * 20
            context.fill(CGRect(x: 50, y: y, width: width - 100, height: 15))
        }
        
        guard let image = context.makeImage() else {
            fatalError("Failed to create CGImage")
        }
        
        return image
    }
}
#endif


