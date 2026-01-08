import Foundation
import Combine
import Cocoa

/// Manages text snippets for auto-expansion with iCloud sync
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
            // Try to decode with new format (includes lastModified)
            let decoded = try JSONDecoder().decode([Snippet].self, from: data)
            snippets = decoded
            print("✓ Loaded \(snippets.count) snippets from UserDefaults (\(data.count) bytes)")
            
            // Check if any snippets are missing lastModified (migration needed)
            var needsMigration = false
            let migratedSnippets = snippets.map { snippet -> Snippet in
                // If lastModified is in the distant past (before 2020), it's likely a default value
                // This indicates old data that needs migration
                let cutoffDate = Date(timeIntervalSince1970: 1577836800) // Jan 1, 2020
                if snippet.lastModified < cutoffDate {
                    needsMigration = true
                    var migrated = snippet
                    migrated.lastModified = Date() // Set to current time
                    return migrated
                }
                return snippet
            }
            
            if needsMigration {
                snippets = migratedSnippets
                saveSnippets() // Save migrated data
                print("✓ Migrated snippets to include lastModified timestamps")
            }
            
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
            // If decoding fails, try to decode as old format (without lastModified)
            print("⚠️ Failed to decode with new format, trying migration: \(error.localizedDescription)")
            
            // Try to decode as array of dictionaries to handle missing lastModified
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var migratedSnippets: [Snippet] = []
                for dict in jsonArray {
                    if let idString = dict["id"] as? String,
                       let id = UUID(uuidString: idString),
                       let trigger = dict["trigger"] as? String,
                       let content = dict["content"] as? String {
                        // Create snippet with current timestamp for migration
                        let snippet = Snippet(id: id, trigger: trigger, content: content, lastModified: Date())
                        migratedSnippets.append(snippet)
                    }
                }
                
                if !migratedSnippets.isEmpty {
                    snippets = migratedSnippets
                    saveSnippets() // Save migrated data
                    print("✓ Migrated \(migratedSnippets.count) snippets from old format")
                    return
                }
            }
            
            // If all else fails, reset to defaults
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
            // Save locally
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
        guard !snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        // SECURITY: Validate and sanitize snippet before adding
        let validation = validateSnippet(snippet)
        guard validation.isValid else {
            Logger.snippet("Invalid snippet: \(validation.error ?? "Unknown error")", level: .error)
            Logger.snippet("Trigger: '\(snippet.trigger)', Content length: \(snippet.content.count) characters", level: .error)
            return
        }
        
        // SECURITY: Sanitize content (escape HTML entities if needed)
        let sanitizedContent = sanitizeContent(snippet.content)
        var sanitizedSnippet = snippet
        sanitizedSnippet.content = sanitizedContent
        
        // Validate trigger is unique
        guard !snippets.contains(where: { $0.trigger.lowercased() == snippet.trigger.lowercased() }) else {
            Logger.snippet("Snippet with trigger '\(snippet.trigger)' already exists", level: .warning)
            return
        }
        
        // Create new snippet with current timestamp
        var newSnippet = sanitizedSnippet
        newSnippet.lastModified = Date()
        snippets.append(newSnippet)
        saveSnippets()
        
        // Notify InputMonitor to register the new trigger
        InputMonitor.shared.registerSnippetTrigger(newSnippet.trigger)
        
        Logger.snippet("Added snippet: '\(newSnippet.trigger)' → '\(newSnippet.content.prefix(30))...'", level: .info)
    }
    
    /// Sanitizes snippet content to prevent XSS attacks
    private func sanitizeContent(_ content: String) -> String {
        // Basic sanitization - escape HTML entities
        // Note: For snippets, we typically want to preserve the content as-is
        // This is mainly for safety if content is ever displayed in HTML context
        return content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
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
        
        // Get old trigger for unregistration
        let oldSnippet = snippets[index]
        let oldTrigger = oldSnippet.trigger
        
        // Create updated snippet with current timestamp
        var updatedSnippet = snippet
        updatedSnippet.lastModified = Date()
        snippets[index] = updatedSnippet
        saveSnippets()
        
        // Update trigger registration if trigger changed
        if oldTrigger != updatedSnippet.trigger {
            InputMonitor.shared.unregisterSnippetTrigger(oldTrigger)
            InputMonitor.shared.registerSnippetTrigger(updatedSnippet.trigger)
        }
        
        print("✓ Updated snippet: '\(updatedSnippet.trigger)' → '\(updatedSnippet.content.prefix(30))...'")
    }
    
    func removeSnippet(_ snippet: Snippet) {
        let trigger = snippet.trigger
        snippets.removeAll { $0.id == snippet.id }
        saveSnippets()
        
        // Notify InputMonitor to unregister the trigger
        InputMonitor.shared.unregisterSnippetTrigger(trigger)
        
        print("✓ Removed snippet: \(trigger)")
    }
    
    func removeSnippet(at index: Int) {
        guard index < snippets.count else { return }
        let snippet = snippets[index]
        removeSnippet(snippet)
    }
    
    /// Atomically replaces all snippets with a new set
    /// This method validates all snippets before replacing, ensuring data integrity
    /// - Parameter newSnippets: Array of snippets to replace existing ones
    /// - Returns: true if replacement was successful, false if validation failed
    func replaceAllSnippets(_ newSnippets: [Snippet]) -> Bool {
        // Validate all new snippets before making any changes
        var validSnippets: [Snippet] = []
        var seenTriggers = Set<String>()
        
        for snippet in newSnippets {
            // Validate snippet structure
            let validation = validateSnippet(snippet)
            guard validation.isValid else {
                print("❌ Invalid snippet in import: '\(snippet.trigger)' - \(validation.error ?? "Unknown error")")
                return false
            }
            
            // Check for duplicate triggers
            let lowercasedTrigger = snippet.trigger.lowercased()
            guard !seenTriggers.contains(lowercasedTrigger) else {
                print("❌ Duplicate trigger in import: '\(snippet.trigger)'")
                return false
            }
            
            validSnippets.append(snippet)
            seenTriggers.insert(lowercasedTrigger)
        }
        
        // All validation passed - now perform atomic replacement
        // Update lastModified for all snippets to current time (they're being imported)
        let now = Date()
        let snippetsWithTimestamp = validSnippets.map { snippet -> Snippet in
            var updated = snippet
            updated.lastModified = now
            return updated
        }
        
        // Unregister all old triggers
        for snippet in snippets {
            InputMonitor.shared.unregisterSnippetTrigger(snippet.trigger)
        }
        
        // Replace the snippets array
        snippets = snippetsWithTimestamp
        
        // Register all new triggers
        for snippet in snippetsWithTimestamp {
            InputMonitor.shared.registerSnippetTrigger(snippet.trigger)
        }
        
        // Save once
        saveSnippets()
        
        print("✓ Atomically replaced all snippets: \(snippetsWithTimestamp.count) snippets")
        return true
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
    /// Note: This method may prompt user for variable values (synchronous, runs on MainActor)
    @MainActor
    func processSnippetContent(_ content: String) -> (text: String, cursorPosition: Int?) {
        var processedText = content
        
        // Replace dynamic variables (may prompt user)
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
    /// Supported variables:
    /// - Built-in: {date}, {time}, {clipboard}
    /// - User-defined: {name}, {email}, etc. (prompts user for input)
    /// - Conditional: {if:condition:trueValue:falseValue}
    /// Note: Must be called on MainActor if user-defined variables are used
    @MainActor
    private func replaceDynamicVariables(in text: String) -> String {
        var result = text
        
        // Process conditional logic first (before variable replacement)
        result = processConditionalLogic(in: result)
        
        // Replace built-in variables
        result = replaceBuiltInVariables(in: result)
        
        // Replace user-defined variables (with prompts)
        result = replaceUserDefinedVariables(in: result)
        
        return result
    }
    
    /// Replaces built-in system variables
    private func replaceBuiltInVariables(in text: String) -> String {
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
        
        // Replace {datetime} with current date and time
        if result.contains("{datetime}") {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
            let currentDateTime = dateFormatter.string(from: Date())
            result = result.replacingOccurrences(of: "{datetime}", with: currentDateTime)
        }
        
        // Replace {year} with current year
        if result.contains("{year}") {
            let year = Calendar.current.component(.year, from: Date())
            result = result.replacingOccurrences(of: "{year}", with: String(year))
        }
        
        // Replace {month} with current month (01-12)
        if result.contains("{month}") {
            let month = Calendar.current.component(.month, from: Date())
            result = result.replacingOccurrences(of: "{month}", with: String(format: "%02d", month))
        }
        
        // Replace {day} with current day (01-31)
        if result.contains("{day}") {
            let day = Calendar.current.component(.day, from: Date())
            result = result.replacingOccurrences(of: "{day}", with: String(format: "%02d", day))
        }
        
        return result
    }
    
    /// Replaces user-defined variables with prompts
    /// Syntax: {variableName} or {variableName:defaultValue}
    /// Example: {name} or {name:John}
    /// Note: Must be called on MainActor (shows UI dialogs)
    @MainActor
    private func replaceUserDefinedVariables(in text: String) -> String {
        var result = text
        
        // Pattern to match {variableName} or {variableName:defaultValue}
        let variablePattern = #"\{([a-zA-Z_][a-zA-Z0-9_]*)(?::([^}]*))?\}"#
        
        guard let regex = try? NSRegularExpression(pattern: variablePattern, options: []) else {
            return result
        }
        
        let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
        
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            
            let variableNameRange = Range(match.range(at: 1), in: result)!
            let variableName = String(result[variableNameRange])
            
            // Check if it's a built-in variable (already processed)
            let builtInVariables = ["date", "time", "clipboard", "datetime", "year", "month", "day"]
            if builtInVariables.contains(variableName.lowercased()) {
                continue
            }
            
            // Get default value if provided
            var defaultValue: String? = nil
            if match.numberOfRanges >= 3 {
                let defaultValueRange = Range(match.range(at: 2), in: result)
                if let defaultValueRange = defaultValueRange {
                    defaultValue = String(result[defaultValueRange])
                }
            }
            
            // Check if variable is cached
            let cacheKey = "snippet_variable_\(variableName)"
            if let cachedValue = UserDefaults.standard.string(forKey: cacheKey), !cachedValue.isEmpty {
                // Use cached value
                let fullMatchRange = Range(match.range, in: result)!
                result.replaceSubrange(fullMatchRange, with: cachedValue)
                continue
            }
            
            // Prompt user for variable value
            let value = promptForVariable(name: variableName, defaultValue: defaultValue)
            
            // Cache the value for future use
            if !value.isEmpty {
                UserDefaults.standard.set(value, forKey: cacheKey)
            }
            
            // Replace variable with user input
            let fullMatchRange = Range(match.range, in: result)!
            result.replaceSubrange(fullMatchRange, with: value)
        }
        
        return result
    }
    
    /// Prompts user for a variable value
    /// Note: Must be called on MainActor (shows UI dialog)
    @MainActor
    private func promptForVariable(name: String, defaultValue: String?) -> String {
        // Use NSAlert with text field for input
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("snippet.variable.prompt.title", comment: "Enter Variable Value")
        alert.informativeText = String(format: NSLocalizedString("snippet.variable.prompt.message", comment: "Enter value for variable"), name)
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("alert.button.cancel", comment: "Cancel"))
        
        // Add text field for input
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.stringValue = defaultValue ?? ""
        inputField.placeholderString = name
        alert.accessoryView = inputField
        
        // Focus the text field
        alert.window.initialFirstResponder = inputField
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            return inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return defaultValue ?? ""
    }
    
    /// Processes conditional logic in snippet content
    /// Syntax: {if:condition:trueValue:falseValue}
    /// Example: {if:{time}<12:Good morning:Good afternoon}
    /// Supported conditions: <, >, ==, !=, contains
    private func processConditionalLogic(in text: String) -> String {
        var result = text
        
        // Pattern to match {if:condition:trueValue:falseValue}
        let conditionalPattern = #"\{if:([^:]+):([^:]+):([^}]+)\}"#
        
        guard let regex = try? NSRegularExpression(pattern: conditionalPattern, options: []) else {
            return result
        }
        
        var hasChanges = true
        var iterations = 0
        let maxIterations = 10 // Prevent infinite loops
        
        // Process conditionals iteratively (they can be nested)
        while hasChanges && iterations < maxIterations {
            hasChanges = false
            iterations += 1
            
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            
            // Process matches in reverse order to preserve indices
            for match in matches.reversed() {
                guard match.numberOfRanges >= 4 else { continue }
                
                let conditionRange = Range(match.range(at: 1), in: result)!
                let trueValueRange = Range(match.range(at: 2), in: result)!
                let falseValueRange = Range(match.range(at: 3), in: result)!
                
                let condition = String(result[conditionRange])
                let trueValue = String(result[trueValueRange])
                let falseValue = String(result[falseValueRange])
                
                // Evaluate condition
                let conditionResult = evaluateCondition(condition)
                
                // Replace with appropriate value
                let replacement = conditionResult ? trueValue : falseValue
                let fullMatchRange = Range(match.range, in: result)!
                result.replaceSubrange(fullMatchRange, with: replacement)
                hasChanges = true
            }
        }
        
        return result
    }
    
    /// Evaluates a conditional expression
    /// Supports: <, >, ==, !=, contains
    /// Examples: "5<10", "name==John", "text contains hello"
    private func evaluateCondition(_ condition: String) -> Bool {
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for comparison operators
        if let lessThanRange = trimmed.range(of: "<") {
            let left = String(trimmed[..<lessThanRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[lessThanRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            
            if let leftNum = Double(left), let rightNum = Double(right) {
                return leftNum < rightNum
            }
            
            // String comparison
            return left < right
        }
        
        if let greaterThanRange = trimmed.range(of: ">") {
            let left = String(trimmed[..<greaterThanRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[greaterThanRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            
            if let leftNum = Double(left), let rightNum = Double(right) {
                return leftNum > rightNum
            }
            
            // String comparison
            return left > right
        }
        
        if let equalsRange = trimmed.range(of: "==") {
            let left = String(trimmed[..<equalsRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[equalsRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return left == right
        }
        
        if let notEqualsRange = trimmed.range(of: "!=") {
            let left = String(trimmed[..<notEqualsRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[notEqualsRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return left != right
        }
        
        // Check for "contains" operator
        if let containsRange = trimmed.range(of: " contains ", options: .caseInsensitive) {
            let left = String(trimmed[..<containsRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[containsRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return left.lowercased().contains(right.lowercased())
        }
        
        // If no operator found, treat as boolean (non-empty = true)
        return !trimmed.isEmpty
    }
}

