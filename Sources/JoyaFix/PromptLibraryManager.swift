import Cocoa
import Foundation
import SwiftUI

class PromptLibraryManager: ObservableObject {
    static let shared = PromptLibraryManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var prompts: [PromptTemplate] = []
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = JoyaFixConstants.UserDefaultsKeys.promptLibrary
    private let initializationKey = "PromptLibraryInitialized"
    private let migrationKey = "PromptLibraryMigratedToCategories"
    
    // MARK: - Computed Properties
    
    /// Returns prompts grouped by category
    var promptsByCategory: [PromptCategory: [PromptTemplate]] {
        Dictionary(grouping: prompts) { $0.category }
    }
    
    /// Returns all categories that have prompts
    var categories: [PromptCategory] {
        Array(Set(prompts.map { $0.category })).sorted { $0.rawValue < $1.rawValue }
    }
    
    /// Returns prompts in a specific category
    func prompts(in category: PromptCategory) -> [PromptTemplate] {
        prompts.filter { $0.category == category }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load prompts on main thread
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                loadPrompts()
                
                // Migrate existing prompts to categories if needed
                if !UserDefaults.standard.bool(forKey: migrationKey) {
                    migratePromptsToCategories()
                    UserDefaults.standard.set(true, forKey: migrationKey)
                }
                
                // Initialize with default prompts on first run
                if !UserDefaults.standard.bool(forKey: initializationKey) {
                    initializeDefaultPrompts()
                    UserDefaults.standard.set(true, forKey: initializationKey)
                }
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    loadPrompts()
                    
                    // Migrate existing prompts to categories if needed
                    if !UserDefaults.standard.bool(forKey: migrationKey) {
                        migratePromptsToCategories()
                        UserDefaults.standard.set(true, forKey: migrationKey)
                    }
                    
                    // Initialize with default prompts on first run
                    if !UserDefaults.standard.bool(forKey: initializationKey) {
                        initializeDefaultPrompts()
                        UserDefaults.standard.set(true, forKey: initializationKey)
                    }
                }
            }
        }
    }
    
    // MARK: - Migration
    
    /// Migrates existing prompts to include categories
    @MainActor
    private func migratePromptsToCategories() {
        var migrated = false
        for i in 0..<prompts.count {
            // If prompt doesn't have a category (shouldn't happen with new decoder, but safety check)
            // The decoder will handle this, but we ensure all prompts have categories
            var prompt = prompts[i]
            // The decoder already handles migration, but we ensure consistency
            if prompts[i].category == .productivity && prompts[i].title.lowercased().contains("code") {
                // Re-assign if needed (though decoder should handle it)
                migrated = true
            }
        }
        if migrated {
            savePrompts()
            print("✓ Migrated prompts to categorized system")
        }
    }
    
    // MARK: - Default Prompts
    
    /// Initializes the library with 5 high-quality professional prompts
    @MainActor
    private func initializeDefaultPrompts() {
        let defaultPrompts: [PromptTemplate] = [
            // Email Refiner - Professional Writing
            PromptTemplate(
                title: "Email Refiner",
                content: "Please review and refine the following email to ensure it is professional, clear, and impactful while maintaining the original intent and tone:\n\n",
                category: .professionalWriting,
                isSystem: true
            ),
            // Code Architect - Coding & Tech
            PromptTemplate(
                title: "Code Architect",
                content: "Please review the following code for:\n1. Performance optimizations\n2. Best practices and design patterns\n3. Security vulnerabilities\n4. Code readability and maintainability\n5. Potential bugs or edge cases\n\nProvide specific, actionable recommendations:\n\n",
                category: .codingTech,
                isSystem: true
            ),
            // The Minimalist - Productivity
            PromptTemplate(
                title: "The Minimalist",
                content: "Please summarize the following text into exactly 3 concise bullet points, capturing only the most essential information:\n\n",
                category: .productivity,
                isSystem: true
            ),
            // Creative Muse - Creative
            PromptTemplate(
                title: "Creative Muse",
                content: "Act as a creative brainstorming partner. For the following topic or idea, generate 5 innovative, actionable marketing concepts that are both creative and practical:\n\n",
                category: .creative,
                isSystem: true
            ),
            // Translator Plus - Professional Writing
            PromptTemplate(
                title: "Translator Plus",
                content: "Please translate the following text, maintaining context and explaining any idioms, cultural references, or nuanced meanings that may not have direct translations. Provide both the translation and brief cultural context notes:\n\n",
                category: .professionalWriting,
                isSystem: true
            )
        ]
        
        prompts = defaultPrompts
        savePrompts()
        print("✓ Initialized prompt library with \(defaultPrompts.count) professional prompts across \(Set(defaultPrompts.map { $0.category }).count) categories")
    }
    
    // MARK: - Prompt Management
    
    /// Adds a new prompt to the library
    /// MUST be called on MainActor to ensure thread safety for @Published prompts
    @MainActor
    func addPrompt(_ prompt: PromptTemplate) {
        prompts.append(prompt)
        savePrompts()
        print("📝 Added prompt to library: \(prompt.title)")
    }
    
    /// Updates an existing prompt
    /// MUST be called on MainActor to ensure thread safety for @Published prompts
    @MainActor
    func updatePrompt(_ prompt: PromptTemplate) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else {
            print("⚠️ Prompt not found for update: \(prompt.id)")
            return
        }
        
        // Prevent editing system prompts (only allow updating lastUsed)
        if prompts[index].isSystem && prompt.isSystem {
            // Only update lastUsed for system prompts
            var updatedPrompt = prompts[index]
            updatedPrompt.lastUsed = prompt.lastUsed
            prompts[index] = updatedPrompt
        } else {
            prompts[index] = prompt
        }
        
        savePrompts()
        print("📝 Updated prompt: \(prompt.title)")
    }
    
    /// Deletes a prompt from the library (cannot delete system prompts)
    /// MUST be called on MainActor to ensure thread safety for @Published prompts
    @MainActor
    func deletePrompt(_ prompt: PromptTemplate) {
        guard !prompt.isSystem else {
            print("⚠️ Cannot delete system prompt: \(prompt.title)")
            return
        }
        
        prompts.removeAll { $0.id == prompt.id }
        savePrompts()
        print("🗑️ Deleted prompt: \(prompt.title)")
    }
    
    /// Records that a prompt was used (updates lastUsed timestamp)
    /// MUST be called on MainActor to ensure thread safety for @Published prompts
    @MainActor
    func recordUsage(of prompt: PromptTemplate) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else {
            return
        }
        
        var updatedPrompt = prompts[index]
        updatedPrompt.lastUsed = Date()
        prompts[index] = updatedPrompt
        savePrompts()
    }
    
    /// Copies prompt content to clipboard and records usage
    func copyPromptToClipboard(_ prompt: PromptTemplate) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt.content, forType: .string)
        
        // Record usage on main thread
        Task { @MainActor in
            recordUsage(of: prompt)
        }
        
        print("📋 Copied prompt to clipboard: \(prompt.title)")
    }
    
    // MARK: - Persistence
    
    /// Saves prompts to UserDefaults
    /// MUST be called on MainActor to ensure thread safety for @Published prompts
    @MainActor
    private func savePrompts() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(prompts) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    /// Loads prompts from UserDefaults
    /// MUST be called on MainActor to ensure thread safety for @Published prompts
    @MainActor
    private func loadPrompts() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([PromptTemplate].self, from: data) {
                prompts = decoded
                print("✓ Loaded \(prompts.count) prompts from library")
            }
        }
    }
}

// MARK: - PromptCategory Enum

enum PromptCategory: String, Codable, CaseIterable, Identifiable {
    case professionalWriting = "Professional Writing"
    case codingTech = "Coding & Tech"
    case creative = "Creative"
    case productivity = "Productivity"
    case socialMedia = "Social Media"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .professionalWriting: return "doc.text.fill"
        case .codingTech: return "chevron.left.forwardslash.chevron.right"
        case .creative: return "paintbrush.fill"
        case .productivity: return "bolt.fill"
        case .socialMedia: return "at"
        }
    }
    
    var color: Color {
        switch self {
        case .professionalWriting: return .blue
        case .codingTech: return .green
        case .creative: return .purple
        case .productivity: return .orange
        case .socialMedia: return .pink
        }
    }
}

// MARK: - PromptTemplate Model

struct PromptTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let content: String
    let category: PromptCategory
    let isSystem: Bool
    var lastUsed: Date?
    
    init(id: UUID = UUID(), title: String, content: String, category: PromptCategory = .productivity, isSystem: Bool = false, lastUsed: Date? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.isSystem = isSystem
        self.lastUsed = lastUsed
    }
    
    // Custom decoding to handle migration from old prompts without category
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        isSystem = try container.decode(Bool.self, forKey: .isSystem)
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
        
        // Migration: If category is missing, assign default based on title/content
        if let categoryString = try? container.decode(String.self, forKey: .category),
           let category = PromptCategory(rawValue: categoryString) {
            self.category = category
        } else {
            // Auto-assign category based on title/content for migration
            self.category = PromptTemplate.autoAssignCategory(title: title, content: content)
        }
    }
    
    // Helper for migration: Auto-assign category based on prompt content
    private static func autoAssignCategory(title: String, content: String) -> PromptCategory {
        let lowerTitle = title.lowercased()
        let lowerContent = content.lowercased()
        
        if lowerTitle.contains("code") || lowerTitle.contains("programming") || lowerContent.contains("code") {
            return .codingTech
        } else if lowerTitle.contains("email") || lowerTitle.contains("professional") || lowerTitle.contains("polish") {
            return .professionalWriting
        } else if lowerTitle.contains("creative") || lowerTitle.contains("brainstorm") || lowerTitle.contains("muse") {
            return .creative
        } else if lowerTitle.contains("social") || lowerTitle.contains("media") || lowerTitle.contains("twitter") {
            return .socialMedia
        } else {
            return .productivity // Default fallback
        }
    }
    
    static func == (lhs: PromptTemplate, rhs: PromptTemplate) -> Bool {
        return lhs.id == rhs.id
    }
}

