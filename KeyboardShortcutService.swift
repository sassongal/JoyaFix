import Foundation
import Cocoa
import Carbon
import ApplicationServices

/// Centralized service for managing all keyboard shortcuts in the application
/// Prevents conflicts between global hotkeys (HotkeyManager) and snippet triggers (InputMonitor)
class KeyboardShortcutService {
    static let shared = KeyboardShortcutService()
    
    // MARK: - Registered Shortcuts
    
    /// Represents a registered keyboard shortcut
    struct RegisteredShortcut: Hashable, Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        let type: ShortcutType
        let identifier: String
        
        enum ShortcutType {
            case globalHotkey    // Carbon RegisterEventHotKey
            case snippetTrigger  // InputMonitor event tap
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(keyCode)
            hasher.combine(modifiers)
            hasher.combine(identifier)
        }
        
        static func == (lhs: RegisteredShortcut, rhs: RegisteredShortcut) -> Bool {
            return lhs.keyCode == rhs.keyCode &&
                   lhs.modifiers == rhs.modifiers &&
                   lhs.identifier == rhs.identifier
        }
    }
    
    /// All currently registered shortcuts
    private var registeredShortcuts: Set<RegisteredShortcut> = []
    
    /// Serial queue for thread-safe shortcut management
    private let shortcutQueue = DispatchQueue(label: "com.joyafix.shortcuts", attributes: .concurrent)
    
    private init() {}
    
    // MARK: - Registration
    
    /// Registers a global hotkey (Carbon RegisterEventHotKey)
    /// - Parameters:
    ///   - keyCode: The virtual key code
    ///   - modifiers: Modifier keys (cmdKey, optionKey, etc.)
    ///   - identifier: Unique identifier for this shortcut
    /// - Returns: true if registered successfully, false if conflict detected
    func registerGlobalHotkey(keyCode: UInt32, modifiers: UInt32, identifier: String) -> Bool {
        return shortcutQueue.sync(flags: .barrier) {
            let shortcut = RegisteredShortcut(keyCode: keyCode, modifiers: modifiers, type: .globalHotkey, identifier: identifier)
            
            // Check for conflicts
            if hasConflict(with: shortcut) {
                print("⚠️ Shortcut conflict detected for \(identifier): keyCode=\(keyCode), modifiers=\(modifiers)")
                return false
            }
            
            registeredShortcuts.insert(shortcut)
            print("✓ Registered global hotkey: \(identifier) (keyCode=\(keyCode), modifiers=\(modifiers))")
            return true
        }
    }
    
    /// Registers a snippet trigger (InputMonitor)
    /// - Parameters:
    ///   - trigger: The trigger text (e.g., "!mail")
    ///   - identifier: Unique identifier for this trigger
    /// - Returns: true if registered successfully, false if conflict detected
    /// Note: Snippet triggers don't have keyCode/modifiers, but we track them for conflict detection
    func registerSnippetTrigger(trigger: String, identifier: String) -> Bool {
        return shortcutQueue.sync(flags: .barrier) {
            // Snippet triggers are text-based, not key-based
            // We still register them to track all shortcuts
            let shortcut = RegisteredShortcut(keyCode: 0, modifiers: 0, type: .snippetTrigger, identifier: identifier)
            
            // Check if trigger conflicts with existing snippet triggers
            let existingTriggers = registeredShortcuts.filter { $0.type == .snippetTrigger && $0.identifier == identifier }
            if !existingTriggers.isEmpty {
                print("⚠️ Snippet trigger already registered: \(identifier)")
                return false
            }
            
            registeredShortcuts.insert(shortcut)
            print("✓ Registered snippet trigger: \(identifier) (trigger=\(trigger))")
            return true
        }
    }
    
    /// Unregisters a shortcut
    func unregisterShortcut(identifier: String) {
        shortcutQueue.async(flags: .barrier) {
            self.registeredShortcuts.removeAll { $0.identifier == identifier }
            print("✓ Unregistered shortcut: \(identifier)")
        }
    }
    
    /// Unregisters all shortcuts of a specific type
    func unregisterAllShortcuts(ofType type: RegisteredShortcut.ShortcutType) {
        shortcutQueue.async(flags: .barrier) {
            let count = self.registeredShortcuts.count
            self.registeredShortcuts.removeAll { $0.type == type }
            let removed = count - self.registeredShortcuts.count
            print("✓ Unregistered \(removed) shortcuts of type: \(type)")
        }
    }
    
    /// Unregisters all shortcuts
    func unregisterAllShortcuts() {
        shortcutQueue.async(flags: .barrier) {
            let count = self.registeredShortcuts.count
            self.registeredShortcuts.removeAll()
            print("✓ Unregistered all \(count) shortcuts")
        }
    }
    
    // MARK: - Conflict Detection
    
    /// Checks if a shortcut conflicts with existing registered shortcuts
    /// - Parameter shortcut: The shortcut to check
    /// - Returns: true if conflict exists, false otherwise
    func hasConflict(with shortcut: RegisteredShortcut) -> Bool {
        return shortcutQueue.sync {
            // Check for exact match (same keyCode + modifiers)
            let hasExactMatch = registeredShortcuts.contains { existing in
                existing.keyCode == shortcut.keyCode &&
                existing.modifiers == shortcut.modifiers &&
                existing.identifier != shortcut.identifier
            }
            
            if hasExactMatch {
                let conflicting = registeredShortcuts.first { existing in
                    existing.keyCode == shortcut.keyCode &&
                    existing.modifiers == shortcut.modifiers &&
                    existing.identifier != shortcut.identifier
                }
                if let conflicting = conflicting {
                    print("⚠️ Conflict: \(shortcut.identifier) conflicts with \(conflicting.identifier)")
                }
                return true
            }
            
            return false
        }
    }
    
    /// Checks if a key combination is available (not registered)
    /// - Parameters:
    ///   - keyCode: The virtual key code
    ///   - modifiers: Modifier keys
    /// - Returns: true if available, false if already registered
    func isKeyCombinationAvailable(keyCode: UInt32, modifiers: UInt32) -> Bool {
        return shortcutQueue.sync {
            let shortcut = RegisteredShortcut(keyCode: keyCode, modifiers: modifiers, type: .globalHotkey, identifier: "check")
            return !hasConflict(with: shortcut)
        }
    }
    
    /// Gets all registered shortcuts
    func getAllRegisteredShortcuts() -> [RegisteredShortcut] {
        return shortcutQueue.sync {
            return Array(registeredShortcuts)
        }
    }
    
    /// Gets registered shortcuts of a specific type
    func getShortcuts(ofType type: RegisteredShortcut.ShortcutType) -> [RegisteredShortcut] {
        return shortcutQueue.sync {
            return registeredShortcuts.filter { $0.type == type }
        }
    }
    
    // MARK: - Validation
    
    /// Validates that a key combination doesn't conflict with system shortcuts
    /// - Parameters:
    ///   - keyCode: The virtual key code
    ///   - modifiers: Modifier keys
    /// - Returns: Validation result with error message if invalid
    /// Note: This is a synchronous method that can be called from any thread
    func validateKeyCombination(keyCode: UInt32, modifiers: UInt32) -> (isValid: Bool, error: String?) {
        // Check for system-reserved shortcuts
        let reservedCombinations: [(keyCode: UInt32, modifiers: UInt32, description: String)] = [
            (UInt32(kVK_ANSI_Q), UInt32(cmdKey), "Cmd+Q (Quit)"),
            (UInt32(kVK_ANSI_W), UInt32(cmdKey), "Cmd+W (Close Window)"),
            (UInt32(kVK_ANSI_M), UInt32(cmdKey), "Cmd+M (Minimize)"),
            (UInt32(kVK_ANSI_H), UInt32(cmdKey), "Cmd+H (Hide)"),
            (UInt32(kVK_ANSI_TAB), UInt32(cmdKey), "Cmd+Tab (App Switcher)"),
            (UInt32(kVK_Space), UInt32(cmdKey), "Cmd+Space (Spotlight)"),
        ]
        
        for reserved in reservedCombinations {
            if keyCode == reserved.keyCode && modifiers == reserved.modifiers {
                return (false, "This key combination is reserved by macOS: \(reserved.description)")
            }
        }
        
        // Check for conflicts with existing shortcuts
        if !isKeyCombinationAvailable(keyCode: keyCode, modifiers: modifiers) {
            return (false, "This key combination is already registered")
        }
        
        return (true, nil)
    }
}

