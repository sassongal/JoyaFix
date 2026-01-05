import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared

    // Local state for editing (not saved until "Save Changes" clicked)
    @State private var localConvertKeyCode: UInt32
    @State private var localConvertModifiers: UInt32
    @State private var localOCRKeyCode: UInt32
    @State private var localOCRModifiers: UInt32
    @State private var localMaxHistoryCount: Int
    @State private var localPlaySound: Bool
    @State private var localAutoPaste: Bool
    @State private var localGeminiKey: String
    @State private var localUseCloudOCR: Bool

    @State private var isRecordingConvertHotkey = false
    @State private var isRecordingOCRHotkey = false
    @State private var hasUnsavedChanges = false
    @State private var showSavedMessage = false

    init() {
        // Initialize local state with current settings
        let settings = SettingsManager.shared
        _localConvertKeyCode = State(initialValue: settings.hotkeyKeyCode)
        _localConvertModifiers = State(initialValue: settings.hotkeyModifiers)
        _localOCRKeyCode = State(initialValue: settings.ocrHotkeyKeyCode)
        _localOCRModifiers = State(initialValue: settings.ocrHotkeyModifiers)
        _localMaxHistoryCount = State(initialValue: settings.maxHistoryCount)
        _localPlaySound = State(initialValue: settings.playSoundOnConvert)
        _localAutoPaste = State(initialValue: settings.autoPasteAfterConvert)
        _localGeminiKey = State(initialValue: settings.geminiKey)
        _localUseCloudOCR = State(initialValue: settings.useCloudOCR)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("JoyaFix Settings")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding()

            Divider()

            // Settings Form
            ScrollView {
                VStack(spacing: 20) {
                    // Text Conversion Hotkey Section
                    GroupBox(label: Label("Text Conversion Hotkey", systemImage: "keyboard")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Press the button and type your desired key combination:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HotkeyRecorderButton(
                                isRecording: $isRecordingConvertHotkey,
                                currentHotkey: displayString(keyCode: localConvertKeyCode, modifiers: localConvertModifiers)
                            ) { keyCode, modifiers in
                                localConvertKeyCode = keyCode
                                localConvertModifiers = modifiers
                                hasUnsavedChanges = true
                            }
                        }
                        .padding(8)
                    }

                    // OCR Hotkey Section
                    GroupBox(label: Label("OCR Screen Capture Hotkey", systemImage: "viewfinder")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Press the button and type your desired key combination:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HotkeyRecorderButton(
                                isRecording: $isRecordingOCRHotkey,
                                currentHotkey: displayString(keyCode: localOCRKeyCode, modifiers: localOCRModifiers)
                            ) { keyCode, modifiers in
                                localOCRKeyCode = keyCode
                                localOCRModifiers = modifiers
                                hasUnsavedChanges = true
                            }
                        }
                        .padding(8)
                    }

                    // History Section
                    GroupBox(label: Label("Clipboard History", systemImage: "clock.arrow.circlepath")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Maximum items to save:")
                                Spacer()
                                Stepper("\(localMaxHistoryCount)", value: $localMaxHistoryCount, in: 5...100, step: 5)
                                    .frame(width: 120)
                                    .onChange(of: localMaxHistoryCount) { _, _ in
                                        hasUnsavedChanges = true
                                    }
                            }

                            Text("Currently saving last \(localMaxHistoryCount) items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }

                    // Behavior Section
                    GroupBox(label: Label("Behavior", systemImage: "slider.horizontal.3")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Play sound on text conversion", isOn: $localPlaySound)
                                .onChange(of: localPlaySound) { _, _ in
                                    hasUnsavedChanges = true
                                }

                            Toggle("Auto-paste after conversion", isOn: $localAutoPaste)
                                .onChange(of: localAutoPaste) { _, _ in
                                    hasUnsavedChanges = true
                                }
                        }
                        .padding(8)
                    }

                    // OCR Configuration Section
                    GroupBox(label: Label("OCR Configuration", systemImage: "cloud.fill")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Use Cloud OCR (Gemini 1.5 Flash)", isOn: $localUseCloudOCR)
                                .onChange(of: localUseCloudOCR) { _, _ in
                                    hasUnsavedChanges = true
                                }

                            if localUseCloudOCR {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Gemini API Key:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    SecureField("Enter your API key...", text: $localGeminiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: localGeminiKey) { _, _ in
                                            hasUnsavedChanges = true
                                        }

                                    Text("Get your free key at aistudio.google.com")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Your API key is stored securely and only used for OCR requests.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Cloud OCR uses Google's Gemini 1.5 Flash for improved accuracy, especially for Hebrew text.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }

            Divider()

            // Bottom Action Bar
            HStack(spacing: 12) {
                // Reset to Defaults
                Button(action: resetToDefaults) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)

                Spacer()

                // Unsaved changes indicator
                if hasUnsavedChanges {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Save confirmation message
                if showSavedMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved!")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .transition(.opacity)
                }

                // Save Button
                Button(action: saveChanges) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Changes")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges)
                .controlSize(.large)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
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
        if result.convertSuccess && result.ocrSuccess {
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
