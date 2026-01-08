import Foundation
import Combine

/// Manages scratchpad content with auto-save
@MainActor
class ScratchpadManager: ObservableObject {
    static let shared = ScratchpadManager()
    
    @Published var content: String = "" {
        didSet {
            scheduleSave()
        }
    }
    
    private let userDefaultsKey = "scratchpadContent"
    private var saveWorkItem: DispatchWorkItem?
    private let saveDelay: TimeInterval = 0.5 // 500ms debounce
    
    private init() {
        // Load saved content
        content = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
    }
    
    /// Schedules a debounced save operation
    private func scheduleSave() {
        // Cancel previous save operation
        saveWorkItem?.cancel()
        
        // Create new save operation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.set(self.content, forKey: self.userDefaultsKey)
            Logger.info("📝 Scratchpad auto-saved (\(self.content.count) chars)")
        }
        
        saveWorkItem = workItem
        
        // Schedule save after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: workItem)
    }
    
    /// Clears the scratchpad content
    func clear() {
        content = ""
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        Logger.info("📝 Scratchpad cleared")
    }
}

