import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared

    // Local state for editing (not saved until "Save Changes" clicked)
    @State private var localConvertKeyCode: UInt32
    @State private var localConvertModifiers: UInt32

    @State private var localPromptKeyCode: UInt32
    @State private var localPromptModifiers: UInt32
    @State private var localMaxHistoryCount: Int
    @State private var localRecentHistoryRowsCount: Int
    @State private var localPlaySound: Bool
    @State private var localAutoPaste: Bool
    @State private var localGeminiKey: String
    @State private var localAIProvider: AIProvider
    @State private var localOpenRouterKey: String
    @State private var localOpenRouterModel: String

    @State private var isRecordingConvertHotkey = false
    @State private var isRecordingPromptHotkey = false
    @State private var hasUnsavedChanges = false
    @State private var showSavedMessage = false

    init() {
        // Initialize local state with current settings
        let settings = SettingsManager.shared
        _localConvertKeyCode = State(initialValue: settings.hotkeyKeyCode)
        _localConvertModifiers = State(initialValue: settings.hotkeyModifiers)

        _localPromptKeyCode = State(initialValue: settings.promptHotkeyKeyCode)
        _localPromptModifiers = State(initialValue: settings.promptHotkeyModifiers)
        _localMaxHistoryCount = State(initialValue: settings.maxHistoryCount)
        _localRecentHistoryRowsCount = State(initialValue: settings.recentHistoryRowsCount)
        _localPlaySound = State(initialValue: settings.playSoundOnConvert)
        _localAutoPaste = State(initialValue: settings.autoPasteAfterConvert)
        _localGeminiKey = State(initialValue: settings.geminiKey)
        _localAIProvider = State(initialValue: settings.selectedAIProvider)
        _localOpenRouterKey = State(initialValue: settings.openRouterKey)
        _localOpenRouterModel = State(initialValue: settings.openRouterModel)

    }

    var body: some View {
        TabView {
            // General Settings Tab
            GeneralSettingsTab(
                settings: settings,
                localConvertKeyCode: $localConvertKeyCode,
                localConvertModifiers: $localConvertModifiers,

                localPromptKeyCode: $localPromptKeyCode,
                localPromptModifiers: $localPromptModifiers,
                localMaxHistoryCount: $localMaxHistoryCount,
                localRecentHistoryRowsCount: $localRecentHistoryRowsCount,
                localPlaySound: $localPlaySound,
                localAutoPaste: $localAutoPaste,
                localGeminiKey: $localGeminiKey,
                localAIProvider: $localAIProvider,
                localOpenRouterKey: $localOpenRouterKey,
                localOpenRouterModel: $localOpenRouterModel,

                isRecordingConvertHotkey: $isRecordingConvertHotkey,

                isRecordingPromptHotkey: $isRecordingPromptHotkey,
                hasUnsavedChanges: $hasUnsavedChanges,
                showSavedMessage: $showSavedMessage,
                onSave: saveChanges,
                onReset: resetToDefaults,
                displayString: displayString
            )
            .tabItem {
                Label(NSLocalizedString("settings.general.title", comment: "General"), systemImage: "gearshape")
            }
            
            // Snippets Tab
            SnippetsTab()
                .tabItem {
                    Label(NSLocalizedString("settings.snippets.title", comment: "Snippets"), systemImage: "text.bubble")
                }
        }
        .frame(minWidth: 750, idealWidth: 800, maxWidth: 900, minHeight: 700, idealHeight: 750, maxHeight: 900)
    }
    
    // MARK: - Actions

    private func saveChanges() {
        // Validate OpenRouter API key if OpenRouter is selected
        if localAIProvider == .openRouter {
            if localOpenRouterKey.isEmpty {
                let alert = NSAlert()
                alert.messageText = "OpenRouter API Key Required"
                alert.informativeText = "Please enter your OpenRouter API key to use OpenRouter as your AI provider."
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
                alert.runModal()
                return
            }
            
            // Basic format validation
            if localOpenRouterKey.count < 20 {
                let alert = NSAlert()
                alert.messageText = "Invalid OpenRouter API Key"
                alert.informativeText = "The API key seems too short. OpenRouter API keys are typically longer. Please check your key and try again."
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
                alert.runModal()
                return
            }
            
            // Validate model name if provided
            if !localOpenRouterModel.isEmpty {
                // Basic validation: model should contain at least one slash (e.g., "deepseek/deepseek-chat")
                if !localOpenRouterModel.contains("/") {
                    let alert = NSAlert()
                    alert.messageText = "Invalid Model Name"
                    alert.informativeText = "Model name should be in the format 'provider/model-name' (e.g., 'deepseek/deepseek-chat')."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
                    alert.runModal()
                    return
                }
            }
        }
        
        // CRITICAL FIX: Validate no duplicate hotkeys before saving
        let allHotkeys = [
            (localConvertKeyCode, localConvertModifiers, NSLocalizedString("settings.text.conversion.hotkey", comment: "Convert hotkey")),

            (localPromptKeyCode, localPromptModifiers, NSLocalizedString("settings.prompt.enhancer.hotkey", comment: "Prompt hotkey"))
        ]
        
        // Check for duplicates
        for i in 0..<allHotkeys.count {
            for j in (i+1)..<allHotkeys.count {
                if allHotkeys[i].0 == allHotkeys[j].0 && 
                   allHotkeys[i].1 == allHotkeys[j].1 {
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("hotkey.duplicate.title", comment: "Duplicate Hotkey")
                    alert.informativeText = String(format: NSLocalizedString("hotkey.duplicate.between", comment: "Hotkeys %@ and %@ use the same shortcut. Please change one of them."), allHotkeys[i].2, allHotkeys[j].2)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
                    alert.runModal()
                    return // Don't save if duplicates exist
                }
            }
        }
        
        // Save all settings to UserDefaults
        settings.hotkeyKeyCode = localConvertKeyCode
        settings.hotkeyModifiers = localConvertModifiers

        settings.promptHotkeyKeyCode = localPromptKeyCode
        settings.promptHotkeyModifiers = localPromptModifiers
        settings.maxHistoryCount = localMaxHistoryCount
        settings.recentHistoryRowsCount = localRecentHistoryRowsCount
        settings.playSoundOnConvert = localPlaySound
        settings.autoPasteAfterConvert = localAutoPaste
        settings.geminiKey = localGeminiKey
        settings.selectedAIProvider = localAIProvider
        settings.openRouterKey = localOpenRouterKey
        settings.openRouterModel = localOpenRouterModel


        // Rebind hotkeys immediately
        let result = HotkeyManager.shared.rebindHotkeys()

        // Show feedback
        hasUnsavedChanges = false
        withAnimation {
            showSavedMessage = true
        }

        // Hide "Saved!" message after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showSavedMessage = false
            }
        }

        // Print results
        if result.convertSuccess && result.keyboardLockSuccess && result.promptSuccess {
            print("✓ Settings saved and hotkeys rebound successfully")
        } else {
            print("⚠️ Settings saved but some hotkeys failed to bind")
        }
    }

    private func resetToDefaults() {
        // Reset local state to defaults
        localConvertKeyCode = UInt32(kVK_ANSI_K)
        localConvertModifiers = UInt32(cmdKey | optionKey)

        localPromptKeyCode = UInt32(kVK_ANSI_P)
        localPromptModifiers = UInt32(cmdKey | optionKey)
        localMaxHistoryCount = 20
        localRecentHistoryRowsCount = 10
        localPlaySound = true
        localAutoPaste = true
        localGeminiKey = ""
        localAIProvider = .gemini
        localOpenRouterKey = ""
        localOpenRouterModel = "deepseek/deepseek-chat"

        hasUnsavedChanges = true
    }

    private func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
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
}

// MARK: - Hotkey Recorder Button

struct HotkeyRecorderButton: NSViewRepresentable {
    @Binding var isRecording: Bool
    let currentHotkey: String
    let onHotkeyRecorded: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onHotkeyRecorded = onHotkeyRecorded
        view.isRecording = isRecording
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.currentHotkeyText = currentHotkey
        nsView.isRecording = isRecording
    }
}

// MARK: - Native Hotkey Recorder View

class HotkeyRecorderView: NSView {
    var currentHotkeyText: String = "" {
        didSet {
            needsDisplay = true
        }
    }

    var isRecording: Bool = false {
        didSet {
            needsDisplay = true
            if isRecording {
                startRecording()
            } else {
                stopRecording()
            }
        }
    }

    var onHotkeyRecorded: ((UInt32, UInt32) -> Void)?
    private var localMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor

        // Add click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewClicked))
        addGestureRecognizer(clickGesture)
    }

    @objc private func viewClicked() {
        isRecording.toggle()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background
        let backgroundColor = isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.1) : NSColor.controlBackgroundColor
        backgroundColor.setFill()
        bounds.fill()

        // Border
        layer?.borderColor = isRecording ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor

        // Text
        let text = isRecording ? "Press your key combination..." : currentHotkeyText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]

        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        text.draw(in: textRect, withAttributes: attributes)
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 250, height: 44)
    }

    private func startRecording() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // Capture key code and modifiers
            let keyCode = UInt32(event.keyCode)
            var modifiers: UInt32 = 0

            if event.modifierFlags.contains(.control) {
                modifiers |= UInt32(controlKey)
            }
            if event.modifierFlags.contains(.option) {
                modifiers |= UInt32(optionKey)
            }
            if event.modifierFlags.contains(.shift) {
                modifiers |= UInt32(shiftKey)
            }
            if event.modifierFlags.contains(.command) {
                modifiers |= UInt32(cmdKey)
            }

            // Require at least one modifier and a valid key
            if event.type == .keyDown && modifiers != 0 && keyCode != 0 {
                // CRITICAL FIX: Check if shortcut is already in use
                let shortcutService = KeyboardShortcutService.shared
                let isAvailable = shortcutService.isKeyCombinationAvailable(keyCode: keyCode, modifiers: modifiers)
                
                if !isAvailable {
                    // Show error alert to user
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("hotkey.duplicate.title", comment: "Duplicate Hotkey")
                        alert.informativeText = NSLocalizedString("hotkey.duplicate.message", comment: "This hotkey is already in use. Please choose a different one.")
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
                        alert.runModal()
                    }
                    self.isRecording = false
                    return nil // Consume event
                }
                
                self.onHotkeyRecorded?(keyCode, modifiers)
                self.isRecording = false
                return nil // Consume event
            }

            return nil // Consume all events while recording
        }

        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        stopRecording()
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
