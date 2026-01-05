import XCTest
@testable import JoyaFix

final class ClipboardHistoryManagerTests: XCTestCase {

    var historyManager: ClipboardHistoryManager!
    var settingsManager: SettingsManager!

    // This method is called before the invocation of each test method in the class.
    @MainActor
    override func setUp() {
        super.setUp()
        // Use a shared instance for settings to control max history
        settingsManager = SettingsManager.shared
        historyManager = ClipboardHistoryManager.shared
        
        // Ensure history is clean before each test
        historyManager.clearHistory(keepPinned: false)
    }

    // This method is called after the invocation of each test method in the class.
    @MainActor
    override func tearDown() {
        // Clean up after each test
        historyManager.clearHistory(keepPinned: false)
        historyManager = nil
        settingsManager = nil
        super.tearDown()
    }

    // Test basic item addition
    @MainActor
    func testAddItem_AddsItemToHistory() {
        let item = ClipboardItem(text: "Hello, World!", timestamp: Date())
        historyManager.addToHistory(item)
        
        XCTAssertEqual(historyManager.history.count, 1)
        XCTAssertEqual(historyManager.history.first?.textForPasting, "Hello, World!")
    }

    // Test that adding a duplicate item replaces the old one
    @MainActor
    func testAddDuplicateItem_ReplacesOldItem() {
        let originalDate = Date()
        let item1 = ClipboardItem(text: "Unique Text", timestamp: originalDate)
        historyManager.addToHistory(item1)
        
        XCTAssertEqual(historyManager.history.count, 1)
        XCTAssertEqual(historyManager.history.first?.timestamp, originalDate)

        // Add the same item again, it should move to the top (and replace the old one)
        let newDate = Date().addingTimeInterval(10)
        let item2 = ClipboardItem(text: "Unique Text", timestamp: newDate)
        historyManager.addToHistory(item2)
        
        XCTAssertEqual(historyManager.history.count, 1, "History count should remain 1 after adding a duplicate.")
        XCTAssertEqual(historyManager.history.first?.timestamp, newDate, "The newer item should be at the top.")
    }

    // Test history limit enforcement
    @MainActor
    func testHistoryLimit_RemovesOldestItem() {
        // Set a specific limit for this test
        let maxHistory = 5
        settingsManager.maxHistoryCount = maxHistory
        
        // Add items up to the limit + 2
        for i in 0..<maxHistory + 2 {
            let item = ClipboardItem(text: "Item \(i)", timestamp: Date())
            historyManager.addToHistory(item)
        }
        
        // The history count should not exceed the max limit
        XCTAssertEqual(historyManager.history.count, maxHistory)
        
        // The first items added ("Item 0", "Item 1") should have been removed
        let itemTexts = historyManager.history.map { $0.textForPasting }
        XCTAssertFalse(itemTexts.contains("Item 0"))
        XCTAssertFalse(itemTexts.contains("Item 1"))
        
        // The last item added should be at the top
        XCTAssertEqual(historyManager.history.first?.textForPasting, "Item \(maxHistory + 1)")
    }

    // Test clearing the history
    @MainActor
    func testClearHistory_RemovesAllItems() {
        historyManager.addToHistory(ClipboardItem(text: "Item 1", timestamp: Date()))
        historyManager.addToHistory(ClipboardItem(text: "Item 2", timestamp: Date()))
        
        XCTAssertEqual(historyManager.history.count, 2)
        
        historyManager.clearHistory(keepPinned: false)
        
        XCTAssertEqual(historyManager.history.count, 0)
    }

    // Test that pinned items are not removed when clearing history (if specified)
    @MainActor
    func testPinning_KeepsItemWhenClearingHistory() {
        let pinnedItem = ClipboardItem(text: "Pinned Item", timestamp: Date())
        let unpinnedItem = ClipboardItem(text: "Unpinned Item", timestamp: Date())
        
        historyManager.addToHistory(pinnedItem)
        historyManager.addToHistory(unpinnedItem)
        
        // Pin the first item
        if let itemToPin = historyManager.history.first(where: { $0.textForPasting == "Pinned Item" }) {
            historyManager.togglePin(for: itemToPin)
        }
        
        XCTAssertEqual(historyManager.history.count, 2)
        
        // Clear history but keep pinned items
        historyManager.clearHistory(keepPinned: true)
        
        XCTAssertEqual(historyManager.history.count, 1, "Only the pinned item should remain.")
        XCTAssertEqual(historyManager.history.first?.textForPasting, "Pinned Item")
        XCTAssertTrue(historyManager.history.first?.isPinned ?? false)
    }
    
    @MainActor
    func testPinning_DoesNotCountTowardsHistoryLimit() {
        let maxHistory = 3
        settingsManager.maxHistoryCount = maxHistory
        
        // Add a pinned item
        let pinnedItem = ClipboardItem(text: "I am Pinned", timestamp: Date())
        historyManager.addToHistory(pinnedItem)
        if let itemToPin = historyManager.history.first(where: { $0.textForPasting == "I am Pinned" }) {
            historyManager.togglePin(for: itemToPin)
        }
        
        // Now add `maxHistory` + 1 unpinned items
        for i in 0...maxHistory {
            let item = ClipboardItem(text: "Item \(i)", timestamp: Date())
            historyManager.addToHistory(item)
        }
        
        // Total history should be maxHistory (unpinned) + 1 (pinned)
        XCTAssertEqual(historyManager.history.count, maxHistory + 1)
        
        // Check that the pinned item is still there
        XCTAssertTrue(historyManager.history.contains(where: { $0.textForPasting == "I am Pinned" && $0.isPinned }))
        
        // Check that the oldest unpinned item ("Item 0") was removed
        XCTAssertFalse(historyManager.history.contains(where: { $0.textForPasting == "Item 0" }))
    }
}
