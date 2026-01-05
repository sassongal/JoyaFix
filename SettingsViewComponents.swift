import SwiftUI
import Carbon
import UniformTypeIdentifiers

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @ObservedObject var settings: SettingsManager
    @Binding var localConvertKeyCode: UInt32
    @Binding var localConvertModifiers: UInt32
    @Binding var localOCRKeyCode: UInt32
    @Binding var localOCRModifiers: UInt32
    @Binding var localMaxHistoryCount: Int
    @Binding var localPlaySound: Bool
    @Binding var localAutoPaste: Bool
    @Binding var localGeminiKey: String
    @Binding var localUseCloudOCR: Bool
    @Binding var isRecordingConvertHotkey: Bool
    @Binding var isRecordingOCRHotkey: Bool
    @Binding var hasUnsavedChanges: Bool
    @Binding var showSavedMessage: Bool
    let onSave: () -> Void
    let onReset: () -> Void
    let displayString: (UInt32, UInt32) -> String
    
    @State private var showExportSuccess = false
    @State private var showImportSuccess = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
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

                    // OCR Hotkey Section
                    GroupBox(label: Label(NSLocalizedString("settings.ocr.hotkey", comment: "OCR hotkey"), systemImage: "viewfinder")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("settings.ocr.hotkey.description", comment: "OCR hotkey description"))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HotkeyRecorderButton(
                                isRecording: $isRecordingOCRHotkey,
                                currentHotkey: displayString(localOCRKeyCode, localOCRModifiers)
                            ) { keyCode, modifiers in
                                localOCRKeyCode = keyCode
                                localOCRModifiers = modifiers
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

                    // OCR Configuration Section
                    GroupBox(label: Label(NSLocalizedString("settings.ocr.configuration", comment: "OCR configuration"), systemImage: "cloud.fill")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(NSLocalizedString("settings.ocr.use.cloud", comment: "Use cloud OCR"), isOn: $localUseCloudOCR)
                                .onChange(of: localUseCloudOCR) { _, _ in
                                    hasUnsavedChanges = true
                                }

                            if localUseCloudOCR {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(NSLocalizedString("settings.ocr.gemini.key", comment: "Gemini API key"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    SecureField(NSLocalizedString("settings.ocr.gemini.key.placeholder", comment: "API key placeholder"), text: $localGeminiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: localGeminiKey) { _, _ in
                                            hasUnsavedChanges = true
                                        }

                                    Text(NSLocalizedString("settings.ocr.gemini.key.description", comment: "API key description"))
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

                    // Export/Import Section
                    GroupBox(label: Label("Backup & Restore", systemImage: "arrow.up.arrow.down")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Export your settings and snippets to a file, or import from a previous backup.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    exportSettings()
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Export Settings...")
                                    }
                                }
                                .buttonStyle(.bordered)
                                
                                Button(action: {
                                    importSettings()
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("Import Settings...")
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            if showExportSuccess {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Settings exported successfully!")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if showImportSuccess {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Settings imported successfully!")
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

                    Spacer(minLength: 20)
                }
                .padding()
            }

            Divider()

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
                        Text("Unsaved changes")
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
        .alert("Export Successful", isPresented: $showExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your settings and snippets have been exported successfully.")
        }
        .alert("Import Successful", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your settings and snippets have been imported successfully. Hotkeys have been rebound.")
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
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
    }
}

// MARK: - Snippet Edit View

struct SnippetEditView: View {
    let snippet: Snippet?
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var trigger: String
    @State private var content: String
    
    init(snippet: Snippet?, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.snippet = snippet
        self.onSave = onSave
        self.onCancel = onCancel
        _trigger = State(initialValue: snippet?.trigger ?? "")
        _content = State(initialValue: snippet?.content ?? "")
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
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("settings.snippets.content", comment: "Content"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $content)
                    .frame(height: 150)
                    .border(Color.gray.opacity(0.3), width: 1)
            }
            
            HStack {
                Button(NSLocalizedString("settings.snippets.cancel", comment: "Cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button(NSLocalizedString("settings.snippets.save", comment: "Save"), action: {
                    onSave(trigger, content)
                })
                .buttonStyle(.borderedProminent)
                .disabled(trigger.isEmpty || content.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}

