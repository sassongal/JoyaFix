import XCTest
@testable import JoyaFix

final class SnippetManagerTests: XCTestCase {
    
    var snippetManager: SnippetManager!
    
    override func setUp() {
        super.setUp()
        snippetManager = SnippetManager.shared
        // Clear existing snippets for clean test
        clearSnippets()
    }
    
    override func tearDown() {
        clearSnippets()
        snippetManager = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func clearSnippets() {
        // Get all snippets and delete them
        let allSnippets = snippetManager.snippets
        for snippet in allSnippets {
            snippetManager.removeSnippet(snippet)
        }
    }
    
    // MARK: - CRUD Tests
    
    func testAddSnippet_ValidSnippet_AddsToManager() {
        let snippet = Snippet(trigger: "!test", content: "Test content")
        snippetManager.addSnippet(snippet)
        
        let snippets = snippetManager.snippets
        XCTAssertTrue(snippets.contains { $0.trigger == "!test" }, "Snippet should be added")
    }
    
    func testAddSnippet_InvalidTrigger_DoesNotAdd() {
        // Trigger too short
        let snippet = Snippet(trigger: "!", content: "Test content")
        snippetManager.addSnippet(snippet)
        
        // Note: The actual implementation might return false or throw, but here we check state
        // Assuming validation happens inside addSnippet
        let snippets = snippetManager.snippets
        // Use a small delay as saving might be async or validation logic might prevent addition
        XCTAssertFalse(snippets.contains { $0.trigger == "!" }, "Invalid snippet should not be added")
    }
    
    func testDeleteSnippet_ExistingSnippet_RemovesFromManager() {
        let snippet = Snippet(trigger: "!delete", content: "Delete me")
        snippetManager.addSnippet(snippet)
        
        let allSnippets = snippetManager.snippets
        guard let snippetToDelete = allSnippets.first(where: { $0.trigger == "!delete" }) else {
            XCTFail("Snippet should exist")
            return
        }
        
        snippetManager.removeSnippet(snippetToDelete)
        
        let updatedSnippets = snippetManager.snippets
        XCTAssertFalse(updatedSnippets.contains { $0.trigger == "!delete" }, "Snippet should be deleted")
    }
    
    func testUpdateSnippet_ExistingSnippet_UpdatesContent() {
        let snippet = Snippet(trigger: "!update", content: "Original")
        snippetManager.addSnippet(snippet)
        
        let allSnippets = snippetManager.snippets
        guard let snippetToUpdate = allSnippets.first(where: { $0.trigger == "!update" }) else {
            XCTFail("Snippet should exist")
            return
        }
        
        var updatedSnippet = snippetToUpdate
        updatedSnippet.content = "Updated"
        snippetManager.updateSnippet(updatedSnippet)
        
        let updatedSnippets = snippetManager.snippets
        let found = updatedSnippets.first { $0.trigger == "!update" }
        XCTAssertEqual(found?.content, "Updated", "Snippet content should be updated")
    }
    
    // MARK: - Validation Tests
    
    func testValidateSnippet_EmptyTrigger_ReturnsFalse() {
        let snippet = Snippet(trigger: "", content: "Content")
        snippetManager.addSnippet(snippet)
        
        let snippets = snippetManager.snippets
        XCTAssertFalse(snippets.contains { $0.trigger == "" }, "Empty trigger should be rejected")
    }
    
    func testValidateSnippet_TriggerTooShort_ReturnsFalse() {
        let snippet = Snippet(trigger: "!", content: "Content")
        snippetManager.addSnippet(snippet)
        
        let snippets = snippetManager.snippets
        XCTAssertFalse(snippets.contains { $0.trigger == "!" }, "Short trigger should be rejected")
    }
    
    func testValidateSnippet_TriggerTooLong_ReturnsFalse() {
        let longTrigger = String(repeating: "a", count: 21) // Max is 20
        let snippet = Snippet(trigger: longTrigger, content: "Content")
        snippetManager.addSnippet(snippet)
        
        let snippets = snippetManager.snippets
        XCTAssertFalse(snippets.contains { $0.trigger == longTrigger }, "Long trigger should be rejected")
    }
    
    func testValidateSnippet_EmptyContent_ReturnsFalse() {
        let snippet = Snippet(trigger: "!test", content: "")
        snippetManager.addSnippet(snippet)
        
        let snippets = snippetManager.snippets
        XCTAssertFalse(snippets.contains { $0.trigger == "!test" }, "Empty content should be rejected")
    }
    
    // MARK: - Trigger Tests
    
    func testGetAllTriggers_ReturnsAllTriggers() {
        snippetManager.addSnippet(Snippet(trigger: "!test1", content: "Content 1"))
        snippetManager.addSnippet(Snippet(trigger: "!test2", content: "Content 2"))
        
        let triggers = snippetManager.snippets.map { $0.trigger }
        XCTAssertTrue(triggers.contains("!test1"), "Should contain first trigger")
        XCTAssertTrue(triggers.contains("!test2"), "Should contain second trigger")
    }
    
    func testGetSnippet_ExistingTrigger_ReturnsSnippet() {
        let snippet = Snippet(trigger: "!find", content: "Find me")
        snippetManager.addSnippet(snippet)
        
        let found = snippetManager.snippets.first(where: { $0.trigger == "!find" })
        XCTAssertNotNil(found, "Should find snippet by trigger")
        XCTAssertEqual(found?.content, "Find me", "Should return correct snippet")
    }
    
    func testGetSnippet_NonExistentTrigger_ReturnsNil() {
        let found = snippetManager.snippets.first(where: { $0.trigger == "!nonexistent" })
        XCTAssertNil(found, "Should return nil for non-existent trigger")
    }
}

