import Foundation
import Combine

/// Manages scratchpad content with auto-save
/// Large text (>50k chars) is stored in Application Support to prevent startup lag
@MainActor
class ScratchpadManager: ObservableObject {
    static let shared = ScratchpadManager()
    
    @Published var content: String = "" {
        didSet {
            scheduleSave()
        }
    }
    
    private let userDefaultsKey = "scratchpadContent"
    private let largeTextThreshold = 50_000
    private let scratchpadFileURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private let saveDelay: TimeInterval = 0.5 // 500ms debounce
    
    private init() {
        // Create Application Support directory for scratchpad
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let scratchpadDirectory = appSupport.appendingPathComponent("JoyaFix/Scratchpad", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: scratchpadDirectory, withIntermediateDirectories: true, attributes: nil)
        
        scratchpadFileURL = scratchpadDirectory.appendingPathComponent("scratchpad.txt")
        
        // Load saved content - check file first (for large text), then UserDefaults (for small text)
        if let fileContent = try? String(contentsOf: scratchpadFileURL, encoding: .utf8), !fileContent.isEmpty {
            content = fileContent
            Logger.info("📝 Scratchpad loaded from file (\(content.count) chars)")
        } else if let userDefaultsContent = UserDefaults.standard.string(forKey: userDefaultsKey), !userDefaultsContent.isEmpty {
            content = userDefaultsContent
            // If content is large, migrate to file
            if content.count > largeTextThreshold {
                migrateToFile()
            }
            Logger.info("📝 Scratchpad loaded from UserDefaults (\(content.count) chars)")
        } else {
            content = ""
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
    
    /// Performs the actual save operation, choosing file or UserDefaults based on content size
    private func performSave() {
        if content.count > largeTextThreshold {
            // Large text: save to file, remove from UserDefaults
            do {
                try content.write(to: scratchpadFileURL, atomically: true, encoding: .utf8)
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                Logger.info("📝 Scratchpad auto-saved to file (\(content.count) chars)")
            } catch {
                Logger.error("Failed to save scratchpad to file: \(error.localizedDescription)", category: .general)
                // Fallback to UserDefaults if file save fails
                UserDefaults.standard.set(content, forKey: userDefaultsKey)
                Logger.info("📝 Scratchpad fallback saved to UserDefaults (\(content.count) chars)")
            }
        } else {
            // Small text: save to UserDefaults, remove file if exists
            UserDefaults.standard.set(content, forKey: userDefaultsKey)
            if FileManager.default.fileExists(atPath: scratchpadFileURL.path) {
                try? FileManager.default.removeItem(at: scratchpadFileURL)
            }
            Logger.info("📝 Scratchpad auto-saved to UserDefaults (\(content.count) chars)")
        }
    }
    
    /// Migrates content from UserDefaults to file (for large text)
    private func migrateToFile() {
        do {
            try content.write(to: scratchpadFileURL, atomically: true, encoding: .utf8)
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            Logger.info("📝 Scratchpad migrated to file (\(content.count) chars)")
        } catch {
            Logger.error("Failed to migrate scratchpad to file: \(error.localizedDescription)", category: .general)
        }
    }
    
    /// Clears the scratchpad content
    func clear() {
        content = ""
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        // Remove file if it exists
        if FileManager.default.fileExists(atPath: scratchpadFileURL.path) {
            try? FileManager.default.removeItem(at: scratchpadFileURL)
        }
        Logger.info("📝 Scratchpad cleared")
    }
}

