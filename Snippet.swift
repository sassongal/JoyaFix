import Foundation

/// Represents a text snippet that can be expanded via a trigger
struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var trigger: String  // e.g., "!mail"
    var content: String  // The text to expand to
    
    init(id: UUID = UUID(), trigger: String, content: String) {
        self.id = id
        self.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        self.content = content
    }
}

