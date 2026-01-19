import SwiftUI
import Carbon
import UniformTypeIdentifiers

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @ObservedObject var settings: SettingsManager
    @Binding var localConvertKeyCode: UInt32
    @Binding var localConvertModifiers: UInt32
    @Binding var localPromptKeyCode: UInt32
    @Binding var localPromptModifiers: UInt32
    @Binding var localMaxHistoryCount: Int
    @Binding var localRecentHistoryRowsCount: Int
    @Binding var localPlaySound: Bool
    @Binding var localAutoPaste: Bool
    @Binding var localGeminiKey: String
    @Binding var localAIProvider: AIProvider
    @Binding var localOpenRouterKey: String
    @Binding var localOpenRouterModel: String
    @Binding var localSelectedModel: String?
    @Binding var isRecordingConvertHotkey: Bool
    @Binding var isRecordingPromptHotkey: Bool
    @Binding var hasUnsavedChanges: Bool
    @Binding var showSavedMessage: Bool
    let onSave: () -> Void
    let onReset: () -> Void
    let displayString: (UInt32, UInt32) -> String
    
    @State private var showExportSuccess = false
    @State private var showImportSuccess = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var showLanguageRestartAlert = false

    // Double-click prevention for file operations
    @State private var isExporting = false
    @State private var isImporting = false
    
    // Permission status tracking
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var microphoneGranted = false
    @State private var speechRecognitionGranted = false
    private let permissionManager = PermissionManager.shared
    
    // OpenRouter API Key validation
    @State private var isTestingOpenRouterKey = false
    @State private var openRouterKeyStatus: APIKeyStatus = .unknown
    @State private var openRouterKeyErrorMessage: String = ""
    
    enum APIKeyStatus {
        case unknown
        case testing
        case valid
        case invalid(String)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    settingsContentGroupBoxes
                }
                .padding()
            }

            Divider()

            // Bottom Action Bar
            settingsActionBar
        }
    }

    private var settingsContentGroupBoxes: some View {
        VStack(spacing: 20) {
            // Text Conversion Hotkey Section
            GroupBox(label: Label(NSLocalizedString("settings.text.conversion.hotkey", comment: "Text conversion hotkey"), systemImage: "keyboard")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("settings.text.conversion.hotkey.description", comment: "Hotkey description"))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HotkeyRecorderButton(
                                isRecording: $isRecordingConvertHotkey,
                                currentHotkey: displayString(localConvertKeyCode, localConvertModifiers)
                            ) { keyCode, modifiers in
                                localConvertKeyCode = keyCode
                                localConvertModifiers = modifiers
                                hasUnsavedChanges = true
                            }
                        }
                        .padding(8)
                    }

                    // Prompt Enhancer Hotkey Section
                    GroupBox(label: Label(NSLocalizedString("settings.prompt.enhancer.hotkey", comment: "Prompt enhancer hotkey"), systemImage: "sparkles")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("settings.prompt.enhancer.hotkey.description", comment: "Prompt enhancer hotkey description"))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HotkeyRecorderButton(
                                isRecording: $isRecordingPromptHotkey,
                                currentHotkey: displayString(localPromptKeyCode, localPromptModifiers)
                            ) { keyCode, modifiers in
                                localPromptKeyCode = keyCode
                                localPromptModifiers = modifiers
                                hasUnsavedChanges = true
                            }
                        }
                        .padding(8)
                    }

                    // History Section
                    GroupBox(label: Label(NSLocalizedString("settings.clipboard.history", comment: "Clipboard history"), systemImage: "clock.arrow.circlepath")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(NSLocalizedString("settings.clipboard.history.max.items", comment: "Max items"))
                                Spacer()
                                Stepper("\(localMaxHistoryCount)", value: $localMaxHistoryCount, in: 5...100, step: 5)
                                    .frame(width: 120)
                                    .onChange(of: localMaxHistoryCount) { _, _ in
                                        hasUnsavedChanges = true
                                    }
                            }

                            Text(String(format: NSLocalizedString("settings.clipboard.history.current", comment: "Current items"), localMaxHistoryCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Divider()
                            
                            HStack {
                                Text(NSLocalizedString("settings.recent.history.rows", comment: "Recent History Rows"))
                                Spacer()
                                Stepper("\(localRecentHistoryRowsCount)", value: $localRecentHistoryRowsCount, in: 5...20, step: 1)
                                    .frame(width: 120)
                                    .onChange(of: localRecentHistoryRowsCount) { _, _ in
                                        hasUnsavedChanges = true
                                    }
                            }
                            
                            Text(NSLocalizedString("settings.recent.history.rows.description", comment: "Recent history description"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }

                    // Behavior Section
                    GroupBox(label: Label(NSLocalizedString("settings.behavior", comment: "Behavior"), systemImage: "slider.horizontal.3")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(NSLocalizedString("settings.behavior.play.sound", comment: "Play sound"), isOn: $localPlaySound)
                                .onChange(of: localPlaySound) { _, _ in
                                    hasUnsavedChanges = true
                                }

                            Toggle(NSLocalizedString("settings.behavior.auto.paste", comment: "Auto paste"), isOn: $localAutoPaste)
                                .onChange(of: localAutoPaste) { _, _ in
                                    hasUnsavedChanges = true
                                }
                        }
                        .padding(8)
                    }
                    
                    // Permissions Section
                    GroupBox(label: Label(NSLocalizedString("settings.permissions.title", comment: "Permissions"), systemImage: "lock.shield")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("settings.permissions.description", comment: "Permissions description"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            // Accessibility Permission
                            SettingsPermissionRow(
                                title: NSLocalizedString("settings.permissions.accessibility.title", comment: "Accessibility"),
                                description: NSLocalizedString("settings.permissions.accessibility.description", comment: "Accessibility description"),
                                isGranted: accessibilityGranted,
                                icon: "hand.point.up.left.fill",
                                onOpenSettings: {
                                    permissionManager.openAccessibilitySettings()
                                }
                            )
                            
                            Divider()
                            
                            // Screen Recording Permission
                            SettingsPermissionRow(
                                title: NSLocalizedString("settings.permissions.screen.recording.title", comment: "Screen Recording"),
                                description: NSLocalizedString("settings.permissions.screen.recording.description", comment: "Screen Recording description"),
                                isGranted: screenRecordingGranted,
                                icon: "camera.fill",
                                onOpenSettings: {
                                    permissionManager.openScreenRecordingSettings()
                                }
                            )
                            
                            Divider()
                            
                            // Microphone Permission
                            SettingsPermissionRow(
                                title: NSLocalizedString("settings.microphone.title", comment: "Microphone"),
                                description: NSLocalizedString("settings.microphone.description", comment: "Microphone description"),
                                isGranted: microphoneGranted,
                                icon: "mic.fill",
                                onOpenSettings: {
                                    permissionManager.openMicrophoneSettings()
                                }
                            )
                            
                            Divider()
                            
                            // Speech Recognition Permission
                            SettingsPermissionRow(
                                title: NSLocalizedString("settings.speech.recognition.title", comment: "Speech Recognition"),
                                description: NSLocalizedString("settings.speech.recognition.description", comment: "Speech recognition description"),
                                isGranted: speechRecognitionGranted,
                                icon: "waveform",
                                onOpenSettings: {
                                    permissionManager.openSpeechRecognitionSettings()
                                }
                            )
                            
                            // Refresh button
                            HStack {
                                Spacer()
                                Button(action: {
                                    refreshPermissionStatus()
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text(NSLocalizedString("settings.permissions.refresh", comment: "Refresh"))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                        }
                        .padding(8)
                    }
                    .onAppear {
                        refreshPermissionStatus()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        // Refresh permissions when app becomes active (user might have changed them in Settings)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            refreshPermissionStatus()
                        }
                    }
                    
                    // System Integration Section
                    GroupBox(label: Label(NSLocalizedString("settings.system.integration", comment: "System Integration"), systemImage: "gear")) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Launch at Login
                            LaunchAtLoginToggle()
                            
                            Divider()
                            
                            // Check for Updates
                            HStack {
                                Text(NSLocalizedString("settings.check.updates", comment: "Check for Updates"))
                                    .font(.body)
                                Spacer()
                                Button(action: {
                                    checkForUpdates()
                                }) {
                                    HStack {
                                        if updateManager.isCheckingForUpdates {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .frame(width: 16, height: 16)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Text(updateManager.isCheckingForUpdates
                                            ? NSLocalizedString("settings.check.updates.checking", comment: "Checking...")
                                            : NSLocalizedString("settings.check.updates.button", comment: "Check Now"))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(updateManager.isCheckingForUpdates)
                            }
                            
                            Divider()
                            
                            // Show Onboarding Again
                            HStack {
                                Text(NSLocalizedString("settings.show.onboarding", comment: "Show Onboarding Again"))
                                    .font(.body)
                                Spacer()
                                Button(action: {
                                    // Reset onboarding flag and show onboarding
                                    UserDefaults.standard.set(false, forKey: JoyaFixConstants.UserDefaultsKeys.hasCompletedOnboarding)
                                    OnboardingWindowController.shared.show {
                                        Logger.info("Onboarding shown again from Settings")
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text(NSLocalizedString("settings.show.onboarding.button", comment: "Show Again"))
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(8)
                    }
                    
                    // Language Selection Section
                    GroupBox(label: Label(NSLocalizedString("settings.language.title", comment: "Language"), systemImage: "globe")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(NSLocalizedString("settings.app.language", comment: "App Language"))
                                Spacer()
                                Picker("", selection: Binding(
                                    get: {
                                        // Check if a specific language is set
                                        UserDefaults.standard.array(forKey: "AppleLanguages")?.first as? String == "en" ? "en" : "system"
                                    },
                                    set: { newValue in
                                        if newValue == "en" {
                                            // Force English
                                            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
                                        } else {
                                            // Reset to system default
                                            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                                        }
                                        // Show message that restart is required
                                        showLanguageRestartAlert = true
                                    }
                                )) {
                                    Text(NSLocalizedString("settings.language.system.default", comment: "System Default")).tag("system")
                                    Text(NSLocalizedString("settings.language.english.force", comment: "English (Force)")).tag("en")
                                }
                                .frame(width: 150)
                            }
                            Text(NSLocalizedString("settings.language.restart.required", comment: "Restart required"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }

                    // AI Provider Configuration Section
                    GroupBox(label: Label(NSLocalizedString("settings.api.configuration", comment: "API Configuration"), systemImage: "key.fill")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("settings.api.configuration.description", comment: "API configuration description"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Provider Picker
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(NSLocalizedString("settings.ai.provider", comment: "AI Provider"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button(action: {
                                        let alert = NSAlert()
                                        alert.messageText = NSLocalizedString("settings.ai.provider.info.title", comment: "AI Provider Selection")
                                        alert.informativeText = NSLocalizedString("settings.ai.provider.info.message", comment: "AI Provider info")
                                        alert.alertStyle = .informational
                                        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
                                        alert.runModal()
                                    }) {
                                        Image(systemName: "info.circle")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(NSLocalizedString("settings.ai.provider.info.title", comment: "Click for more information"))
                                }
                                
                                Picker("", selection: $localAIProvider) {
                                    Text("Gemini").tag(AIProvider.gemini)
                                    Text("OpenRouter").tag(AIProvider.openRouter)
                                    Text("Local").tag(AIProvider.local)
                                    Text("Ollama").tag(AIProvider.ollama)
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: localAIProvider) { _, _ in
                                    hasUnsavedChanges = true
                                    // Reset API key status when switching providers
                                    if localAIProvider == .openRouter {
                                        openRouterKeyStatus = .unknown
                                    }
                                    // Check Ollama status when switching to it
                                    if localAIProvider == .ollama {
                                        Task {
                                            await OllamaService.shared.checkOllamaStatus()
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // Conditional API Key Fields
                            if localAIProvider == .gemini {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(NSLocalizedString("settings.api.gemini.key", comment: "Gemini API key"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    SecureField(NSLocalizedString("settings.api.gemini.key.placeholder", comment: "API key placeholder"), text: $localGeminiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: localGeminiKey) { _, _ in
                                            hasUnsavedChanges = true
                                        }

                                    Text(NSLocalizedString("settings.api.gemini.key.description", comment: "API key description"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    // Help link
                                    Button(action: {
                                        if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "link")
                                                .font(.caption2)
                                            Text("Get your free API Key from Google AI Studio")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "lock.shield.fill")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(NSLocalizedString("settings.api.key.secure.storage", comment: "Secure storage message"))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else if localAIProvider == .openRouter {
                                // OpenRouter Configuration
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(NSLocalizedString("settings.openrouter.api.key", comment: "OpenRouter API Key"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    HStack(spacing: 8) {
                                        SecureField(NSLocalizedString("settings.openrouter.api.key.placeholder", comment: "Enter OpenRouter API key"), text: $localOpenRouterKey)
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: localOpenRouterKey) { _, _ in
                                                hasUnsavedChanges = true
                                                openRouterKeyStatus = .unknown
                                                openRouterKeyErrorMessage = ""
                                            }
                                        
                                        // Visual status indicator
                                        Group {
                                            switch openRouterKeyStatus {
                                            case .unknown:
                                                Image(systemName: "questionmark.circle")
                                                    .foregroundColor(.secondary)
                                            case .testing:
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                            case .valid:
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                            case .invalid:
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .frame(width: 20, height: 20)
                                        
                                        // Test API Key button
                                        Button(action: {
                                            testOpenRouterAPIKey()
                                        }) {
                                            HStack(spacing: 6) {
                                                if isTestingOpenRouterKey {
                                                    ProgressView()
                                                        .scaleEffect(0.6)
                                                        .frame(width: 12, height: 12)
                                                }
                                                Text(isTestingOpenRouterKey ? NSLocalizedString("settings.api.testing", comment: "Testing...") : NSLocalizedString("settings.api.test", comment: "Test"))
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isTestingOpenRouterKey || localOpenRouterKey.isEmpty)
                                    }
                                    
                                    // Error message display
                                    if case .invalid(let message) = openRouterKeyStatus {
                                        Text(message)
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                            .padding(.leading, 4)
                                    }

                                    if case .valid = openRouterKeyStatus {
                                        Text(NSLocalizedString("settings.openrouter.key.valid", comment: "API key is valid"))
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    } else {
                                        Text(NSLocalizedString("settings.openrouter.key.get", comment: "Get your API key"))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    // Help link
                                    Button(action: {
                                        if let url = URL(string: "https://openrouter.ai/keys") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "link")
                                                .font(.caption2)
                                            Text(NSLocalizedString("settings.openrouter.key.link", comment: "Get your API Key from OpenRouter"))
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "lock.shield.fill")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(NSLocalizedString("settings.api.key.secure.storage", comment: "Secure storage message"))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Divider()
                                    
                                    Text(NSLocalizedString("settings.openrouter.model", comment: "Model"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // Model selection with Picker
                                    ModelSelectionView(
                                        selectedModelID: $localOpenRouterModel,
                                        hasUnsavedChanges: $hasUnsavedChanges
                                    )
                                }
                            } else if localAIProvider == .local {
                                // Local Model Configuration
                                LocalModelManagementView(
                                    selectedModelId: $localSelectedModel,
                                    hasUnsavedChanges: $hasUnsavedChanges
                                )
                            } else if localAIProvider == .ollama {
                                // Ollama Configuration
                                OllamaConfigurationView(hasUnsavedChanges: $hasUnsavedChanges)
                            }
                        }
                        .padding(8)
                    }

                    // Export/Import Section
                    GroupBox(label: Label(NSLocalizedString("settings.backup.title", comment: "Backup & Restore"), systemImage: "arrow.up.arrow.down")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("settings.backup.description", comment: "Export description"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    guard !isExporting else { return }  // Prevent double-click
                                    isExporting = true
                                    Task {
                                        exportSettings()
                                        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s debounce
                                        isExporting = false
                                    }
                                }) {
                                    HStack {
                                        if isExporting {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .frame(width: 16, height: 16)
                                        } else {
                                            Image(systemName: "square.and.arrow.up")
                                        }
                                        Text(isExporting ? NSLocalizedString("settings.export.progress", comment: "Exporting...") : NSLocalizedString("settings.export", comment: "Export Settings..."))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isExporting)

                                Button(action: {
                                    guard !isImporting else { return }  // Prevent double-click
                                    isImporting = true
                                    Task {
                                        importSettings()
                                        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s debounce
                                        isImporting = false
                                    }
                                }) {
                                    HStack {
                                        if isImporting {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .frame(width: 16, height: 16)
                                        } else {
                                            Image(systemName: "square.and.arrow.down")
                                        }
                                        Text(isImporting ? NSLocalizedString("settings.import.progress", comment: "Importing...") : NSLocalizedString("settings.import", comment: "Import Settings..."))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isImporting)
                            }
                            
                            if showExportSuccess {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(NSLocalizedString("settings.export.success", comment: "Settings exported successfully!"))
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if showImportSuccess {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(NSLocalizedString("settings.import.success", comment: "Settings imported successfully!"))
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if showImportError {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(importErrorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(8)
                    }
        }
    }

    private var settingsActionBar: some View {
        VStack(spacing: 0) {
            // Bottom Action Bar
            HStack(spacing: 12) {
                Button(action: onReset) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(NSLocalizedString("settings.reset", comment: "Reset"))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)

                Spacer()

                if hasUnsavedChanges {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text(NSLocalizedString("settings.unsaved.changes", comment: "Unsaved changes"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if showSavedMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("settings.saved", comment: "Saved"))
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .transition(.opacity)
                }

                Button(action: onSave) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(NSLocalizedString("settings.save.changes", comment: "Save changes"))
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
        .alert(NSLocalizedString("settings.export.success.title", comment: "Export Successful"), isPresented: $showExportSuccess) {
            Button(NSLocalizedString("alert.button.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("settings.export.success.message", comment: "Export success message"))
        }
        .alert(NSLocalizedString("settings.import.success.title", comment: "Import Successful"), isPresented: $showImportSuccess) {
            Button(NSLocalizedString("alert.button.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("settings.import.success.message", comment: "Import success message"))
        }
        .alert(NSLocalizedString("settings.import.failed.title", comment: "Import Failed"), isPresented: $showImportError) {
            Button(NSLocalizedString("alert.button.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
        .alert(NSLocalizedString("update.alert.title", comment: "Update Available"), isPresented: $showUpdateAlert) {
            Button(NSLocalizedString("update.alert.button", comment: "Download")) {
                if let info = updateInfo, let downloadURL = info.downloadURL, let url = URL(string: downloadURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(NSLocalizedString("update.alert.cancel", comment: "Later"), role: .cancel) { }
        } message: {
            if let info = updateInfo {
                Text(String(format: NSLocalizedString("update.alert.message", comment: "Update message"), info.version, info.releaseNotes ?? "Bug fixes and improvements."))
            }
        }
        .alert(NSLocalizedString("update.alert.no.update.title", comment: "You're Up to Date"), isPresented: $showNoUpdateAlert) {
            Button(NSLocalizedString("alert.button.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("update.alert.no.update.message", comment: "No update message"))
        }
        .alert(NSLocalizedString("settings.language.change.title", comment: "Language Change"), isPresented: $showLanguageRestartAlert) {
            Button(NSLocalizedString("alert.button.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("settings.language.change.message", comment: "Restart message"))
        }
    }
    
    // MARK: - Update Check

    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var showUpdateAlert = false
    @State private var updateInfo: UpdateInfo?
    @State private var showNoUpdateAlert = false

    private func checkForUpdates() {
        Task {
            do {
                let info = try await updateManager.checkForUpdates()

                if let info = info {
                    updateInfo = info
                    showUpdateAlert = true
                } else {
                    showNoUpdateAlert = true
                }
            } catch {
                showToast("Couldn't check for updates. Please check your connection.", style: .error)
                Logger.error("Update check failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Permission Management
    
    private func refreshPermissionStatus() {
        accessibilityGranted = permissionManager.refreshAccessibilityStatus()
        screenRecordingGranted = permissionManager.isScreenRecordingTrusted()
        microphoneGranted = permissionManager.isMicrophoneGranted()
        speechRecognitionGranted = permissionManager.isSpeechRecognitionGranted()
    }
    
    // MARK: - OpenRouter API Key Testing
    
    private func testOpenRouterAPIKey() {
        guard !localOpenRouterKey.isEmpty else {
            openRouterKeyStatus = .invalid("API key cannot be empty")
            return
        }
        
        // Basic format validation
        if localOpenRouterKey.count < 20 {
            openRouterKeyStatus = .invalid("API key seems too short. OpenRouter API keys are typically longer.")
            return
        }
        
        isTestingOpenRouterKey = true
        openRouterKeyStatus = .testing
        
        // Test the API key by making a direct request
        Task { @MainActor in
            // Save original values before testing
            let originalKey = settings.openRouterKey
            let originalModel = settings.openRouterModel
            
            // Always restore original settings when done
            defer {
                settings.openRouterKey = originalKey
                settings.openRouterModel = originalModel
                isTestingOpenRouterKey = false
            }
            
            do {
                // Temporarily store the key in SettingsManager for testing
                settings.openRouterKey = localOpenRouterKey
                if !localOpenRouterModel.isEmpty {
                    settings.openRouterModel = localOpenRouterModel
                }
                
                // Test with a simple request using the service
                let testService = OpenRouterService.shared
                let testPrompt = "Say hello"
                let response = try await testService.generateResponse(prompt: testPrompt)
                
                // Check if we got a valid response
                if !response.isEmpty {
                    openRouterKeyStatus = .valid
                    openRouterKeyErrorMessage = ""
                    showToast("API key is valid and working!", style: .success)
                } else {
                    openRouterKeyStatus = .invalid("API key test returned empty response")
                    showToast("API key test returned empty response", style: .error)
                }
            } catch {
                let errorMessage: String
                if let aiError = error as? AIServiceError {
                    switch aiError {
                    case .apiKeyNotFound:
                        errorMessage = "API key not found. Please enter a valid OpenRouter API key."
                    case .httpError(let code, let message):
                        if code == 401 {
                            errorMessage = "Invalid API key. Please check your OpenRouter API key."
                        } else if code == 429 {
                            errorMessage = "Rate limit exceeded. Please try again later."
                        } else {
                            errorMessage = "HTTP error \(code): \(message ?? "Unknown error")"
                        }
                    case .networkError(let err):
                        errorMessage = "Network error: \(err.localizedDescription). Please check your internet connection."
                    case .rateLimitExceeded:
                        errorMessage = "Rate limit exceeded. Please try again later."
                    default:
                        errorMessage = "Error testing API key: \(aiError.localizedDescription)"
                    }
                } else {
                    errorMessage = "Error testing API key: \(error.localizedDescription)"
                }
                
                openRouterKeyStatus = .invalid(errorMessage)
                openRouterKeyErrorMessage = errorMessage
                showToast(errorMessage, style: .error)
            }
        }
    }
    
    // MARK: - Export/Import Actions
    
    private func exportSettings() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "JoyaFix_Settings_\(Date().timeIntervalSince1970).json"
        savePanel.title = "Export JoyaFix Settings"
        savePanel.message = "Choose where to save your settings and snippets"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if SettingsExporter.export(to: url) {
                    showExportSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        showExportSuccess = false
                    }
                } else {
                    importErrorMessage = "Failed to export settings. Please try again."
                    showImportError = true
                }
            }
        }
    }
    
    private func importSettings() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.title = "Import JoyaFix Settings"
        openPanel.message = "Choose a settings file to import"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                // Validate file first
                guard SettingsExporter.isValidExportFile(url) else {
                    importErrorMessage = "Invalid export file. Please select a valid JoyaFix settings file."
                    showImportError = true
                    return
                }
                
                // Show confirmation alert
                let alert = NSAlert()
                alert.messageText = "Import Settings"
                alert.informativeText = "This will replace your current settings and snippets. Are you sure you want to continue?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Import")
                alert.addButton(withTitle: "Cancel")
                
                let alertResponse = alert.runModal()
                if alertResponse == .alertFirstButtonReturn {
                    if SettingsExporter.importSettings(from: url) {
                        showImportSuccess = true
                        hasUnsavedChanges = false // Import saves immediately
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            showImportSuccess = false
                        }
                    } else {
                        importErrorMessage = "Failed to import settings. The file may be corrupted or incompatible."
                        showImportError = true
                    }
                }
            }
        }
    }
}

// MARK: - Snippets Tab

struct SnippetsTab: View {
    @ObservedObject var snippetManager = SnippetManager.shared
    @State private var isAddingSnippet = false
    @State private var editingSnippet: Snippet?
    @State private var newTrigger = ""
    @State private var newContent = ""
    @State private var showSnippetGuide = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(NSLocalizedString("settings.snippets.title", comment: "Snippets title"))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { isAddingSnippet = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(NSLocalizedString("settings.snippets.add", comment: "Add snippet"))
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // How to Use Guide (Collapsible)
            DisclosureGroup(isExpanded: $showSnippetGuide) {
                VStack(alignment: .leading, spacing: 12) {
                    // Basic Usage
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Basic Usage")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Type your trigger (e.g., '!mail') followed by a space or punctuation to expand.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Dynamic Variables
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dynamic Variables")
                            .font(.system(size: 12, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\u{2022} {date} - Current date (dd/MM/yyyy)")
                            Text("\u{2022} {time} - Current time (HH:mm)")
                            Text("\u{2022} {datetime} - Full date and time")
                            Text("\u{2022} {clipboard} - Paste clipboard content")
                            Text("\u{2022} {year}, {month}, {day} - Date components")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }

                    Divider()

                    // Cursor Placement
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cursor Placement")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Use | (pipe) to set cursor position after expansion.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Example: 'Hello |,' places cursor before the comma")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }

                    Divider()

                    // Custom Variables
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Variables")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Use {variableName} to prompt for custom input.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Example: 'Dear {recipientName},' prompts for the name")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.accentColor)
                    Text("How to Use Snippets")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)

            // Snippets List
            if snippetManager.snippets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("settings.snippets.empty", comment: "No snippets"))
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(snippetManager.snippets) { snippet in
                        SnippetRow(
                            snippet: snippet,
                            onEdit: { editingSnippet = snippet },
                            onDelete: { snippetManager.removeSnippet(snippet) }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingSnippet) {
            SnippetEditView(
                snippet: nil,
                onSave: { trigger, content in
                    let newSnippet = Snippet(trigger: trigger, content: content)
                    snippetManager.addSnippet(newSnippet)
                    isAddingSnippet = false
                },
                onCancel: { isAddingSnippet = false }
            )
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditView(
                snippet: snippet,
                onSave: { trigger, content in
                    var updated = snippet
                    updated.trigger = trigger
                    updated.content = content
                    snippetManager.updateSnippet(updated)
                    editingSnippet = nil
                },
                onCancel: { editingSnippet = nil }
            )
        }
    }
}

// MARK: - Snippet Row

struct SnippetRow: View {
    let snippet: Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.trigger)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(snippet.content)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .help(snippet.content) // Display full content on hover
    }
}

// MARK: - Snippet Edit View

struct SnippetEditView: View {
    let snippet: Snippet?
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var trigger: String
    @State private var content: String
    @State private var validationError: String? = nil
    
    init(snippet: Snippet?, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.snippet = snippet
        self.onSave = onSave
        self.onCancel = onCancel
        _trigger = State(initialValue: snippet?.trigger ?? "")
        _content = State(initialValue: snippet?.content ?? "")
    }
    
    private func validateInput() -> Bool {
        validationError = nil
        
        // Validate trigger is not empty
        guard !trigger.isEmpty else {
            validationError = "Snippet trigger cannot be empty"
            return false
        }
        
        // Validate trigger length
        let minLength = JoyaFixConstants.minSnippetTriggerLength
        let maxLength = JoyaFixConstants.maxSnippetTriggerLength
        
        guard trigger.count >= minLength else {
            validationError = "Snippet trigger must be at least \(minLength) characters long"
            return false
        }
        
        guard trigger.count <= maxLength else {
            validationError = "Snippet trigger cannot exceed \(maxLength) characters"
            return false
        }
        
        // Validate content is not empty
        guard !content.isEmpty else {
            validationError = "Snippet content cannot be empty"
            return false
        }
        
        // Check for special characters that might cause issues
        let invalidChars = CharacterSet(charactersIn: "\n\r\t")
        if trigger.rangeOfCharacter(from: invalidChars) != nil {
            validationError = "Snippet trigger cannot contain newlines or tabs"
            return false
        }
        
        return true
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(snippet == nil ? NSLocalizedString("settings.snippets.add", comment: "Add snippet") : NSLocalizedString("settings.snippets.edit", comment: "Edit snippet"))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("settings.snippets.trigger", comment: "Trigger"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(NSLocalizedString("settings.snippets.trigger.placeholder", comment: "Trigger placeholder"), text: $trigger)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: trigger) { _, _ in
                        validationError = nil
                    }
                
                // Trigger length indicator
                HStack {
                    Spacer()
                    Text("\(trigger.count)/\(JoyaFixConstants.maxSnippetTriggerLength)")
                        .font(.caption2)
                        .foregroundColor(trigger.count > JoyaFixConstants.maxSnippetTriggerLength ? .red : .secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("settings.snippets.content", comment: "Content"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $content)
                    .frame(height: 220)  // Increased from 150px (47% more space)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .onChange(of: content) { _, _ in
                        validationError = nil
                    }
            }
            
            // Validation error display
            if let error = validationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption2)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
            }
            
            HStack {
                Button(NSLocalizedString("settings.snippets.cancel", comment: "Cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button(NSLocalizedString("settings.snippets.save", comment: "Save"), action: {
                    if validateInput() {
                        onSave(trigger, content)
                    }
                })
                .buttonStyle(.borderedProminent)
                .disabled(trigger.isEmpty || content.isEmpty || validationError != nil)
            }
        }
        .padding(24)  // Increased from default 20 for premium feel
        .frame(width: 500, height: 480)  // 25% larger for better readability
    }
}

// MARK: - Permission Row Component

struct SettingsPermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let icon: String
    let onOpenSettings: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // Status indicator
                    HStack(spacing: 6) {
                        Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isGranted ? .green : .orange)
                        Text(isGranted ? NSLocalizedString("settings.permissions.granted", comment: "Granted") : NSLocalizedString("settings.permissions.not.granted", comment: "Not Granted"))
                            .font(.caption)
                            .foregroundColor(isGranted ? .green : .orange)
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !isGranted {
                    Button(action: onOpenSettings) {
                        HStack {
                            Image(systemName: "gear")
                            Text(NSLocalizedString("settings.permissions.open.settings", comment: "Open Settings"))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Model Selection View

struct ModelSelectionView: View {
    @Binding var selectedModelID: String
    @Binding var hasUnsavedChanges: Bool
    @State private var isCustom: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let currentModel = JoyaFixConstants.OpenRouterModel.fromModelID(selectedModelID.isEmpty ? "deepseek/deepseek-chat" : selectedModelID)
            let isCustomModel = if case .custom = currentModel { true } else { false }
            
            Picker("", selection: Binding(
                get: { currentModel },
                set: { newModel in
                    if case .custom = newModel {
                        // Keep current custom value, just mark as custom
                        isCustom = true
                    } else {
                        selectedModelID = newModel.modelID
                        isCustom = false
                        hasUnsavedChanges = true
                    }
                }
            )) {
                ForEach(JoyaFixConstants.OpenRouterModel.recommendedModels, id: \.modelID) { model in
                    Text(model.displayName).tag(model)
                }
                Text("Custom Model").tag(JoyaFixConstants.OpenRouterModel.custom(selectedModelID))
            }
            .pickerStyle(.menu)
            .onAppear {
                isCustom = isCustomModel
            }
            
            // Show custom text field if custom is selected or current model is not in recommended list
            if isCustom || isCustomModel {
                TextField("e.g., anthropic/claude-3-haiku", text: $selectedModelID)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: selectedModelID) { _, _ in
                        hasUnsavedChanges = true
                    }
            }
            
            // Model info
            if isCustom || isCustomModel {
                Text("Enter a custom model ID in the format 'provider/model-name'")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    if currentModel.supportsVision {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text("Supports Vision")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    if currentModel.isFree {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Free")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Local Model Management View

struct LocalModelManagementView: View {
    @ObservedObject var downloadManager = ModelDownloadManager.shared
    @Binding var selectedModelId: String?
    @Binding var hasUnsavedChanges: Bool

    @State private var showModelPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            Text(NSLocalizedString("settings.local.model", comment: "Local Model"))
                .font(.caption)
                .foregroundColor(.secondary)

            // Downloaded Models
            if downloadManager.downloadedModels.isEmpty {
                // No models downloaded
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text(NSLocalizedString("settings.local.no.models", comment: "No local models"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { showModelPicker = true }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(NSLocalizedString("settings.local.download.model", comment: "Download Model"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            } else {
                // Model Selection
                VStack(alignment: .leading, spacing: 8) {
                    Picker(NSLocalizedString("settings.local.select.model", comment: "Select Model"), selection: Binding(
                        get: { selectedModelId ?? "" },
                        set: { newValue in
                            selectedModelId = newValue.isEmpty ? nil : newValue
                            hasUnsavedChanges = true
                        }
                    )) {
                        Text(NSLocalizedString("settings.local.select.placeholder", comment: "Select a model...")).tag("")
                        ForEach(downloadManager.downloadedModels) { model in
                            HStack {
                                Text(model.info.displayName)
                                
                                // Source indicator
                                switch model.source {
                                case .downloaded:
                                    Text(NSLocalizedString("settings.local.source.downloaded", comment: "(Downloaded)"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                case .ollama:
                                    Text(NSLocalizedString("settings.local.source.ollama", comment: "(Ollama)"))
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                case .external:
                                    Text(NSLocalizedString("settings.local.source.external", comment: "(External)"))
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                if model.info.supportsVision {
                                    Image(systemName: "eye.fill")
                                        .font(.caption2)
                                }
                                // V/X indicator for file existence
                                if model.exists {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                            .tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)

                    // Model info
                    if let selectedId = selectedModelId,
                       let model = downloadManager.downloadedModels.first(where: { $0.id == selectedId }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                // File status indicator
                                if model.exists {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                        Text(model.statusDisplay)
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.green)
                                    
                                    // Model readiness indicator (for local models)
                                    if model.source == .downloaded || model.source == .external {
                                        let llmService = LocalLLMService.shared
                                        if llmService.isReady {
                                            HStack(spacing: 4) {
                                                Image(systemName: "bolt.fill")
                                                    .font(.caption2)
                                                Text(NSLocalizedString("settings.local.status.ready", comment: "Ready"))
                                                    .font(.caption2)
                                            }
                                            .foregroundColor(.blue)
                                        } else {
                                            HStack(spacing: 4) {
                                                Image(systemName: "hourglass")
                                                    .font(.caption2)
                                                Text(NSLocalizedString("settings.local.status.not.loaded", comment: "Not loaded"))
                                                    .font(.caption2)
                                            }
                                            .foregroundColor(.orange)
                                        }
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                        Text(NSLocalizedString("settings.local.status.file.missing", comment: "File missing"))
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.red)
                                }

                                Text("\(NSLocalizedString("settings.local.info.size", comment: "Size:")) \(model.info.fileSizeFormatted)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text("\(NSLocalizedString("settings.local.info.ram", comment: "RAM:")) \(model.info.requiredRAMFormatted)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                if model.info.supportsVision {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eye.fill")
                                            .font(.caption2)
                                        Text(NSLocalizedString("settings.local.info.vision", comment: "Vision"))
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                            
                            // Source-specific info
                            if model.source == .ollama {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                    Text(NSLocalizedString("settings.local.info.managed.ollama", comment: "Managed by Ollama"))
                                        .font(.caption2)
                                }
                                .foregroundColor(.purple)
                            } else if model.source == .external && model.isExternal {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                    Text("\(NSLocalizedString("settings.local.info.external", comment: "External model found at:")) \(model.localPath)")
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .foregroundColor(.orange)
                            }
                        }
                    }
                }

                Divider()

                // Action Buttons
                HStack(spacing: 12) {
                    // Manage Models Button
                    Button(action: { showModelPicker = true }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text(NSLocalizedString("settings.local.manage.models", comment: "Manage Models..."))
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    // Scan for Models Button
                    Button(action: {
                        Task {
                            await downloadManager.refreshLocalModels()
                        }
                    }) {
                        HStack {
                            if downloadManager.isScanning {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text(downloadManager.isScanning ? NSLocalizedString("settings.local.scanning", comment: "Scanning...") : NSLocalizedString("settings.local.scan.models", comment: "Scan for Models"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(downloadManager.isScanning)
                }
            }

            // Download Progress
            if downloadManager.isDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(format: NSLocalizedString("settings.local.downloading", comment: "Downloading model..."), downloadManager.currentDownloadModel?.displayName ?? "model"))
                            .font(.caption)

                        Spacer()

                        Button(NSLocalizedString("settings.local.download.cancel", comment: "Cancel")) {
                            downloadManager.cancelDownload()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        .font(.caption)
                    }

                    ProgressView(value: downloadManager.downloadProgress)
                        .progressViewStyle(.linear)

                    Text("\(Int(downloadManager.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            // Info text
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(NSLocalizedString("settings.local.info.privacy", comment: "Local models privacy note"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showModelPicker) {
            LocalModelPickerSheet(downloadManager: downloadManager)
        }
    }
}

// MARK: - Local Model Picker Sheet

struct LocalModelPickerSheet: View {
    @ObservedObject var downloadManager: ModelDownloadManager
    @Environment(\.dismiss) var dismiss
    
    private var llmService: LocalLLMService {
        LocalLLMService.shared
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(NSLocalizedString("settings.local.models.title", comment: "Local Models"))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(NSLocalizedString("settings.local.done", comment: "Done")) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()
            
            // Hardware info banner
            HStack(spacing: 8) {
                Image(systemName: llmService.isOptimalHardware ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(llmService.isOptimalHardware ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(NSLocalizedString("settings.local.hardware", comment: "Hardware:")) \(llmService.hardwareArchitecture.displayName)")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if let warning = llmService.hardwareArchitecture.performanceWarning {
                        Text(warning)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        Text(NSLocalizedString("settings.local.hardware.optimal", comment: "Optimal for local AI"))
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(llmService.isOptimalHardware ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))

            // Available Models List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(LocalModelRegistry.availableModels) { model in
                        LocalModelCard(
                            model: model,
                            downloadManager: downloadManager,
                            isDownloaded: downloadManager.downloadedModels.contains { $0.id == model.id }
                        )
                    }
                }
                .padding()
            }

            // Footer with RAM info
            VStack(spacing: 4) {
                Divider()
                HStack {
                    Image(systemName: "memorychip")
                        .foregroundColor(.secondary)
                    Text("\(NSLocalizedString("settings.local.available.ram", comment: "Available RAM:")) \(ByteCountFormatter.string(fromByteCount: Int64(downloadManager.availableRAM()), countStyle: .memory))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .frame(width: 550, height: 550)
    }
}

// MARK: - Local Model Card

struct LocalModelCard: View {
    let model: LocalModelInfo
    @ObservedObject var downloadManager: ModelDownloadManager
    let isDownloaded: Bool
    
    private var llmService: LocalLLMService {
        LocalLLMService.shared
    }

    /// Check if the downloaded model file actually exists on disk
    private var fileExists: Bool {
        guard isDownloaded,
              let downloaded = downloadManager.downloadedModels.first(where: { $0.id == model.id }) else {
            return false
        }
        return downloaded.exists
    }
    
    /// Whether this model is recommended for current hardware
    private var isRecommended: Bool {
        llmService.isModelRecommended(model)
    }
    
    /// Performance estimate for this model
    private var performanceEstimate: String {
        llmService.getPerformanceEstimate(for: model)
    }
    
    /// Color for performance badge
    private var performanceColor: Color {
        let estimate = performanceEstimate
        if estimate.contains("Fast") || estimate.contains("מהיר") {
            return .green
        } else if estimate.contains("Good") || estimate.contains("טוב") {
            return .blue
        } else if estimate.contains("Moderate") || estimate.contains("בינוני") {
            return .orange
        } else if estimate.contains("Slow") || estimate.contains("איטי") {
            return .red
        }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: model.supportsVision ? "eye.circle.fill" : "cpu.fill")
                .font(.title2)
                .foregroundColor(isDownloaded ? (fileExists ? .green : .red) : .secondary)
                .frame(width: 40)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)

                    if model.supportsVision {
                        Text("Vision")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    // Performance estimate badge
                    Text(performanceEstimate)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(performanceColor.opacity(0.2))
                        .foregroundColor(performanceColor)
                        .cornerRadius(4)

                    // File existence indicator (V or X)
                    if isDownloaded {
                        if fileExists {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                                .help("Model file exists on disk")
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                                .help("Model file not found on disk - please re-download")
                        }
                    }
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // Show warning if file is missing
                if isDownloaded && !fileExists {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("File missing - please re-download")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                // Show warning for non-recommended models on Intel
                if !isRecommended && !llmService.isOptimalHardware {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("local.llm.not.recommended.intel", comment: "Not recommended for Intel"))
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 12) {
                    Label(model.fileSizeFormatted, systemImage: "doc.fill")
                    Label(model.requiredRAMFormatted + " RAM", systemImage: "memorychip")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Action Button
            if isDownloaded && fileExists {
                Button(role: .destructive) {
                    if let downloaded = downloadManager.downloadedModels.first(where: { $0.id == model.id }) {
                        try? downloadManager.deleteModel(downloaded)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            } else if isDownloaded && !fileExists {
                // File is missing - show re-download button
                Button {
                    // First remove the broken entry
                    if let downloaded = downloadManager.downloadedModels.first(where: { $0.id == model.id }) {
                        try? downloadManager.deleteModel(downloaded)
                    }
                    // Then start fresh download
                    Task {
                        try? await downloadManager.downloadModel(model)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-download")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(downloadManager.isDownloading)
            } else if downloadManager.isDownloading && downloadManager.currentDownloadModel?.id == model.id {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    Task {
                        try? await downloadManager.downloadModel(model)
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(downloadManager.isDownloading)
            }
        }
        .padding()
        .background(isDownloaded ? (fileExists ? Color.green.opacity(0.1) : Color.red.opacity(0.1)) : Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Ollama Configuration View

struct OllamaConfigurationView: View {
    @ObservedObject var ollamaService = OllamaService.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var downloadManager = ModelDownloadManager.shared
    @Binding var hasUnsavedChanges: Bool
    
    @State private var localEndpoint: String = ""
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    
    enum ConnectionStatus {
        case unknown
        case testing
        case connected
        case failed(String)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Text(NSLocalizedString("ollama.config.title", comment: "Ollama Configuration"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(ollamaService.isOllamaRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(ollamaService.isOllamaRunning ? NSLocalizedString("ollama.status.connected", comment: "Connected") : NSLocalizedString("ollama.status.not.running", comment: "Not Running"))
                        .font(.caption2)
                        .foregroundColor(ollamaService.isOllamaRunning ? .green : .red)
                }
            }
            
            // Endpoint configuration
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("ollama.endpoint.url", comment: "Endpoint URL"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("http://localhost:11434", text: $localEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            localEndpoint = settings.ollamaEndpoint
                        }
                        .onChange(of: localEndpoint) { _, newValue in
                            settings.ollamaEndpoint = newValue
                            hasUnsavedChanges = true
                        }
                    
                    Button(NSLocalizedString("ollama.test.button", comment: "Test")) {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingConnection)
                }
                
                // Connection status message
                switch connectionStatus {
                case .connected:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("ollama.connected", comment: "Connected to Ollama"))
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                case .failed(let message):
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                case .testing:
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(NSLocalizedString("ollama.testing", comment: "Testing connection..."))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                case .unknown:
                    EmptyView()
                }
            }
            
            Divider()
            
            // Model Selection
            if ollamaService.isOllamaRunning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("ollama.select.model", comment: "Select Model"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: refreshModels) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(NSLocalizedString("ollama.refresh", comment: "Refresh"))
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if ollamaService.availableModels.isEmpty {
                        VStack(spacing: 8) {
                            Text(NSLocalizedString("ollama.no.models", comment: "No models found"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                if let url = URL(string: "https://ollama.ai/library") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                    Text(NSLocalizedString("ollama.browse.library", comment: "Browse Ollama Library"))
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            
                            Text(NSLocalizedString("ollama.pull.hint", comment: "Pull a model"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Picker(NSLocalizedString("settings.openrouter.model", comment: "Model"), selection: Binding(
                            get: { settings.selectedOllamaModel ?? "" },
                            set: { newValue in
                                settings.selectedOllamaModel = newValue.isEmpty ? nil : newValue
                                hasUnsavedChanges = true
                            }
                        )) {
                            Text(NSLocalizedString("ollama.select.placeholder", comment: "Select a model...")).tag("")
                            ForEach(ollamaService.availableModels) { model in
                                HStack {
                                    Text(model.displayName)
                                    if model.supportsVision {
                                        Image(systemName: "eye.fill")
                                            .font(.caption2)
                                    }
                                    Text("(\(model.sizeFormatted))")
                                        .foregroundColor(.secondary)
                                }
                                .tag(model.name)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        // Model info
                        if let selectedModel = settings.selectedOllamaModel,
                           let model = ollamaService.availableModels.first(where: { $0.name == selectedModel }) {
                            HStack(spacing: 8) {
                                // Status indicator
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                    Text(NSLocalizedString("ollama.available", comment: "Available"))
                                        .font(.caption2)
                                }
                                .foregroundColor(.green)
                                
                                Text("\(NSLocalizedString("settings.local.info.size", comment: "Size:")) \(model.sizeFormatted)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if model.supportsVision {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eye.fill")
                                            .font(.caption2)
                                        Text(NSLocalizedString("settings.local.info.vision", comment: "Vision"))
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.blue)
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "text.alignleft")
                                            .font(.caption2)
                                        Text(NSLocalizedString("ollama.text.only", comment: "Text only"))
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.secondary)
                                }
                            }
                            
                            // Vision warning for text-only models
                            if !model.supportsVision {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text(NSLocalizedString("ollama.text.only.warning", comment: "Text only warning"))
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
            } else {
                // Ollama not running instructions
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("ollama.not.running.title", comment: "Ollama is not running"))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Text(NSLocalizedString("ollama.instructions.title", comment: "To use Ollama"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("ollama.instructions.step1", comment: "Step 1"))
                        Text(NSLocalizedString("ollama.instructions.step2", comment: "Step 2"))
                        Text(NSLocalizedString("ollama.instructions.step3", comment: "Step 3"))
                        Text(NSLocalizedString("ollama.instructions.step4", comment: "Step 4"))
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            if let url = URL(string: "https://ollama.ai") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text(NSLocalizedString("ollama.download.button", comment: "Download Ollama"))
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: refreshModels) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(NSLocalizedString("ollama.check.status", comment: "Check Status"))
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Scan for models button
            Button(action: {
                Task {
                    await downloadManager.refreshLocalModels()
                }
            }) {
                HStack {
                    if downloadManager.isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(downloadManager.isScanning ? NSLocalizedString("settings.local.scanning", comment: "Scanning...") : NSLocalizedString("settings.local.scan.models", comment: "Scan for Models"))
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(downloadManager.isScanning)
            
            // Info text
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(NSLocalizedString("settings.local.info.privacy", comment: "Local models privacy"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            Task {
                await ollamaService.checkOllamaStatus()
                if ollamaService.isOllamaRunning {
                    _ = try? await ollamaService.fetchAvailableModels()
                }
            }
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionStatus = .testing
        
        Task {
            await ollamaService.checkOllamaStatus()
            
            if ollamaService.isOllamaRunning {
                connectionStatus = .connected
                _ = try? await ollamaService.fetchAvailableModels()
            } else {
                connectionStatus = .failed("Cannot connect to Ollama at \(localEndpoint)")
            }
            
            isTestingConnection = false
        }
    }
    
    private func refreshModels() {
        Task {
            await ollamaService.checkOllamaStatus()
            if ollamaService.isOllamaRunning {
                _ = try? await ollamaService.fetchAvailableModels()
            }
        }
    }
}

// MARK: - Agent Configuration View

struct AgentConfigView: View {
    @Binding var agent: JoyaAgent
    @State private var selectedPreset: JoyaAgent?
    
    var body: some View {
        Form {
            Section(header: Text(NSLocalizedString("agent.config.profile", comment: "Agent Profile"))) {
                TextField(NSLocalizedString("agent.config.name", comment: "Agent Name"), text: $agent.name)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("agent.config.system.instructions", comment: "System Instructions"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $agent.systemInstructions)
                        .frame(height: 100)
                        .font(.system(.body, design: .monospaced))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                }
            }
            
            Section(header: Text(NSLocalizedString("agent.config.parameters", comment: "Parameters"))) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("agent.config.creativity", comment: "Creativity (Temperature)"))
                        Spacer()
                        Text("\(agent.temperature, specifier: "%.1f")")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $agent.temperature, in: 0.1...1.0)
                    
                    Text(NSLocalizedString("agent.config.creativity.description", comment: "Lower = focused, Higher = creative"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("agent.config.max.tokens", comment: "Max Response Length"))
                        Spacer()
                        Text("\(agent.maxTokens)")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(agent.maxTokens) },
                        set: { agent.maxTokens = Int($0) }
                    ), in: 256...4096, step: 256)
                    
                    Text(NSLocalizedString("agent.config.max.tokens.description", comment: "Maximum tokens in response"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text(NSLocalizedString("agent.config.presets", comment: "Preset Agents"))) {
                ForEach(JoyaAgent.predefinedAgents) { preset in
                    Button(action: {
                        agent = preset
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.headline)
                                Text(preset.systemInstructions)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if agent.id == preset.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Section {
                Button(NSLocalizedString("agent.config.reset", comment: "Reset to Default")) {
                    agent = .default
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}

// MARK: - AI Persona Tab

struct AIPersonaTab: View {
    @ObservedObject var settings: SettingsManager
    @Binding var hasUnsavedChanges: Bool
    @State private var localAgent: JoyaAgent
    
    init(settings: SettingsManager, hasUnsavedChanges: Binding<Bool>) {
        self.settings = settings
        self._hasUnsavedChanges = hasUnsavedChanges
        self._localAgent = State(initialValue: settings.activeAgent)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                GroupBox(label: Label(NSLocalizedString("settings.ai.persona.title", comment: "AI Persona"), systemImage: "person.crop.circle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("settings.ai.persona.description", comment: "AI Persona description"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(NSLocalizedString("settings.ai.persona.explanation", comment: "AI Persona explanation"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(8)
                }
                
                // Agent Configuration
                GroupBox(label: Label(NSLocalizedString("agent.config.profile", comment: "Agent Profile"), systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(NSLocalizedString("agent.config.name", comment: "Agent Name"), text: $localAgent.name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: localAgent.name) { _, _ in
                                hasUnsavedChanges = true
                            }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("agent.config.system.instructions", comment: "System Instructions"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $localAgent.systemInstructions)
                                .frame(height: 120)
                                .font(.system(.body, design: .monospaced))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                                .onChange(of: localAgent.systemInstructions) { _, _ in
                                    hasUnsavedChanges = true
                                }
                        }
                        
                        Divider()
                        
                        // Parameters
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(NSLocalizedString("agent.config.creativity", comment: "Creativity (Temperature)"))
                                    Spacer()
                                    Text("\(localAgent.temperature, specifier: "%.1f")")
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $localAgent.temperature, in: 0.1...1.0)
                                    .onChange(of: localAgent.temperature) { _, _ in
                                        hasUnsavedChanges = true
                                    }
                                
                                Text(NSLocalizedString("agent.config.creativity.description", comment: "Lower = focused, Higher = creative"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(NSLocalizedString("agent.config.max.tokens", comment: "Max Response Length"))
                                    Spacer()
                                    Text("\(localAgent.maxTokens)")
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { Double(localAgent.maxTokens) },
                                    set: { localAgent.maxTokens = Int($0); hasUnsavedChanges = true }
                                ), in: 256...4096, step: 256)
                                
                                Text(NSLocalizedString("agent.config.max.tokens.description", comment: "Maximum tokens in response"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }
                
                // Preset Agents
                GroupBox(label: Label(NSLocalizedString("agent.config.presets", comment: "Preset Agents"), systemImage: "list.bullet")) {
                    VStack(spacing: 8) {
                        ForEach(JoyaAgent.predefinedAgents) { preset in
                            Button(action: {
                                localAgent = preset
                                hasUnsavedChanges = true
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(preset.systemInstructions)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if localAgent.id == preset.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(8)
                                .background(localAgent.id == preset.id ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                
                // Reset Button
                HStack {
                    Spacer()
                    Button(NSLocalizedString("agent.config.reset", comment: "Reset to Default")) {
                        localAgent = JoyaAgent.default
                        hasUnsavedChanges = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .onChange(of: localAgent) { _, newValue in
            settings.activeAgent = newValue
        }
    }
}

