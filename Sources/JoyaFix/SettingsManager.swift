import Foundation
import Combine
import Carbon

/// AI Provider selection
enum AIProvider: String, Codable {
    case gemini
    case openRouter
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - Published Properties

    @Published var maxHistoryCount: Int {
        didSet {
            UserDefaults.standard.set(maxHistoryCount, forKey: Keys.maxHistoryCount)
        }
    }

    @Published var hotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode)
        }
    }

    @Published var hotkeyModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers)
        }
    }

    @Published var playSoundOnConvert: Bool {
        didSet {
            UserDefaults.standard.set(playSoundOnConvert, forKey: Keys.playSoundOnConvert)
        }
    }

    @Published var autoPasteAfterConvert: Bool {
        didSet {
            UserDefaults.standard.set(autoPasteAfterConvert, forKey: Keys.autoPasteAfterConvert)
        }
    }

    @Published var ocrHotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(ocrHotkeyKeyCode, forKey: Keys.ocrHotkeyKeyCode)
        }
    }

    @Published var ocrHotkeyModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(ocrHotkeyModifiers, forKey: Keys.ocrHotkeyModifiers)
        }
    }

    @Published var promptHotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(promptHotkeyKeyCode, forKey: Keys.promptHotkeyKeyCode)
        }
    }

    @Published var promptHotkeyModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(promptHotkeyModifiers, forKey: Keys.promptHotkeyModifiers)
        }
    }

    @Published var geminiKey: String {
        didSet {
            // Store securely in Keychain instead of UserDefaults
            if !geminiKey.isEmpty {
                try? KeychainHelper.storeGeminiKey(geminiKey)
            } else {
                try? KeychainHelper.deleteGeminiKey()
            }
        }
    }

    @Published var useCloudOCR: Bool {
        didSet {
            UserDefaults.standard.set(useCloudOCR, forKey: Keys.useCloudOCR)
        }
    }
    
    @Published var selectedAIProvider: AIProvider {
        didSet {
            if let encoded = try? JSONEncoder().encode(selectedAIProvider),
               let string = String(data: encoded, encoding: .utf8) {
                UserDefaults.standard.set(string, forKey: Keys.selectedAIProvider)
            }
        }
    }
    
    @Published var openRouterKey: String {
        didSet {
            // Store securely in Keychain instead of UserDefaults
            if !openRouterKey.isEmpty {
                try? KeychainHelper.storeOpenRouterKey(openRouterKey)
            } else {
                try? KeychainHelper.deleteOpenRouterKey()
            }
        }
    }
    
    @Published var openRouterModel: String {
        didSet {
            UserDefaults.standard.set(openRouterModel, forKey: Keys.openRouterModel)
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let maxHistoryCount = "maxHistoryCount"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let playSoundOnConvert = "playSoundOnConvert"
        static let autoPasteAfterConvert = "autoPasteAfterConvert"
        static let ocrHotkeyKeyCode = "ocrHotkeyKeyCode"
        static let ocrHotkeyModifiers = "ocrHotkeyModifiers"
        static let promptHotkeyKeyCode = "promptHotkeyKeyCode"
        static let promptHotkeyModifiers = "promptHotkeyModifiers"
        static let geminiKey = "geminiKey"
        static let useCloudOCR = "useCloudOCR"
        static let selectedAIProvider = "selectedAIProvider"
        static let openRouterModel = "openRouterModel"
    }

    // MARK: - Initialization

    private init() {
        // Load settings or use defaults
        self.maxHistoryCount = UserDefaults.standard.object(forKey: Keys.maxHistoryCount) as? Int ?? Int(JoyaFixConstants.defaultMaxClipboardHistoryCount)
        self.hotkeyKeyCode = UserDefaults.standard.object(forKey: Keys.hotkeyKeyCode) as? UInt32 ?? UInt32(kVK_ANSI_K)
        self.hotkeyModifiers = UserDefaults.standard.object(forKey: Keys.hotkeyModifiers) as? UInt32 ?? UInt32(cmdKey | optionKey)
        self.playSoundOnConvert = UserDefaults.standard.object(forKey: Keys.playSoundOnConvert) as? Bool ?? true
        self.autoPasteAfterConvert = UserDefaults.standard.object(forKey: Keys.autoPasteAfterConvert) as? Bool ?? true
        self.ocrHotkeyKeyCode = UserDefaults.standard.object(forKey: Keys.ocrHotkeyKeyCode) as? UInt32 ?? UInt32(kVK_ANSI_X)
        self.ocrHotkeyModifiers = UserDefaults.standard.object(forKey: Keys.ocrHotkeyModifiers) as? UInt32 ?? UInt32(cmdKey | optionKey)
        self.promptHotkeyKeyCode = UserDefaults.standard.object(forKey: Keys.promptHotkeyKeyCode) as? UInt32 ?? UInt32(kVK_ANSI_P)
        self.promptHotkeyModifiers = UserDefaults.standard.object(forKey: Keys.promptHotkeyModifiers) as? UInt32 ?? UInt32(cmdKey | optionKey)
        
        // Load Gemini key from Keychain (secure storage)
        // First try Keychain, then fallback to UserDefaults for migration
        if let keychainKey = try? KeychainHelper.retrieveGeminiKey() {
            self.geminiKey = keychainKey
        } else if let userDefaultsKey = UserDefaults.standard.string(forKey: Keys.geminiKey), !userDefaultsKey.isEmpty {
            // Migrate from UserDefaults to Keychain
            self.geminiKey = userDefaultsKey
            try? KeychainHelper.storeGeminiKey(userDefaultsKey)
            // Remove from UserDefaults after migration
            UserDefaults.standard.removeObject(forKey: Keys.geminiKey)
        } else {
            self.geminiKey = ""
        }
        
        self.useCloudOCR = UserDefaults.standard.object(forKey: Keys.useCloudOCR) as? Bool ?? true
        
        // Load AI Provider selection
        if let providerString = UserDefaults.standard.string(forKey: Keys.selectedAIProvider),
           let providerData = providerString.data(using: .utf8),
           let provider = try? JSONDecoder().decode(AIProvider.self, from: providerData) {
            self.selectedAIProvider = provider
        } else {
            // Default to Gemini for backward compatibility
            self.selectedAIProvider = .gemini
        }
        
        // Load OpenRouter key from Keychain
        if let keychainKey = try? KeychainHelper.retrieveOpenRouterKey() {
            self.openRouterKey = keychainKey
        } else {
            self.openRouterKey = ""
        }
        
        // Load OpenRouter model (default to deepseek/deepseek-chat)
        self.openRouterModel = UserDefaults.standard.string(forKey: Keys.openRouterModel) ?? "deepseek/deepseek-chat"
    }

    // MARK: - Hotkey Helpers

    /// Returns a human-readable string representation of the current hotkey
    var hotkeyDisplayString: String {
        var modifierString = ""

        if hotkeyModifiers & UInt32(controlKey) != 0 {
            modifierString += "⌃"
        }
        if hotkeyModifiers & UInt32(optionKey) != 0 {
            modifierString += "⌥"
        }
        if hotkeyModifiers & UInt32(shiftKey) != 0 {
            modifierString += "⇧"
        }
        if hotkeyModifiers & UInt32(cmdKey) != 0 {
            modifierString += "⌘"
        }

        let keyString = keyCodeToString(hotkeyKeyCode)
        return modifierString + keyString
    }

    /// Converts a key code to its string representation
    func keyCodeToString(_ keyCode: Int) -> String {
        return keyCodeToString(UInt32(keyCode))
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "?"
        }
    }

    /// Resets all settings to defaults
    func resetToDefaults() {
        maxHistoryCount = Int(JoyaFixConstants.defaultMaxClipboardHistoryCount)
        hotkeyKeyCode = UInt32(kVK_ANSI_K)
        hotkeyModifiers = UInt32(cmdKey | optionKey)
        playSoundOnConvert = true
        autoPasteAfterConvert = true
    }
}
