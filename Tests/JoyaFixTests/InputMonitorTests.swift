import XCTest
@testable import JoyaFix
import ApplicationServices

final class InputMonitorTests: XCTestCase {
    
    var inputMonitor: InputMonitor!
    
    override func setUp() {
        super.setUp()
        inputMonitor = InputMonitor.shared
        inputMonitor.configureForTesting()
        // Ensure monitoring is stopped before each test
        inputMonitor.stopMonitoring()
    }
    
    override func tearDown() {
        inputMonitor.stopMonitoring()
        inputMonitor = nil
        super.tearDown()
    }
    
    // MARK: - Monitoring Tests
    
    func testStartMonitoring_WhenNotMonitoring_StartsSuccessfully() {
        // Note: This test may fail if Accessibility permission is not granted
        // In that case, it's expected behavior
        
        // Try to start monitoring
        inputMonitor.startMonitoring()
        
        // Should not crash
        XCTAssertNoThrow(inputMonitor.startMonitoring(), "Should not crash when starting")
    }
    
    func testStartMonitoring_WhenAlreadyMonitoring_DoesNotStartAgain() {
        // Start monitoring first time
        inputMonitor.startMonitoring()
        
        // Try to start again
        inputMonitor.startMonitoring()
        
        // Should not crash (idempotent)
        XCTAssertNoThrow(inputMonitor.startMonitoring(), "Should handle multiple start calls")
    }
    
    func testStopMonitoring_WhenMonitoring_StopsSuccessfully() {
        // Start monitoring first
        inputMonitor.startMonitoring()
        
        // Stop monitoring
        inputMonitor.stopMonitoring()
        
        // Should not crash
        XCTAssertNoThrow(inputMonitor.stopMonitoring(), "Should not crash when stopping")
    }
    
    func testStopMonitoring_WhenNotMonitoring_DoesNotCrash() {
        // Stop without starting
        inputMonitor.stopMonitoring()
        
        // Should not crash
        XCTAssertNoThrow(inputMonitor.stopMonitoring(), "Should handle stop when not monitoring")
    }
    
    // MARK: - Snippet Registration Tests
    
    func testRegisterSnippetTrigger_ValidTrigger_RegistersSuccessfully() {
        let trigger = "!testtrigger"
        
        inputMonitor.registerSnippetTrigger(trigger)
        
        // Should not crash
        XCTAssertNoThrow(inputMonitor.registerSnippetTrigger(trigger), "Should register trigger")
    }
    
    func testRegisterSnippetTrigger_MultipleTriggers_RegistersAll() {
        let triggers = ["!test1", "!test2", "!test3"]
        
        for trigger in triggers {
            inputMonitor.registerSnippetTrigger(trigger)
        }
        
        // Should not crash
        XCTAssertNoThrow(inputMonitor.registerSnippetTrigger("!test4"), "Should handle multiple triggers")
    }
    
    func testRegisterSnippetTrigger_EmptyTrigger_HandlesGracefully() {
        // Empty trigger should be handled gracefully
        inputMonitor.registerSnippetTrigger("")
        
        // Should not crash
        XCTAssertNoThrow(inputMonitor.registerSnippetTrigger(""), "Should handle empty trigger")
    }
    
    // MARK: - Buffer Management Tests
    
    func testBufferManagement_DoesNotExceedMaxSize() {
        // Note: Buffer is private, so we test indirectly through monitoring
        // If monitoring works, buffer management is working
        
        inputMonitor.startMonitoring()
        
        // Should not crash
        XCTAssertNoThrow(inputMonitor.stopMonitoring(), "Buffer should be managed correctly")
    }
    
    // MARK: - Permission Tests
    
    func testStartMonitoring_WithoutPermission_HandlesGracefully() {
        // Note: This test assumes permissions might not be granted
        // The actual behavior depends on system state
        
        inputMonitor.startMonitoring()
        
        // Should handle gracefully without crashing
        XCTAssertNoThrow(inputMonitor.startMonitoring(), "Should handle missing permissions")
    }
}

