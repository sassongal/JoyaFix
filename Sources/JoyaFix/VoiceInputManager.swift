import Foundation
import Speech
import AVFoundation
import AppKit
import AVKit

/// Manages voice input and transcription using Apple's Speech framework
@MainActor
class VoiceInputManager: NSObject, ObservableObject {
    static let shared = VoiceInputManager()
    
    @Published var isRecording = false
    @Published var transcribedText: String = ""
    @Published var errorMessage: String?
    @Published var recordingDuration: TimeInterval = 0
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    
    private var recordingTimer: Timer?
    private var startTime: Date?
    
    // Supported languages
    private let supportedLocales: [Locale] = [
        Locale(identifier: "he-IL"), // Hebrew
        Locale(identifier: "en-US")  // English
    ]
    
    private var currentLocale: Locale {
        // Always default to Hebrew as primary language
        return supportedLocales[0] // Hebrew (he-IL)
    }
    
    override init() {
        super.init()
        setupSpeechRecognizer()
    }
    
    // MARK: - Setup
    
    private func setupSpeechRecognizer() {
        // Always use Hebrew as primary language for voice input
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "he-IL"))
        speechRecognizer?.delegate = self
        
        // Check availability
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available"
            return
        }
    }
    
    // MARK: - Permission Management
    
    /// Checks if speech recognition permission is granted
    func checkSpeechPermission() -> Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    /// Requests speech recognition permission
    func requestSpeechPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    /// Checks if microphone permission is granted (macOS)
    func checkMicrophonePermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    /// Requests microphone permission (macOS)
    func requestMicrophonePermission() async -> Bool {
        let status = await AVCaptureDevice.requestAccess(for: .audio)
        return status
    }
    
    /// Checks and requests all required permissions with UI feedback
    func ensurePermissions() async -> Bool {
        // Check microphone permission
        if !checkMicrophonePermission() {
            // Show alert first
            await showPermissionAlert(
                title: "Microphone Permission Required",
                message: "JoyaFix needs microphone access to record your voice for transcription.",
                settingsAction: {
                    PermissionManager.shared.openMicrophoneSettings()
                }
            )
            
            let granted = await requestMicrophonePermission()
            if !granted {
                errorMessage = "Microphone permission is required. Please grant it in System Settings → Privacy & Security → Microphone"
                return false
            }
        }
        
        // Check speech recognition permission
        if !checkSpeechPermission() {
            // Show alert first
            await showPermissionAlert(
                title: "Speech Recognition Permission Required",
                message: "JoyaFix needs speech recognition access to transcribe your voice to text.",
                settingsAction: {
                    PermissionManager.shared.openSpeechRecognitionSettings()
                }
            )
            
            let granted = await requestSpeechPermission()
            if !granted {
                errorMessage = "Speech recognition permission is required. Please grant it in System Settings → Privacy & Security → Speech Recognition"
                return false
            }
        }
        
        return true
    }
    
    /// Shows permission alert on main thread
    private func showPermissionAlert(title: String, message: String, settingsAction: @escaping () -> Void) async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                settingsAction()
            }
        }
    }
    
    // MARK: - Recording Control
    
    /// Starts voice recording and transcription
    func startRecording() async {
        // Ensure permissions
        guard await ensurePermissions() else {
            return
        }
        
        // Stop any existing recording
        stopRecording()
        
        // Reset state
        transcribedText = ""
        errorMessage = nil
        isRecording = true
        startTime = Date()
        recordingDuration = 0

        // Invalidate existing timer to prevent memory leaks from multiple rapid calls
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            errorMessage = "Failed to initialize audio engine"
            isRecording = false
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Failed to create recognition request"
            isRecording = false
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true

        // Configure for optimal recognition quality
        recognitionRequest.taskHint = .dictation

        // Enable automatic punctuation on macOS 13+
        if #available(macOS 13.0, *) {
            recognitionRequest.addsPunctuation = true
        }

        // Force Hebrew locale for recognition
        // Note: The locale is set via the speechRecognizer, but we ensure it's Hebrew
        if speechRecognizer?.locale.identifier != "he-IL" {
            // Recreate recognizer with Hebrew locale
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "he-IL"))
            speechRecognizer?.delegate = self
        }
        
        // On macOS, we don't need to configure AVAudioSession
        // AVAudioEngine handles audio routing automatically
        
        // Setup audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            isRecording = false
            return
        }
        
        // Start recognition task
        guard let recognizer = speechRecognizer else {
            errorMessage = "Speech recognizer not available"
            isRecording = false
            return
        }
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            // CRITICAL: Speech recognition callback runs on arbitrary thread
            // Must dispatch UI updates to MainActor to avoid crashes
            Task { @MainActor in
                if let error = error {
                    // Check if it's a cancellation (user stopped)
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 { // Cancelled
                        self.errorMessage = "Recognition error: \(error.localizedDescription)"
                    }
                    self.isRecording = false
                    return
                }

                if let result = result {
                    self.transcribedText = result.bestTranscription.formattedString

                    // If final result, stop recording
                    if result.isFinal {
                        self.stopRecording()
                    }
                }
            }
        }
    }
    
    /// Stops voice recording (without pasting)
    func stopRecording() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        // Cancel recognition
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    // MARK: - Transcription and Paste
    
    /// Transcribes the recorded audio and pastes it
    func transcribeAndPaste() async {
        // Stop recording first
        stopRecording()
        
        // Wait a moment for final transcription
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        guard !transcribedText.isEmpty else {
            errorMessage = "No text was transcribed"
            return
        }
        
        // Paste the transcribed text
        await ClipboardHelper.pasteText(transcribedText)
        
        // Show success notification
        showToast("Voice input transcribed and pasted")
        
        // Clear transcribed text after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.transcribedText = ""
        }
    }
    
    private func showToast(_ message: String) {
        NotificationCenter.default.post(
            name: .showToast,
            object: ToastMessage(text: message, style: .success, duration: 2.0)
        )
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceInputManager: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available {
                self.errorMessage = "Speech recognition is no longer available"
                self.stopRecording()
            }
        }
    }
}
