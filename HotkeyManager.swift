import Cocoa
import Carbon
import ApplicationServices

class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHotKeyRef: EventHotKeyRef?
    private var ocrHotKeyRef: EventHotKeyRef?
    private var keyboardLockHotKeyRef: EventHotKeyRef?
    private var promptHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // Hotkey signatures
    private let hotkeyID = EventHotKeyID(signature: OSType(0x4A4F5941), id: 1) // 'JOYA'
    private let ocrHotkeyID = EventHotKeyID(signature: OSType(0x4F435231), id: 2) // 'OCR1'
    private let keyboardLockHotkeyID = EventHotKeyID(signature: OSType(0x4B424C4B), id: 3) // 'KBLK'
    private let promptHotkeyID = EventHotKeyID(signature: OSType(0x50524F4D), id: 4) // 'PROM'

    private let settings = SettingsManager.shared

    private init() {}

    // MARK: - Rebind Hotkeys

    /// Rebinds all hotkeys with current settings from UserDefaults
    /// Call this after saving new hotkey settings to apply changes immediately
    @discardableResult
    func rebindHotkeys() -> (convertSuccess: Bool, ocrSuccess: Bool, keyboardLockSuccess: Bool, promptSuccess: Bool) {
        print("🔄 Rebinding hotkeys...")

        // Step 1: Unregister all existing hotkeys
        unregisterHotkey()

        // Step 2: Small delay to ensure system processes the unregistration
        usleep(50000) // 50ms

        // Step 3: Register hotkeys with new settings from UserDefaults
        let convertSuccess = registerHotkey()
        let ocrSuccess = registerOCRHotkey()
        let keyboardLockSuccess = registerKeyboardLockHotkey()
        let promptSuccess = registerPromptHotkey()

        // Step 4: Report results
        if convertSuccess && ocrSuccess && keyboardLockSuccess && promptSuccess {
            print("✓ All hotkeys rebound successfully")
            SoundManager.shared.playSuccess()
        } else {
            print("⚠️ Some hotkeys failed to rebind")
            if !convertSuccess {
                print("  - Text conversion hotkey failed")
            }
            if !ocrSuccess {
                print("  - OCR hotkey failed")
            }
            if !keyboardLockSuccess {
                print("  - Keyboard lock hotkey failed")
            }
            if !promptSuccess {
                print("  - Prompt enhancer hotkey failed")
            }
        }

        return (convertSuccess, ocrSuccess, keyboardLockSuccess, promptSuccess)
    }

    // MARK: - Registration

    /// Registers the global hotkey using settings
    func registerHotkey() -> Bool {
        // Get hotkey from settings
        let keyCode = settings.hotkeyKeyCode
        let modifiers = settings.hotkeyModifiers

        print("🔧 Registering hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")

        // Create event type spec for hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))

        // Install shared event handler if not already installed
        if eventHandler == nil {
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (nextHandler, event, userData) -> OSStatus in
                    var hotkeyID = EventHotKeyID()
                    GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotkeyID
                    )

                    // Check which hotkey was pressed
                    if hotkeyID.id == 1 {
                        HotkeyManager.shared.hotkeyPressed()
                    } else if hotkeyID.id == 2 {
                        HotkeyManager.shared.ocrHotkeyPressed()
                    } else if hotkeyID.id == 3 {
                        HotkeyManager.shared.keyboardLockHotkeyPressed()
                    } else if hotkeyID.id == 4 {
                        HotkeyManager.shared.promptHotkeyPressed()
                    }

                    return noErr
                },
                1,
                &eventType,
                nil,
                &eventHandler
            )

            guard status == noErr else {
                print("Failed to install event handler: \(status)")
                return false
            }
        }

        // Register the hotkey
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )

        guard registerStatus == noErr else {
            let errorMessage = getErrorMessage(for: registerStatus)
            print("❌ Failed to register conversion hotkey: \(errorMessage)")
            print("   Attempted: \(settings.hotkeyDisplayString)")
            print("   This key combination may be reserved by the system or another app")
            return false
        }

        print("✓ Conversion hotkey registered: \(settings.hotkeyDisplayString)")
        return true
    }

    /// Registers the OCR hotkey using settings
    func registerOCRHotkey() -> Bool {
        // Get OCR hotkey from settings
        let keyCode = settings.ocrHotkeyKeyCode
        let modifiers = settings.ocrHotkeyModifiers

        print("🔧 Registering OCR hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")

        // Create event type spec for hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))

        // Use existing event handler
        if eventHandler == nil {
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (nextHandler, event, userData) -> OSStatus in
                    var hotkeyID = EventHotKeyID()
                    GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotkeyID
                    )

                    // Check which hotkey was pressed
                    if hotkeyID.id == 1 {
                        HotkeyManager.shared.hotkeyPressed()
                    } else if hotkeyID.id == 2 {
                        HotkeyManager.shared.ocrHotkeyPressed()
                    } else if hotkeyID.id == 3 {
                        HotkeyManager.shared.keyboardLockHotkeyPressed()
                    } else if hotkeyID.id == 4 {
                        HotkeyManager.shared.promptHotkeyPressed()
                    }

                    return noErr
                },
                1,
                &eventType,
                nil,
                &eventHandler
            )

            guard status == noErr else {
                print("Failed to install event handler: \(status)")
                return false
            }
        }

        // Register the OCR hotkey
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            ocrHotkeyID,
            GetApplicationEventTarget(),
            0,
            &ocrHotKeyRef
        )

        guard registerStatus == noErr else {
            let errorMessage = getErrorMessage(for: registerStatus)
            let ocrHotkeyDisplay = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
            print("❌ Failed to register OCR hotkey: \(errorMessage)")
            print("   Attempted: \(ocrHotkeyDisplay)")
            print("   This key combination may be reserved by the system or another app")
            return false
        }

        let ocrHotkeyDisplay = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
        print("✓ OCR hotkey registered: \(ocrHotkeyDisplay)")
        return true
    }

    /// Registers the keyboard lock hotkey (Cmd+Option+L)
    func registerKeyboardLockHotkey() -> Bool {
        let keyCode = UInt32(kVK_ANSI_L)
        let modifiers = UInt32(cmdKey | optionKey)
        
        print("🔧 Registering keyboard lock hotkey: Cmd+Option+L")
        
        // Create event type spec for hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        
        // Use existing event handler
        if eventHandler == nil {
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (nextHandler, event, userData) -> OSStatus in
                    var hotkeyID = EventHotKeyID()
                    GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotkeyID
                    )
                    
                    // Check which hotkey was pressed
                    if hotkeyID.id == 1 {
                        HotkeyManager.shared.hotkeyPressed()
                    } else if hotkeyID.id == 2 {
                        HotkeyManager.shared.ocrHotkeyPressed()
                    } else if hotkeyID.id == 3 {
                        HotkeyManager.shared.keyboardLockHotkeyPressed()
                    }
                    
                    return noErr
                },
                1,
                &eventType,
                nil,
                &eventHandler
            )
            
            guard status == noErr else {
                print("Failed to install event handler")
                return false
            }
        }
        
        // Register the keyboard lock hotkey
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            keyboardLockHotkeyID,
            GetApplicationEventTarget(),
            0,
            &keyboardLockHotKeyRef
        )
        
        guard registerStatus == noErr else {
            let errorMessage = getErrorMessage(for: registerStatus)
            print("❌ Failed to register keyboard lock hotkey: \(errorMessage)")
            return false
        }
        
        print("✓ Keyboard lock hotkey registered: ⌘⌥L")
        return true
    }
    
    /// Registers the prompt enhancer hotkey using settings
    func registerPromptHotkey() -> Bool {
        // Get prompt hotkey from settings
        let keyCode = settings.promptHotkeyKeyCode
        let modifiers = settings.promptHotkeyModifiers
        
        print("🔧 Registering prompt enhancer hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")
        
        // Create event type spec for hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        
        // Use existing event handler
        if eventHandler == nil {
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (nextHandler, event, userData) -> OSStatus in
                    var hotkeyID = EventHotKeyID()
                    GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotkeyID
                    )
                    
                    // Check which hotkey was pressed
                    if hotkeyID.id == 1 {
                        HotkeyManager.shared.hotkeyPressed()
                    } else if hotkeyID.id == 2 {
                        HotkeyManager.shared.ocrHotkeyPressed()
                    } else if hotkeyID.id == 3 {
                        HotkeyManager.shared.keyboardLockHotkeyPressed()
                    } else if hotkeyID.id == 4 {
                        HotkeyManager.shared.promptHotkeyPressed()
                    }
                    
                    return noErr
                },
                1,
                &eventType,
                nil,
                &eventHandler
            )
            
            guard status == noErr else {
                print("Failed to install event handler")
                return false
            }
        }
        
        // Register the prompt hotkey
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            promptHotkeyID,
            GetApplicationEventTarget(),
            0,
            &promptHotKeyRef
        )
        
        guard registerStatus == noErr else {
            let errorMessage = getErrorMessage(for: registerStatus)
            let promptHotkeyDisplay = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
            print("❌ Failed to register prompt enhancer hotkey: \(errorMessage)")
            print("   Attempted: \(promptHotkeyDisplay)")
            print("   This key combination may be reserved by the system or another app")
            return false
        }
        
        let promptHotkeyDisplay = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
        print("✓ Prompt enhancer hotkey registered: \(promptHotkeyDisplay)")
        return true
    }
    
    /// Unregisters all global hotkeys
    func unregisterHotkey() {
        if let eventHotKeyRef = eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
            self.eventHotKeyRef = nil
        }

        if let ocrHotKeyRef = ocrHotKeyRef {
            UnregisterEventHotKey(ocrHotKeyRef)
            self.ocrHotKeyRef = nil
        }
        
        if let keyboardLockHotKeyRef = keyboardLockHotKeyRef {
            UnregisterEventHotKey(keyboardLockHotKeyRef)
            self.keyboardLockHotKeyRef = nil
        }
        
        if let promptHotKeyRef = promptHotKeyRef {
            UnregisterEventHotKey(promptHotKeyRef)
            self.promptHotKeyRef = nil
        }

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Returns a human-readable string for any hotkey combination
    private func hotkeyDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var modifierString = ""

        if modifiers & UInt32(controlKey) != 0 {
            modifierString += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            modifierString += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            modifierString += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            modifierString += "⌘"
        }

        let keyString = settings.keyCodeToString(Int(keyCode))
        return modifierString + keyString
    }

    // MARK: - Hotkey Action

    /// Called when the global hotkey is pressed
    private func hotkeyPressed() {
        print("🔥 Hotkey pressed! Converting text...")
        
        // CRITICAL: Check permissions at the moment the key is pressed
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            print("⚠️ Accessibility permission missing - showing alert")
            showPermissionRequiredAlert(for: "Accessibility", reason: "simulate keyboard shortcuts (Cmd+C, Cmd+V, Delete)")
            return
        }

        // Call the public conversion method
        performTextConversion()
    }
    
    /// Public method to perform text conversion (can be called from UI)
    /// This method handles the full conversion flow: copy, convert, paste
    func performTextConversion() {
        // Step 1: Simulate Cmd+C to copy selected text
        simulateCopy()

        // Step 2: Wait for clipboard to update
        DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.textConversionClipboardDelay) {
            // Step 3: Read from clipboard
            guard let copiedText = self.readFromClipboard() else {
                print("❌ No text in clipboard")
                return
            }

            print("📋 Original: '\(copiedText)'")

            // Step 4: Convert the text
            let convertedText = TextConverter.convert(copiedText)
            print("✅ Converted: '\(convertedText)'")

            // Step 5: Notify clipboard manager to ignore this write
            ClipboardHistoryManager.shared.notifyInternalWrite()

            // Step 6: Write back to clipboard
            self.writeToClipboard(convertedText)
            print("📋 Converted text written to clipboard")

            // Step 7: Delete selected text, then paste (if enabled in settings)
            DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.clipboardPasteDelay) {
                if self.settings.autoPasteAfterConvert {
                    // Delete the selected text first
                    print("🗑️ Deleting selected text...")
                    self.simulateDelete()
                    
                    // Wait a bit before pasting
                    DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.textConversionDeleteDelay) {
                        print("📋 Simulating paste...")
                        self.simulatePaste()
                        
                        // Step 8: Play success sound (if enabled in settings)
                        if self.settings.playSoundOnConvert {
                            SoundManager.shared.playSuccess()
                        }
                    }
                } else {
                    print("⚠️ Auto-paste is disabled in settings")
                    // Still play sound even if not pasting
                    if self.settings.playSoundOnConvert {
                        SoundManager.shared.playSuccess()
                    }
                }
            }
        }
    }

    /// Called when the OCR hotkey is pressed
    private func ocrHotkeyPressed() {
        print("📸 OCR Hotkey pressed! Starting screen capture...")
        
        // Note: Screen Recording permission is handled by ScreenCaptureManager
        // when screencapture command is executed
        
        // ScreenCaptureManager now handles confirmation, OCR, saving to history, and copying to clipboard
        // CRITICAL FIX: Must call MainActor-isolated method from MainActor context
        Task { @MainActor in
            ScreenCaptureManager.shared.startScreenCapture { extractedText in
                if let text = extractedText, !text.isEmpty {
                    print("✓ OCR completed: \(text.count) characters extracted and saved to OCR history")
                } else {
                    print("⚠️ OCR was cancelled or failed")
                }
            }
        }
    }
    
    /// Called when the keyboard lock hotkey is pressed
    private func keyboardLockHotkeyPressed() {
        print("🔒 Keyboard lock hotkey pressed!")
        KeyboardBlocker.shared.toggleLock()
    }
    
    /// Called when the prompt enhancer hotkey is pressed
    private func promptHotkeyPressed() {
        print("✨ Prompt enhancer hotkey pressed!")
        Task { @MainActor in
            PromptEnhancerManager.shared.enhanceSelectedText()
        }
    }

    // MARK: - Clipboard Operations

    /// Reads string from the system clipboard
    private func readFromClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
    }

    /// Writes string to the system clipboard
    private func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Key Simulation

    /// Simulates Cmd+C key press (Copy)
    private func simulateCopy() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }

    /// Simulates Cmd+V key press (Paste)
    private func simulatePaste() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    /// Simulates Delete/ForwardDelete key press
    private func simulateDelete() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ForwardDelete), flags: [])
    }

    /// Simulates a key press with modifier keys
    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        // Key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            print("Failed to create key down event")
            return
        }
        keyDownEvent.flags = flags

        // Key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            print("Failed to create key up event")
            return
        }
        keyUpEvent.flags = flags

        // Post events
        let location = CGEventTapLocation.cghidEventTap
        keyDownEvent.post(tap: location)

        // Small delay between key down and up
        usleep(10000) // 10ms

        keyUpEvent.post(tap: location)
    }

    // MARK: - Accessibility Check

    /// Checks if the app has accessibility permissions (required for key simulation)
    static func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            print("⚠️ Accessibility permissions required!")
            print("Go to: System Preferences → Security & Privacy → Privacy → Accessibility")
            print("Enable access for this app to simulate key presses.")
        }

        return accessEnabled
    }

    // MARK: - Error Handling

    /// Converts Carbon error code to readable message
    private func getErrorMessage(for status: OSStatus) -> String {
        switch status {
        case -9850: return "Hotkey already registered (duplicate)"
        case -9879: return "Invalid hotkey parameters"
        case -50: return "Parameter error"
        default: return "Error code \(status)"
        }
    }
    
    // MARK: - Permission Alerts
    
    /// Shows an alert when permissions are missing
    private func showPermissionRequiredAlert(for permission: String, reason: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = String(format: NSLocalizedString("alert.accessibility.title", comment: "Permission alert title"), permission)
            alert.informativeText = String(format: NSLocalizedString("alert.accessibility.message", comment: "Permission alert message"), permission, reason)
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("alert.button.open.settings", comment: "Open settings"))
            alert.addButton(withTitle: NSLocalizedString("alert.button.cancel", comment: "Cancel"))
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                if permission == "Accessibility" {
                    PermissionManager.shared.openAccessibilitySettings()
                } else if permission == "Screen Recording" {
                    PermissionManager.shared.openScreenRecordingSettings()
                }
            }
        }
    }
}
