import SwiftUI
import Carbon

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
    
    var body: some View {
        VStack(spacing: 0) {
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
                    GroupBox(label: Label("OCR Screen Capture Hotkey", systemImage: "viewfinder")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Press the button and type your desired key combination:")
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
                Button(action: onReset) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
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
                        Text("Saved!")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .transition(.opacity)
                }

                Button(action: onSave) {
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
                Text("Text Snippets")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { isAddingSnippet = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Snippet")
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
                    Text("No Snippets")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Create shortcuts that expand into full text.\nFor example: !mail → your@email.com")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            Text(snippet == nil ? "Add Snippet" : "Edit Snippet")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger (e.g., !mail)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Trigger", text: $trigger)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Content (text to expand)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $content)
                    .frame(height: 150)
                    .border(Color.gray.opacity(0.3), width: 1)
            }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save", action: {
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

