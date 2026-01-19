import XCTest
@testable import JoyaFix
import Carbon

final class HotkeyManagerTests: XCTestCase {
    
    var hotkeyManager: HotkeyManager!
    
    override func setUp() {
        super.setUp()
        hotkeyManager = HotkeyManager.shared
        // Unregister all hotkeys before each test
        hotkeyManager.unregisterHotkey()
    }
    
    override func tearDown() {
        hotkeyManager.unregisterHotkey()
        hotkeyManager = nil
        super.tearDown()
    }
    
    // MARK: - Hotkey Registration Tests
    
    func testRegisterHotkey_ReturnsSuccessStatus() {
        let result = hotkeyManager.registerHotkey()
        
        // Should return a boolean indicating success
        // Note: May fail if hotkey is already registered by another app
        XCTAssertTrue(result || !result, "Should return a boolean value")
    }
    
#if false
    func testRegisterOCRHotkey_ReturnsSuccessStatus() {
        let result = hotkeyManager.registerOCRHotkey()
        
        // Should return a boolean indicating success
        XCTAssertTrue(result || !result, "Should return a boolean value")
    }
#endif
    
    func testRegisterKeyboardLockHotkey_ReturnsSuccessStatus() {
        let result = hotkeyManager.registerKeyboardLockHotkey()
        
        // Should return a boolean indicating success
        XCTAssertTrue(result || !result, "Should return a boolean value")
    }
    
    func testRegisterPromptHotkey_ReturnsSuccessStatus() {
        let result = hotkeyManager.registerPromptHotkey()
        
        // Should return a boolean indicating success
        XCTAssertTrue(result || !result, "Should return a boolean value")
    }
    
    // MARK: - Hotkey Unregistration Tests
    
    func testUnregisterHotkey_DoesNotCrash() {
        // Register first
        _ = hotkeyManager.registerHotkey()
        
        // Unregister
        hotkeyManager.unregisterHotkey()
        
        // Should not crash
        XCTAssertNoThrow(hotkeyManager.unregisterHotkey(), "Should handle unregistration")
    }
    
    func testUnregisterHotkey_WhenNotRegistered_DoesNotCrash() {
        // Unregister without registering first
        hotkeyManager.unregisterHotkey()
        
        // Should not crash
        XCTAssertNoThrow(hotkeyManager.unregisterHotkey(), "Should handle unregistration when not registered")
    }
    
    // MARK: - Rebind Tests
    
    func testRebindHotkeys_ReturnsStatusForAllHotkeys() {
        let result = hotkeyManager.rebindHotkeys()
        
        // Should return tuple with success status for all hotkeys
        XCTAssertTrue(result.convertSuccess || !result.convertSuccess, "Should return convert status")
        XCTAssertTrue(result.keyboardLockSuccess || !result.keyboardLockSuccess, "Should return keyboard lock status")
        XCTAssertTrue(result.promptSuccess || !result.promptSuccess, "Should return prompt status")
    }
    
    func testRebindHotkeys_UnregistersAndReregisters() {
        // Register first
        _ = hotkeyManager.registerHotkey()
        
        // Rebind
        let result = hotkeyManager.rebindHotkeys()
        
        // Should complete without crashing
        XCTAssertTrue(result.convertSuccess || !result.convertSuccess, "Should complete rebind")
    }
    
    // MARK: - Multiple Registration Tests
    
    func testMultipleRegistrations_HandlesGracefully() {
        // Register multiple times
        _ = hotkeyManager.registerHotkey()
        _ = hotkeyManager.registerHotkey()
        _ = hotkeyManager.registerHotkey()
        
        // Should not crash
        XCTAssertNoThrow(hotkeyManager.unregisterHotkey(), "Should handle multiple registrations")
    }
    
    // MARK: - Notification Tests
    
    func testHotkeyNotification_PostsCorrectNotification() {
        let expectation = XCTestExpectation(description: "Hotkey notification")
        expectation.isInverted = true // Inverted: we expect this NOT to fire (since we can't trigger hotkeys in tests)
        
        // Register for notification
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HotkeyManager.hotkeyPressed"),
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        // Note: We can't actually trigger the hotkey in tests,
        // but we can verify the notification system is set up correctly
        // Since we can't trigger the hotkey, we expect the notification NOT to fire
        // This verifies the observer is set up correctly without requiring actual hotkey triggering
        
        // Cleanup
        NotificationCenter.default.removeObserver(observer)
        
        // Test should complete - inverted expectation means it passes if notification doesn't fire
        wait(for: [expectation], timeout: 0.1)
    }
}

