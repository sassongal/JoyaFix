import Cocoa
import Foundation

class PromptLibraryManager: ObservableObject {
    static let shared = PromptLibraryManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var prompts: [PromptTemplate] = []
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = JoyaFixConstants.UserDefaultsKeys.promptLibrary
    private let initializationKey = "PromptLibraryInitialized"
    
    // MARK: - Initialization
    
    private init() {
        // Load prompts on main thread
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                loadPrompts()
                
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
                    
                    // Initialize with default prompts on first run
                    if !UserDefaults.standard.bool(forKey: initializationKey) {
                        initializeDefaultPrompts()
                        UserDefaults.standard.set(true, forKey: initializationKey)
                    }
                }
            }
        }
    }
    
    // MARK: - Default Prompts
    
    /// Initializes the library with 5 high-quality default prompts
    @MainActor
    private func initializeDefaultPrompts() {
        let defaultPrompts: [PromptTemplate] = [
            PromptTemplate(
                title: NSLocalizedString("library.default.polish", comment: "Professional Polish"),
                content: "Please review and improve the following text for professional polish, clarity, and correctness. Maintain the original meaning and tone while enhancing readability and impact:\n\n",
                isSystem: true
            ),
            PromptTemplate(
                title: NSLocalizedString("library.default.code", comment: "Code Review"),
                content: "Please review the following code for:\n1. Best practices and code quality\n2. Potential bugs or issues\n3. Performance optimizations\n4. Security concerns\n5. Code readability and maintainability\n\nCode:\n",
                isSystem: true
            ),
            PromptTemplate(
                title: NSLocalizedString("library.default.summarize", comment: "Summarize"),
                content: "Please provide a concise summary of the following text, highlighting the key points and main ideas:\n\n",
                isSystem: true
            ),
            PromptTemplate(
                title: NSLocalizedString("library.default.translate", comment: "Translate to Hebrew"),
                content: "Please translate the following text to Hebrew, maintaining the original meaning and tone:\n\n",
                isSystem: true
            ),
            PromptTemplate(
                title: NSLocalizedString("library.default.explain", comment: "Explain Simply"),
                content: "Please explain the following concept or text in simple, easy-to-understand language, as if explaining to someone without prior knowledge:\n\n",
                isSystem: true
            )
        ]
        
        prompts = defaultPrompts
        savePrompts()
        print("✓ Initialized prompt library with \(defaultPrompts.count) default prompts")
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

// MARK: - PromptTemplate Model

struct PromptTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let content: String
    let isSystem: Bool
    var lastUsed: Date?
    
    init(id: UUID = UUID(), title: String, content: String, isSystem: Bool = false, lastUsed: Date? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.isSystem = isSystem
        self.lastUsed = lastUsed
    }
    
    static func == (lhs: PromptTemplate, rhs: PromptTemplate) -> Bool {
        return lhs.id == rhs.id
    }
}

