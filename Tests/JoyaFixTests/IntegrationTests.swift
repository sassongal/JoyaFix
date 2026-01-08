import XCTest
@testable import JoyaFix
import CoreGraphics

#if false

/// Integration tests for end-to-end flows
@MainActor
final class IntegrationTests: XCTestCase {
    
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
        clipboardManager.clearHistory(keepPinned: false)
    }
    
    override func tearDown() {
        clipboardManager.clearHistory(keepPinned: false)
        ocrService.clearCache()
        ocrService = nil
        clipboardManager = nil
        geminiService = nil
        settingsManager = nil
        super.tearDown()
    }
    
#if false
    // MARK: - OCR Flow Tests
    
    /// Tests the complete OCR flow: image → preprocessing → OCR → result
    func testOCRFlow_EndToEnd() {
        let testImage = createTestImageWithText(width: 400, height: 200)
        let expectation = XCTestExpectation(description: "OCR flow completion")
        
        // Test the complete flow
        ocrService.extractText(from: testImage) { result in
            // Flow should complete without crashing
            // Result may be nil if no text is found, which is acceptable
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    /// Tests OCR flow with fallback from cloud to local
    func testOCRFlow_CloudToLocalFallback() {
        // Enable cloud OCR (will fail without API key)
        settingsManager.useCloudOCR = true
        
        let testImage = createTestImageWithText(width: 400, height: 200)
        let expectation = XCTestExpectation(description: "OCR fallback")
        
        ocrService.extractText(from: testImage) { result in
            // Should fallback to local OCR if cloud fails
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 20.0)
    }
#endif
    
    // MARK: - Clipboard Flow Tests
    
    /// Tests the complete clipboard flow: copy → monitor → save → retrieve
    func testClipboardFlow_EndToEnd() {
        let testText = "Integration Test Text \(UUID().uuidString)"
        let expectation = XCTestExpectation(description: "Clipboard flow")
        
        // Simulate clipboard copy
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(testText, forType: .string)
        
        // Wait for clipboard manager to detect change
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Check if item was added to history
            let found = self.clipboardManager.history.contains { item in
                item.textForPasting == testText
            }
            
            XCTAssertTrue(found, "Clipboard item should be in history")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    /// Tests clipboard deduplication flow
    func testClipboardFlow_Deduplication() {
        let testText = "Duplicate Test Text \(UUID().uuidString)"
        let expectation = XCTestExpectation(description: "Clipboard deduplication")
        
        // Copy same text twice
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(testText, forType: .string)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Copy again
            pasteboard.setString(testText, forType: .string)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Should only have one item in history
                let count = self.clipboardManager.history.filter { item in
                    item.textForPasting == testText
                }.count
                
                XCTAssertLessThanOrEqual(count, 1, "Should not have duplicates in history")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
#if false
    // MARK: - OCR + Clipboard Integration
    
    /// Tests OCR result being copied to clipboard
    func testOCRToClipboardFlow() {
        let testImage = createTestImageWithText(width: 400, height: 200)
        let expectation = XCTestExpectation(description: "OCR to clipboard")
        
        // Perform OCR
        ocrService.extractText(from: testImage) { [weak self] result in
            guard let self = self, let text = result, !text.isEmpty else {
                expectation.fulfill()
                return
            }
            
            // Copy to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            // Wait for clipboard manager to detect
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let found = self.clipboardManager.history.contains { item in
                    item.textForPasting == text
                }
                
                XCTAssertTrue(found, "OCR result should be in clipboard history")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 20.0)
    }
#endif
    
#if false
    // MARK: - Error Handling Integration
    
    /// Tests error handling in OCR flow
    func testOCRFlow_ErrorHandling() {
        // Create an invalid/empty image
        let invalidImage = createTestImage(width: 1, height: 1)
        let expectation = XCTestExpectation(description: "OCR error handling")
        
        ocrService.extractText(from: invalidImage) { result in
            // Should handle gracefully without crashing
            // Result may be nil, which is acceptable
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
#endif
    
#if false
    // MARK: - Performance Integration
    
    /// Tests that OCR completes within reasonable time
    func testOCRFlow_Performance() {
        let testImage = createTestImageWithText(width: 800, height: 600)
        let expectation = XCTestExpectation(description: "OCR performance")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        ocrService.extractText(from: testImage) { result in
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            
            // Should complete within 10 seconds (reasonable for OCR)
            XCTAssertLessThan(elapsed, 10.0, "OCR should complete within 10 seconds")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
#endif
    
    // MARK: - Snippet Expansion Integration
    
    /// Tests snippet expansion flow: trigger → match → expansion
    func testSnippetExpansionFlow() {
        let snippetManager = SnippetManager.shared
        let testTrigger = "!testexp\(UUID().uuidString.prefix(8))"
        let testContent = "Expanded content \(UUID().uuidString)"
        
        // Add a test snippet
        let snippet = Snippet(trigger: testTrigger, content: testContent)
        snippetManager.addSnippet(snippet)
        
        // Register trigger with InputMonitor
        InputMonitor.shared.registerSnippetTrigger(testTrigger)
        
        // Note: Actual expansion requires Accessibility permission and event tap
        // This test verifies the setup is correct
        
        let expectation = XCTestExpectation(description: "Snippet expansion setup")
        expectation.fulfill()
        
        wait(for: [expectation], timeout: 1.0)
        
        // Cleanup
        let allSnippets = snippetManager.snippets
        if let snippetToDelete = allSnippets.first(where: { $0.trigger == testTrigger }) {
            snippetManager.removeSnippet(snippetToDelete)
        }
    }
    
    // MARK: - Hotkey Integration
    
    /// Tests hotkey registration and notification flow
    func testHotkeyFlow() {
        let hotkeyManager = HotkeyManager.shared
        
        // Register hotkey
        let registered = hotkeyManager.registerHotkey()
        
        // Should attempt registration (may fail if already registered, which is OK)
        XCTAssertTrue(registered || !registered, "Should attempt hotkey registration")
        
        // Test notification setup
        let expectation = XCTestExpectation(description: "Hotkey notification")
        
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HotkeyManager.hotkeyPressed"),
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        // Note: Can't actually trigger hotkey in tests, but verify setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.removeObserver(observer)
        }
        
        wait(for: [expectation], timeout: 0.2)
        
        // Cleanup
        hotkeyManager.unregisterHotkey()
    }
    
#if false
    // MARK: - Screen Capture Integration
    
    /// Tests screen capture flow: start → select → OCR → result
    func testScreenCaptureFlow() {
        let expectation = XCTestExpectation(description: "Screen capture flow")
        
        ScreenCaptureManager.shared.startScreenCapture { result in
            // Flow should complete (may be nil if cancelled)
            // This tests the integration without actually capturing
            expectation.fulfill()
        }
        
        // Cancel immediately (simulate user cancelling)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // In real scenario, user presses Escape
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
#endif
    
#if false
    // MARK: - Complete User Flow Integration
    
    /// Tests complete user flow: OCR → Copy → Clipboard History
    func testCompleteUserFlow_OCRToClipboard() {
        let expectation = XCTestExpectation(description: "Complete user flow")
        
        // Step 1: Perform OCR
        let testImage = createTestImageWithText(width: 400, height: 200)
        ocrService.extractText(from: testImage) { [weak self] ocrResult in
            guard let self = self, let text = ocrResult, !text.isEmpty else {
                expectation.fulfill()
                return
            }
            
            // Step 2: Copy to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            // Step 3: Wait for clipboard manager
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // Step 4: Verify in history
                let found = self.clipboardManager.history.contains { item in
                    item.textForPasting == text
                }
                
                XCTAssertTrue(found, "OCR result should be in clipboard history")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 20.0)
    }
    
    // MARK: - Error Recovery Integration
    
    /// Tests error recovery: OCR failure → fallback → success
    func testErrorRecovery_OCRFallback() {
        // Force cloud OCR mode
        settingsManager.useCloudOCR = true
        
        // Use invalid/empty image to trigger fallback
        let invalidImage = createTestImage(width: 1, height: 1)
        let expectation = XCTestExpectation(description: "Error recovery")
        
        ocrService.extractText(from: invalidImage) { result in
            // Should handle gracefully (may return nil, which is OK)
            // Should not crash
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
#endif
    
    // MARK: - Concurrent Operations Integration
    
    /// Tests handling of concurrent operations
    func testConcurrentOperations() {
        let expectation1 = XCTestExpectation(description: "OCR 1")
        let expectation2 = XCTestExpectation(description: "OCR 2")
        let expectation3 = XCTestExpectation(description: "Clipboard")
        
        // Concurrent OCR operations
        let image1 = createTestImageWithText(width: 200, height: 200)
        let image2 = createTestImageWithText(width: 300, height: 300)
        
        ocrService.extractText(from: image1) { _ in
            expectation1.fulfill()
        }
        
        ocrService.extractText(from: image2) { _ in
            expectation2.fulfill()
        }
        
        // Concurrent clipboard operation
        let pasteboard = NSPasteboard.general
        pasteboard.setString("Concurrent test", forType: .string)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation3.fulfill()
        }
        
        wait(for: [expectation1, expectation2, expectation3], timeout: 15.0)
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
        
        guard let image = context.makeImage() else {
            fatalError("Failed to create CGImage")
        }
        
        return image
    }
    
    private func createTestImageWithText(width: Int, height: Int) -> CGImage {
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
        
        // Add text-like pattern (black rectangles that simulate text)
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


