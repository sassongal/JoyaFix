import Foundation
import Combine

/// Represents a single scratchpad tab
struct ScratchpadTab: Identifiable, Codable {
    let id: UUID
    var name: String
    var content: String
    var createdAt: Date
    var lastModified: Date
    
    init(id: UUID = UUID(), name: String, content: String = "", createdAt: Date = Date(), lastModified: Date = Date()) {
        self.id = id
        self.name = name
        self.content = content
        self.createdAt = createdAt
        self.lastModified = lastModified
    }
}

/// Manages scratchpad content with auto-save and multiple tabs
/// Large text (>50k chars) is stored in Application Support to prevent startup lag
@MainActor
class ScratchpadManager: ObservableObject {
    static let shared = ScratchpadManager()
    
    @Published var tabs: [ScratchpadTab] = []
    @Published var selectedTabId: UUID? = nil
    
    // Legacy support - for backward compatibility
    @Published var content: String = "" {
        didSet {
            // Update current tab if exists
            if let currentTab = currentTab {
                updateTabContent(currentTab.id, content: content)
            }
        }
    }
    
    var currentTab: ScratchpadTab? {
        guard let selectedId = selectedTabId else { return nil }
        return tabs.first { $0.id == selectedId }
    }
    
    private let userDefaultsKey = "scratchpadTabs"
    private let legacyUserDefaultsKey = "scratchpadContent"
    private let largeTextThreshold = 50_000
    private let scratchpadDirectory: URL
    private var saveWorkItem: DispatchWorkItem?
    private let saveDelay: TimeInterval = 0.5 // 500ms debounce
    
    private init() {
        // Create Application Support directory for scratchpad
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        scratchpadDirectory = appSupport.appendingPathComponent("JoyaFix/Scratchpad", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: scratchpadDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Load tabs from UserDefaults
        loadTabs()
        
        // Migrate legacy single scratchpad to tabs if needed
        migrateLegacyScratchpad()
        
        // If no tabs exist, create default tab
        if tabs.isEmpty {
            createNewTab(name: "Scratchpad 1")
        }
        
        // Set first tab as selected
        if selectedTabId == nil, let firstTab = tabs.first {
            selectedTabId = firstTab.id
            content = firstTab.content
        }
    }
    
    /// Loads tabs from UserDefaults
    private func loadTabs() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([ScratchpadTab].self, from: data) {
            tabs = decoded
            Logger.info("📝 Loaded \(tabs.count) scratchpad tabs")
        }
        
        // Load selected tab ID
        if let selectedIdString = UserDefaults.standard.string(forKey: "scratchpadSelectedTabId"),
           let selectedId = UUID(uuidString: selectedIdString) {
            selectedTabId = selectedId
        }
    }
    
    /// Migrates legacy single scratchpad to tabs
    private func migrateLegacyScratchpad() {
        // Check if we already have tabs (migration already done)
        guard tabs.isEmpty else { return }
        
        // Try to load legacy content
        let legacyFileURL = scratchpadDirectory.appendingPathComponent("scratchpad.txt")
        var legacyContent = ""
        
        if let fileContent = try? String(contentsOf: legacyFileURL, encoding: .utf8), !fileContent.isEmpty {
            legacyContent = fileContent
        } else if let userDefaultsContent = UserDefaults.standard.string(forKey: legacyUserDefaultsKey), !userDefaultsContent.isEmpty {
            legacyContent = userDefaultsContent
        }
        
        // If legacy content exists, migrate it
        if !legacyContent.isEmpty {
            let migratedTab = ScratchpadTab(name: "Scratchpad 1", content: legacyContent)
            tabs = [migratedTab]
            selectedTabId = migratedTab.id
            content = legacyContent
            saveTabs()
            
            // Clean up legacy files
            try? FileManager.default.removeItem(at: legacyFileURL)
            UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
            
            Logger.info("📝 Migrated legacy scratchpad to tabs")
        }
    }
    
    /// Saves tabs to UserDefaults
    private func saveTabs() {
        if let encoded = try? JSONEncoder().encode(tabs) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            if let selectedId = selectedTabId {
                UserDefaults.standard.set(selectedId.uuidString, forKey: "scratchpadSelectedTabId")
            }
        }
    }
    
    /// Schedules a debounced save operation
    private func scheduleSave() {
        // Cancel previous save operation
        saveWorkItem?.cancel()
        
        // Create new save operation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.performSave()
        }
        
        saveWorkItem = workItem
        
        // Schedule save after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: workItem)
    }
    
    /// Performs the actual save operation
    private func performSave() {
        // Update current tab content
        if let currentTab = currentTab {
            updateTabContent(currentTab.id, content: content)
        }
        
        // Save tabs to UserDefaults
        saveTabs()
        
        Logger.info("📝 Scratchpad auto-saved")
    }
    
    /// Updates content for a specific tab
    func updateTabContent(_ tabId: UUID, content: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].content = content
        tabs[index].lastModified = Date()
    }
    
    /// Creates a new scratchpad tab
    func createNewTab(name: String? = nil) {
        let tabNumber = tabs.count + 1
        let tabName = name ?? "Scratchpad \(tabNumber)"
        let newTab = ScratchpadTab(name: tabName)
        tabs.append(newTab)
        selectedTabId = newTab.id
        content = ""
        saveTabs()
        Logger.info("📝 Created new scratchpad tab: \(tabName)")
    }
    
    /// Deletes a scratchpad tab
    func deleteTab(_ tabId: UUID) {
        guard tabs.count > 1 else {
            // Don't allow deleting the last tab
            Logger.warning("Cannot delete last scratchpad tab")
            return
        }
        
        tabs.removeAll { $0.id == tabId }
        
        // If deleted tab was selected, select another tab
        if selectedTabId == tabId {
            selectedTabId = tabs.first?.id
            if let newSelected = tabs.first {
                content = newSelected.content
            }
        }
        
        saveTabs()
        Logger.info("📝 Deleted scratchpad tab")
    }
    
    /// Selects a tab
    func selectTab(_ tabId: UUID) {
        selectedTabId = tabId
        if let tab = tabs.first(where: { $0.id == tabId }) {
            content = tab.content
        }
        saveTabs()
    }
    
    /// Renames a tab
    func renameTab(_ tabId: UUID, newName: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].name = newName
        saveTabs()
    }
    
    /// Clears the current scratchpad content
    func clear() {
        content = ""
        if let currentTab = currentTab {
            updateTabContent(currentTab.id, content: "")
        }
        saveTabs()
        Logger.info("📝 Scratchpad cleared")
    }
}

