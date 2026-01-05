import Foundation

/// Represents a text snippet that can be expanded via a trigger
struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var trigger: String  // e.g., "!mail"
    var content: String  // The text to expand to
    var lastModified: Date  // Timestamp for conflict resolution in iCloud sync
    
    init(id: UUID = UUID(), trigger: String, content: String, lastModified: Date = Date()) {
        self.id = id
        self.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        self.content = content
        self.lastModified = lastModified
    }
}

