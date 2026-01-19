import SwiftUI
import AVFoundation

/// UI view for voice input recording with visual feedback
struct VoiceInputView: View {
    @ObservedObject private var voiceManager = VoiceInputManager.shared
    @State private var showPermissionAlert = false
    @State private var editableText: String = ""
    @State private var isEditing = false
    @State private var showConfirmation = false
    @State private var pendingText: String = ""

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Voice Input")
                .font(.system(size: 18, weight: .semibold))
            
            // Recording Status
            if voiceManager.isRecording {
                VStack(spacing: 12) {
                    // Animated recording indicator
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .scaleEffect(voiceManager.isRecording ? 1.2 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true),
                                value: voiceManager.isRecording
                            )
                        
                        Circle()
                            .fill(Color.red)
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    
                    // Duration
                    Text(formatDuration(voiceManager.recordingDuration))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    // Live transcribed text preview (editable)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Live Transcription:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            if !voiceManager.transcribedText.isEmpty {
                                Button(action: {
                                    isEditing.toggle()
                                    if isEditing {
                                        editableText = voiceManager.transcribedText
                                    }
                                }) {
                                    Image(systemName: isEditing ? "checkmark" : "pencil")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help(isEditing ? "Save changes" : "Edit text")
                            }
                        }
                        
                        if isEditing {
                            TextEditor(text: $editableText)
                                .font(.system(size: 13))
                                .frame(height: 150)
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.accentColor, lineWidth: 1)
                                )
                        } else {
                            ScrollView {
                                Text(voiceManager.transcribedText.isEmpty ? "Listening..." : voiceManager.transcribedText)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundColor(voiceManager.transcribedText.isEmpty ? .secondary : .primary)
                                    .padding(12)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                            }
                            .frame(height: 150)
                        }
                    }
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        // Stop button
                        Button(action: {
                            voiceManager.stopRecording()
                        }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 80)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        // Review & Paste button - opens confirmation dialog
                        Button(action: {
                            // Set pending text and show confirmation
                            pendingText = isEditing && !editableText.isEmpty ? editableText : voiceManager.transcribedText
                            showConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                Text("Review & Paste")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 130)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(voiceManager.transcribedText.isEmpty && editableText.isEmpty)
                    }

                    // Close button
                    Button(action: {
                        closeVoiceInputWindow()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Close")
                        }
                        .font(.system(size: 12))
                        .frame(width: 80)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            } else {
                // Start recording button
                Button(action: {
                    Task { @MainActor in
                        // Check permissions first and show alert if needed
                        let hasPermissions = await voiceManager.ensurePermissions()
                        if hasPermissions {
                            await voiceManager.startRecording()
                        } else {
                            // Show error in UI
                            showPermissionAlert = true
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Start Recording")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 200)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text("• Press hotkey or click to start recording")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("• Speak clearly in Hebrew or English")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("• Click 'Stop & Paste' when finished")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
            
            // Error message
            if let error = voiceManager.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(24)
        .frame(width: 450, height: 550)
        .onChange(of: voiceManager.transcribedText) { oldValue, newValue in
            // Update editable text if not currently editing
            if !isEditing {
                editableText = newValue
            }
        }
        .onAppear {
            editableText = voiceManager.transcribedText
        }
        .alert("Permissions Required", isPresented: $showPermissionAlert) {
            Button("Open Microphone Settings") {
                PermissionManager.shared.openMicrophoneSettings()
            }
            Button("Open Speech Recognition Settings") {
                PermissionManager.shared.openSpeechRecognitionSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(voiceManager.errorMessage ?? "Voice input requires microphone and speech recognition permissions. Please grant them in System Settings.")
        }
        .sheet(isPresented: $showConfirmation) {
            VoiceInputConfirmationView(
                text: $pendingText,
                onConfirm: {
                    Task {
                        await ClipboardHelper.pasteText(pendingText)
                        showToast("Text pasted successfully")
                        showConfirmation = false
                        // Close window after paste
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            closeVoiceInputWindow()
                        }
                    }
                },
                onCancel: {
                    showConfirmation = false
                }
            )
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func showToast(_ message: String) {
        NotificationCenter.default.post(
            name: .showToast,
            object: ToastMessage(text: message, style: .success, duration: 2.0)
        )
    }

    private func closeVoiceInputWindow() {
        voiceManager.stopRecording()
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Voice Input" }) {
            window.close()
        }
    }
}

// MARK: - Voice Input Confirmation View

/// Confirmation dialog for reviewing and editing text before pasting
struct VoiceInputConfirmationView: View {
    @Binding var text: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                Text("Review Before Pasting")
                    .font(.headline)
            }

            // Editable text area
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit your text if needed:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .frame(height: 200)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            // Character count
            HStack {
                Spacer()
                Text("\(text.count) characters")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)

                Spacer()

                Button("Confirm & Paste") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420, height: 360)
    }
}

// MARK: - Voice Input Window Controller

class VoiceInputWindowController: NSWindowController {
    static var shared: VoiceInputWindowController?
    
    static func show() {
        // Close existing window if open
        if let existing = shared {
            existing.close()
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 550),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Voice Input"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: VoiceInputView())
        
        let controller = VoiceInputWindowController(window: window)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    override func close() {
        window?.close()
        VoiceInputWindowController.shared = nil
    }
}
