import Foundation
import Combine

/// Manages text snippets for auto-expansion
class SnippetManager: ObservableObject {
    static let shared = SnippetManager()
    
    @Published private(set) var snippets: [Snippet] = []
    
    private let userDefaultsKey = JoyaFixConstants.UserDefaultsKeys.snippets
    
    private init() {
        loadSnippets()
    }
    
    // MARK: - Persistence
    
    private func loadSnippets() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            // Initialize with some default snippets on first run
            print("ℹ️ No snippets found in UserDefaults (first run) - initializing defaults")
            snippets = [
                Snippet(trigger: "!mail", content: "gal@joyatech.com"),
                Snippet(trigger: "!sig", content: "Best regards,\nGal Sasson\nJoyaTech")
            ]
            saveSnippets()
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode([Snippet].self, from: data)
            snippets = decoded
            print("✓ Loaded \(snippets.count) snippets from UserDefaults (\(data.count) bytes)")
            
            // Validate loaded snippets and remove invalid ones
            let validSnippets = snippets.filter { snippet in
                let validation = validateSnippet(snippet)
                if !validation.isValid {
                    print("⚠️ Removing invalid snippet from history: '\(snippet.trigger)' - \(validation.error ?? "Unknown error")")
                }
                return validation.isValid
            }
            
            if validSnippets.count != snippets.count {
                snippets = validSnippets
                saveSnippets()
                print("✓ Cleaned up invalid snippets: \(snippets.count) valid snippets remaining")
            }
        } catch {
            print("❌ Failed to decode snippets: \(error.localizedDescription)")
            print("   Data size: \(data.count) bytes")
            // Reset to default snippets on decode failure
            snippets = [
                Snippet(trigger: "!mail", content: "gal@joyatech.com"),
                Snippet(trigger: "!sig", content: "Best regards,\nGal Sasson\nJoyaTech")
            ]
            saveSnippets()
        }
    }
    
    private func saveSnippets() {
        do {
            let encoded = try JSONEncoder().encode(snippets)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("✓ Snippets saved (\(snippets.count) snippets, \(encoded.count) bytes)")
        } catch {
            print("❌ Failed to save snippets: \(error.localizedDescription)")
            print("   Snippets count: \(snippets.count)")
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Validates a snippet before adding/updating
    private func validateSnippet(_ snippet: Snippet) -> (isValid: Bool, error: String?) {
        // Validate trigger is not empty
        guard !snippet.trigger.isEmpty else {
            return (false, "Snippet trigger cannot be empty")
        }
        
        // Validate trigger length (min 2, max 20 characters)
        guard snippet.trigger.count >= JoyaFixConstants.minSnippetTriggerLength else {
            return (false, "Snippet trigger must be at least \(JoyaFixConstants.minSnippetTriggerLength) characters long")
        }
        
        guard snippet.trigger.count <= JoyaFixConstants.maxSnippetTriggerLength else {
            return (false, "Snippet trigger cannot exceed \(JoyaFixConstants.maxSnippetTriggerLength) characters")
        }
        
        // Validate content is not empty
        guard !snippet.content.isEmpty else {
            return (false, "Snippet content cannot be empty")
        }
        
        // Validate content length (max 10,000 characters to prevent abuse)
        guard snippet.content.count <= JoyaFixConstants.maxSnippetContentLength else {
            return (false, "Snippet content cannot exceed \(JoyaFixConstants.maxSnippetContentLength) characters")
        }
        
        // Validate trigger doesn't contain only whitespace
        guard snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
            return (false, "Snippet trigger cannot be only whitespace")
        }
        
        // Validate trigger doesn't start with common command prefixes that might conflict
        let trimmedTrigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let reservedPrefixes = ["!", "@", "#", "$", "%", "^", "&", "*"]
        // Note: We allow "!" but warn if it's just "!"
        if trimmedTrigger.count == 1 && reservedPrefixes.contains(trimmedTrigger) {
            return (false, "Single-character triggers with special characters are not recommended")
        }
        
        return (true, nil)
    }
    
    func addSnippet(_ snippet: Snippet) {
        // FIX: Validate snippet before adding
        let validation = validateSnippet(snippet)
        guard validation.isValid else {
            print("❌ Invalid snippet: \(validation.error ?? "Unknown error")")
            print("   Trigger: '\(snippet.trigger)'")
            print("   Content length: \(snippet.content.count) characters")
            return
        }
        
        // Validate trigger is unique
        guard !snippets.contains(where: { $0.trigger.lowercased() == snippet.trigger.lowercased() }) else {
            print("⚠️ Snippet with trigger '\(snippet.trigger)' already exists")
            return
        }
        
        snippets.append(snippet)
        saveSnippets()
        print("✓ Added snippet: '\(snippet.trigger)' → '\(snippet.content.prefix(30))...'")
    }
    
    func updateSnippet(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else {
            print("⚠️ Snippet not found for update (ID: \(snippet.id))")
            return
        }
        
        // FIX: Validate snippet before updating
        let validation = validateSnippet(snippet)
        guard validation.isValid else {
            print("❌ Invalid snippet update: \(validation.error ?? "Unknown error")")
            print("   Trigger: '\(snippet.trigger)'")
            print("   Content length: \(snippet.content.count) characters")
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
        print("✓ Updated snippet: '\(snippet.trigger)' → '\(snippet.content.prefix(30))...'")
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
    
    // MARK: - Snippets 2.0: Dynamic Content Processing
    
    /// Processes snippet content to replace dynamic variables and handle cursor placement
    /// - Parameter content: The raw snippet content
    /// - Returns: A tuple containing the processed text and the cursor position (if any)
    func processSnippetContent(_ content: String) -> (text: String, cursorPosition: Int?) {
        var processedText = content
        
        // Replace dynamic variables
        processedText = replaceDynamicVariables(in: processedText)
        
        // Handle cursor placement (| syntax)
        if let pipeIndex = processedText.firstIndex(of: "|") {
            // Remove the pipe character
            processedText.remove(at: pipeIndex)
            
            // Calculate cursor position from the end of the string
            let distanceFromEnd = processedText.distance(from: pipeIndex, to: processedText.endIndex)
            
            return (processedText, distanceFromEnd)
        }
        
        return (processedText, nil)
    }
    
    /// Replaces dynamic variables in snippet content
    /// Supported variables: {date}, {time}, {clipboard}
    private func replaceDynamicVariables(in text: String) -> String {
        var result = text
        
        // Replace {date} with current date (dd/MM/yyyy)
        if result.contains("{date}") {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd/MM/yyyy"
            let currentDate = dateFormatter.string(from: Date())
            result = result.replacingOccurrences(of: "{date}", with: currentDate)
        }
        
        // Replace {time} with current time (HH:mm)
        if result.contains("{time}") {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let currentTime = timeFormatter.string(from: Date())
            result = result.replacingOccurrences(of: "{time}", with: currentTime)
        }
        
        // Replace {clipboard} with current clipboard content
        if result.contains("{clipboard}") {
            let pasteboard = NSPasteboard.general
            let clipboardContent = pasteboard.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{clipboard}", with: clipboardContent)
        }
        
        return result
    }
}

