import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared

    // Local state for editing (not saved until "Save Changes" clicked)
    @State private var localConvertKeyCode: UInt32
    @State private var localConvertModifiers: UInt32
    @State private var localOCRKeyCode: UInt32
    @State private var localOCRModifiers: UInt32
    @State private var localPromptKeyCode: UInt32
    @State private var localPromptModifiers: UInt32
    @State private var localMaxHistoryCount: Int
    @State private var localPlaySound: Bool
    @State private var localAutoPaste: Bool
    @State private var localGeminiKey: String
    @State private var localUseCloudOCR: Bool

    @State private var isRecordingConvertHotkey = false
    @State private var isRecordingOCRHotkey = false
    @State private var isRecordingPromptHotkey = false
    @State private var hasUnsavedChanges = false
    @State private var showSavedMessage = false

    init() {
        // Initialize local state with current settings
        let settings = SettingsManager.shared
        _localConvertKeyCode = State(initialValue: settings.hotkeyKeyCode)
        _localConvertModifiers = State(initialValue: settings.hotkeyModifiers)
        _localOCRKeyCode = State(initialValue: settings.ocrHotkeyKeyCode)
        _localOCRModifiers = State(initialValue: settings.ocrHotkeyModifiers)
        _localPromptKeyCode = State(initialValue: settings.promptHotkeyKeyCode)
        _localPromptModifiers = State(initialValue: settings.promptHotkeyModifiers)
        _localMaxHistoryCount = State(initialValue: settings.maxHistoryCount)
        _localPlaySound = State(initialValue: settings.playSoundOnConvert)
        _localAutoPaste = State(initialValue: settings.autoPasteAfterConvert)
        _localGeminiKey = State(initialValue: settings.geminiKey)
        _localUseCloudOCR = State(initialValue: settings.useCloudOCR)
    }

    var body: some View {
        TabView {
            // General Settings Tab
            GeneralSettingsTab(
                settings: settings,
                localConvertKeyCode: $localConvertKeyCode,
                localConvertModifiers: $localConvertModifiers,
                localOCRKeyCode: $localOCRKeyCode,
                localOCRModifiers: $localOCRModifiers,
                localPromptKeyCode: $localPromptKeyCode,
                localPromptModifiers: $localPromptModifiers,
                localMaxHistoryCount: $localMaxHistoryCount,
                localPlaySound: $localPlaySound,
                localAutoPaste: $localAutoPaste,
                localGeminiKey: $localGeminiKey,
                localUseCloudOCR: $localUseCloudOCR,
                isRecordingConvertHotkey: $isRecordingConvertHotkey,
                isRecordingOCRHotkey: $isRecordingOCRHotkey,
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
        .frame(width: 600, height: 550)
    }
    
    // MARK: - Actions

    private func saveChanges() {
        // Save all settings to UserDefaults
        settings.hotkeyKeyCode = localConvertKeyCode
        settings.hotkeyModifiers = localConvertModifiers
        settings.ocrHotkeyKeyCode = localOCRKeyCode
        settings.ocrHotkeyModifiers = localOCRModifiers
        settings.promptHotkeyKeyCode = localPromptKeyCode
        settings.promptHotkeyModifiers = localPromptModifiers
        settings.maxHistoryCount = localMaxHistoryCount
        settings.playSoundOnConvert = localPlaySound
        settings.autoPasteAfterConvert = localAutoPaste
        settings.geminiKey = localGeminiKey
        settings.useCloudOCR = localUseCloudOCR

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
        if result.convertSuccess && result.ocrSuccess && result.keyboardLockSuccess && result.promptSuccess {
            print("✓ Settings saved and hotkeys rebound successfully")
        } else {
            print("⚠️ Settings saved but some hotkeys failed to bind")
        }
    }

    private func resetToDefaults() {
        // Reset local state to defaults
        localConvertKeyCode = UInt32(kVK_ANSI_K)
        localConvertModifiers = UInt32(cmdKey | optionKey)
        localOCRKeyCode = UInt32(kVK_ANSI_X)
        localOCRModifiers = UInt32(cmdKey | optionKey)
        localPromptKeyCode = UInt32(kVK_ANSI_P)
        localPromptModifiers = UInt32(cmdKey | optionKey)
        localMaxHistoryCount = 20
        localPlaySound = true
        localAutoPaste = true
        localGeminiKey = ""
        localUseCloudOCR = false

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
