import Foundation
import Combine

/// Manages text snippets for auto-expansion
class SnippetManager: ObservableObject {
    static let shared = SnippetManager()
    
    @Published private(set) var snippets: [Snippet] = []
    
    private let userDefaultsKey = "JoyaFixSnippets"
    
    private init() {
        loadSnippets()
    }
    
    // MARK: - Persistence
    
    private func loadSnippets() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else {
            // Initialize with some default snippets
            snippets = [
                Snippet(trigger: "!mail", content: "gal@joyatech.com"),
                Snippet(trigger: "!sig", content: "Best regards,\nGal Sasson\nJoyaTech")
            ]
            saveSnippets()
            return
        }
        snippets = decoded
    }
    
    private func saveSnippets() {
        if let encoded = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    // MARK: - CRUD Operations
    
    func addSnippet(_ snippet: Snippet) {
        // Validate trigger is unique
        guard !snippets.contains(where: { $0.trigger.lowercased() == snippet.trigger.lowercased() }) else {
            print("⚠️ Snippet with trigger '\(snippet.trigger)' already exists")
            return
        }
        
        snippets.append(snippet)
        saveSnippets()
        print("✓ Added snippet: \(snippet.trigger)")
    }
    
    func updateSnippet(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else {
            print("⚠️ Snippet not found for update")
            return
        }
        
        // Check if trigger is unique (excluding current snippet)
        let isTriggerUnique = !snippets.contains(where: { 
            $0.id != snippet.id && $0.trigger.lowercased() == snippet.trigger.lowercased()
        })
        
        guard isTriggerUnique else {
            print("⚠️ Snippet with trigger '\(snippet.trigger)' already exists")
            return
        }
        
        snippets[index] = snippet
        saveSnippets()
        print("✓ Updated snippet: \(snippet.trigger)")
    }
    
    func removeSnippet(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        saveSnippets()
        print("✓ Removed snippet: \(snippet.trigger)")
    }
    
    func removeSnippet(at index: Int) {
        guard index < snippets.count else { return }
        let snippet = snippets[index]
        removeSnippet(snippet)
    }
    
    // MARK: - Lookup
    
    /// Finds a snippet by its trigger (case-insensitive)
    func findSnippet(trigger: String) -> Snippet? {
        return snippets.first { $0.trigger.lowercased() == trigger.lowercased() }
    }
    
    /// Returns all triggers for quick lookup
    func getAllTriggers() -> [String] {
        return snippets.map { $0.trigger }
    }
}

