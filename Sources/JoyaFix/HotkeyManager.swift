import Cocoa
import Carbon
import ApplicationServices
import CoreFoundation

// Global pointer for C callback access
private weak var globalHotkeyManagerInstance: HotkeyManager?

// MARK: - Global C Callback Function
// CRITICAL FIX: Defined outside the class to prevent Swift closure capture crashes
private func globalHotkeyEventHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotkeyID = EventHotKeyID()
    let size = MemoryLayout<EventHotKeyID>.size
    
    // שליפת ה-ID של המקש שנלחץ
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        size,
        nil,
        &hotkeyID
    )
    
    // קביעת שם הנוטיפיקציה
    let notificationNameString: String
    switch hotkeyID.id {
    case 1:
        notificationNameString = "HotkeyManager.hotkeyPressed"
    case 3:
        notificationNameString = "HotkeyManager.keyboardLockHotkeyPressed"
    case 4:
        notificationNameString = "HotkeyManager.promptHotkeyPressed"
    case 5:
        notificationNameString = "HotkeyManager.voiceInputHotkeyPressed"
    default:
        return noErr
    }
    
    // שימוש ב-performSelector בטוח כדי לחזור ל-Main Thread
    if let manager = globalHotkeyManagerInstance {
        let notificationNameObj = NSString(string: notificationNameString)
        manager.performSelector(onMainThread: #selector(HotkeyManager.postHotkeyNotificationObj(_:)), with: notificationNameObj, waitUntilDone: false)
    }
    
    return noErr
}

class HotkeyManager: NSObject {
    static let shared: HotkeyManager = {
        let instance = HotkeyManager()
        // Set the global pointer once
        globalHotkeyManagerInstance = instance
        return instance
    }()

    private var eventHotKeyRef: EventHotKeyRef?
    private var keyboardLockHotKeyRef: EventHotKeyRef?
    private var promptHotKeyRef: EventHotKeyRef?
    private var voiceInputHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // Hotkey signatures
    private let hotkeyID = EventHotKeyID(signature: OSType(0x4A4F5941), id: 1) // 'JOYA'
    private let keyboardLockHotkeyID = EventHotKeyID(signature: OSType(0x4B424C4B), id: 3) // 'KBLK'
    private let promptHotkeyID = EventHotKeyID(signature: OSType(0x50524F4D), id: 4) // 'PROM'
    private let voiceInputHotkeyID = EventHotKeyID(signature: OSType(0x564F4943), id: 5) // 'VOIC'
    
    private let convertShortcutID = "hotkey.convert"
    private let keyboardLockShortcutID = "hotkey.keyboardLock"
    private let promptShortcutID = "hotkey.prompt"
    private let voiceInputShortcutID = "hotkey.voiceInput"

    private let settings = SettingsManager.shared
    private let shortcutService = KeyboardShortcutService.shared

    override private init() {
        super.init()
        // Ensure global pointer is set
        globalHotkeyManagerInstance = self
    }

    // MARK: - Rebind Hotkeys
    @discardableResult
    func rebindHotkeys() -> (convertSuccess: Bool, keyboardLockSuccess: Bool, promptSuccess: Bool) {
        Logger.hotkey("Rebinding hotkeys...", level: .info)
        unregisterHotkey()
        usleep(50000) // 50ms delay

        let convertSuccess = registerHotkey()
        let keyboardLockSuccess = registerKeyboardLockHotkey()
        let promptSuccess = registerPromptHotkey()

        if convertSuccess && keyboardLockSuccess && promptSuccess {
            Logger.hotkey("All hotkeys rebound successfully", level: .info)
            SoundManager.shared.playSuccess()
        } else {
            Logger.hotkey("Some hotkeys failed to rebind", level: .warning)
        }
        return (convertSuccess, keyboardLockSuccess, promptSuccess)
    }

    // MARK: - Registration
    
    private func installSharedEventHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        
        // CRITICAL FIX: Pass the global function pointer
        let handler: EventHandlerUPP = globalHotkeyEventHandler
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        
        guard status == noErr else {
            Logger.hotkey("Failed to install event handler: \(status)", level: .error)
            return false
        }
        
        setupNotificationObservers()
        return true
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleHotkeyPressed), name: Notification.Name("HotkeyManager.hotkeyPressed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardLockHotkeyPressed), name: Notification.Name("HotkeyManager.keyboardLockHotkeyPressed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePromptHotkeyPressed), name: Notification.Name("HotkeyManager.promptHotkeyPressed"), object: nil)
    }
    
    // Methods to handle notifications from C callback
    @objc private func handleHotkeyPressed() { hotkeyPressed() }
    @objc private func handleKeyboardLockHotkeyPressed() { keyboardLockHotkeyPressed() }
    @objc private func handlePromptHotkeyPressed() { promptHotkeyPressed() }
    
    @objc func postHotkeyNotificationObj(_ notificationNameString: NSString) {
        NotificationCenter.default.post(name: Notification.Name(notificationNameString as String), object: nil)
    }

    func registerHotkey() -> Bool {
        let keyCode = settings.hotkeyKeyCode
        let modifiers = settings.hotkeyModifiers
        
        // CRITICAL FIX: Check if shortcut is already registered before attempting registration
        if !shortcutService.isKeyCombinationAvailable(keyCode: keyCode, modifiers: modifiers) {
            Logger.hotkey("Hotkey already registered: \(settings.hotkeyDisplayString)", level: .warning)
            return false
        }
        
        guard installSharedEventHandlerIfNeeded() else { return false }

        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &eventHotKeyRef)
        guard registerStatus == noErr else {
            Logger.hotkey("Failed to register conversion hotkey (Error: \(registerStatus))", level: .error)
            return false
        }
        _ = shortcutService.registerGlobalHotkey(keyCode: keyCode, modifiers: modifiers, identifier: convertShortcutID)
        Logger.hotkey("Conversion hotkey registered: \(settings.hotkeyDisplayString)", level: .info)
        return true
    }

    func registerKeyboardLockHotkey() -> Bool {
        let keyCode = UInt32(kVK_ANSI_L)
        let modifiers = UInt32(cmdKey | optionKey)
        guard installSharedEventHandlerIfNeeded() else { return false }
        
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, keyboardLockHotkeyID, GetApplicationEventTarget(), 0, &keyboardLockHotKeyRef)
        guard registerStatus == noErr else {
            Logger.hotkey("Failed to register keyboard lock hotkey (Error: \(registerStatus))", level: .error)
            return false
        }
        
        _ = shortcutService.registerGlobalHotkey(keyCode: keyCode, modifiers: modifiers, identifier: keyboardLockShortcutID)
        Logger.hotkey("Keyboard lock hotkey registered", level: .info)
        return true
    }
    
    func registerPromptHotkey() -> Bool {
        let keyCode = settings.promptHotkeyKeyCode
        let modifiers = settings.promptHotkeyModifiers
        
        // CRITICAL FIX: Check if shortcut is already registered
        if !shortcutService.isKeyCombinationAvailable(keyCode: keyCode, modifiers: modifiers) {
            Logger.hotkey("Prompt hotkey already registered", level: .warning)
            return false
        }
        
        guard installSharedEventHandlerIfNeeded() else { return false }

        let registerStatus = RegisterEventHotKey(keyCode, modifiers, promptHotkeyID, GetApplicationEventTarget(), 0, &promptHotKeyRef)
        guard registerStatus == noErr else {
            Logger.hotkey("Failed to register prompt hotkey (Error: \(registerStatus))", level: .error)
            return false
        }
        
        _ = shortcutService.registerGlobalHotkey(keyCode: keyCode, modifiers: modifiers, identifier: promptShortcutID)
        Logger.hotkey("Prompt hotkey registered", level: .info)
        return true
    }
    
    func registerVoiceInputHotkey() -> Bool {
        // Default: Cmd+Option+V
        let keyCode = UInt32(kVK_ANSI_V)
        let modifiers = UInt32(cmdKey | optionKey)
        
        // Check if shortcut is already registered
        if !shortcutService.isKeyCombinationAvailable(keyCode: keyCode, modifiers: modifiers) {
            Logger.hotkey("Voice input hotkey already registered", level: .warning)
            return false
        }
        
        guard installSharedEventHandlerIfNeeded() else { return false }

        let registerStatus = RegisterEventHotKey(keyCode, modifiers, voiceInputHotkeyID, GetApplicationEventTarget(), 0, &voiceInputHotKeyRef)
        guard registerStatus == noErr else {
            Logger.hotkey("Failed to register voice input hotkey (Error: \(registerStatus))", level: .error)
            return false
        }
        
        _ = shortcutService.registerGlobalHotkey(keyCode: keyCode, modifiers: modifiers, identifier: voiceInputShortcutID)
        Logger.hotkey("Voice input hotkey registered", level: .info)
        return true
    }
    
    func unregisterHotkey() {
        shortcutService.unregisterShortcut(identifier: convertShortcutID)
        shortcutService.unregisterShortcut(identifier: keyboardLockShortcutID)
        shortcutService.unregisterShortcut(identifier: promptShortcutID)
        shortcutService.unregisterShortcut(identifier: voiceInputShortcutID)
        
        if let ref = eventHotKeyRef { UnregisterEventHotKey(ref); eventHotKeyRef = nil }
        if let ref = keyboardLockHotKeyRef { UnregisterEventHotKey(ref); keyboardLockHotKeyRef = nil }
        if let ref = promptHotKeyRef { UnregisterEventHotKey(ref); promptHotKeyRef = nil }
        if let ref = voiceInputHotKeyRef { UnregisterEventHotKey(ref); voiceInputHotKeyRef = nil }
        
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - Actions (Logic)
    
    private func hotkeyPressed() {
        Logger.hotkey("Hotkey pressed! Converting text...", level: .info)
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            showPermissionRequiredAlert()
            return
        }
        performTextConversion()
    }
    
    func performTextConversion() {
        simulateCopy()
        DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.textConversionClipboardDelay) {
            guard let copiedText = self.readFromClipboard() else { return }
            let convertedText = TextConverter.convert(copiedText)
            ClipboardHistoryManager.shared.notifyInternalWrite()
            self.writeToClipboard(convertedText)
            
            if self.settings.autoPasteAfterConvert {
                DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.clipboardPasteDelay) {
                    self.simulateDelete() // מחק את הטקסט המקורי
                    DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.textConversionDeleteDelay) {
                        self.simulatePaste() // הדבק את החדש
                        if self.settings.playSoundOnConvert { SoundManager.shared.playSuccess() }
                    }
                }
            } else if self.settings.playSoundOnConvert {
                SoundManager.shared.playSuccess()
            }
        }
    }

    
    private func keyboardLockHotkeyPressed() {
        KeyboardBlocker.shared.toggleLock()
    }
    
    private func promptHotkeyPressed() {
        // Check permissions first (with fresh check)
        let hasAccessibility = PermissionManager.shared.refreshAccessibilityStatus()
        guard hasAccessibility else {
            Logger.error("Accessibility permission missing for prompt enhancer hotkey")
            PermissionManager.shared.invalidateCache()
            PermissionManager.shared.openAccessibilitySettings()
            return
        }
        
        Task { @MainActor in
            PromptEnhancerManager.shared.enhanceSelectedText()
        }
    }

    // MARK: - Helpers
    private func readFromClipboard() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }

    private func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func simulateCopy() { simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand) }
    private func simulatePaste() { simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand) }
    private func simulateDelete() { simulateKeyPress(keyCode: CGKeyCode(kVK_ForwardDelete), flags: []) }

    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(10000)
        up.post(tap: .cghidEventTap)
    }
    
    private func showPermissionRequiredAlert() {
        DispatchQueue.main.async {
            PermissionManager.shared.openAccessibilitySettings()
        }
    }
}
