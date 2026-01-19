import Cocoa
import ApplicationServices
import AVFoundation
import Speech

/// Manages system permissions required by JoyaFix
class PermissionManager {
    static let shared = PermissionManager()
    
    // Cache for permission status (refreshed periodically)
    private var cachedAccessibilityStatus: Bool?
    private var lastAccessibilityCheck: Date?
    private let cacheValidityInterval: TimeInterval = 2.0 // Refresh cache every 2 seconds
    
    private init() {
        // Listen for app activation to refresh permissions when user returns from Settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppActivation),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppActivation() {
        // Clear cache and refresh when app becomes active (user might have changed permissions in Settings)
        // Small delay to ensure system has updated permission status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            _ = self.refreshAccessibilityStatus()
        }
    }
    
    /// Invalidates the permission cache to force fresh check
    func invalidateCache() {
        cachedAccessibilityStatus = nil
        lastAccessibilityCheck = nil
    }
    
    // MARK: - Permission Checks
    
    /// Checks if Accessibility permissions are granted (with cache to avoid excessive system calls)
    /// Always checks the real system state, but caches result briefly to improve performance
    func isAccessibilityTrusted() -> Bool {
        // Check if cache is still valid
        if let cached = cachedAccessibilityStatus,
           let lastCheck = lastAccessibilityCheck,
           Date().timeIntervalSince(lastCheck) < cacheValidityInterval {
            return cached
        }
        
        // Force fresh check from system (no prompt)
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        // Update cache
        cachedAccessibilityStatus = isTrusted
        lastAccessibilityCheck = Date()
        
        return isTrusted
    }
    
    /// Forces a fresh check of Accessibility permissions (bypasses cache)
    func refreshAccessibilityStatus() -> Bool {
        invalidateCache()
        return isAccessibilityTrusted()
    }
    
    /// Checks if Screen Recording permissions are granted
    func isScreenRecordingTrusted() -> Bool {
        // On macOS, we check screen recording permissions by attempting a test capture
        // We use screencapture CLI to test if we have permission
        
        let testFile = NSTemporaryDirectory() + "joyafix_permission_test_\(UUID().uuidString).png"
        defer {
            // Clean up test file
            try? FileManager.default.removeItem(atPath: testFile)
        }
        
        // Try to capture a 1x1 pixel area - this requires screen recording permission
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = [
            "-R", "0,0,1,1",  // Capture 1x1 pixel at top-left
            "-x",  // No sound
            "-t", "png",
            testFile
        ]
        
        // Suppress output
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        task.launch()
        task.waitUntilExit()
        
        // Check if capture succeeded and file was created
        if task.terminationStatus == 0 {
            // Check if file actually exists and has content
            if FileManager.default.fileExists(atPath: testFile) {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: testFile)[.size] as? Int) ?? 0
                return fileSize > 0
            }
        }
        
        return false
    }
    
    // MARK: - Permission Requests
    
    /// Attempts to trigger system permission prompts for all required permissions
    func requestAllPermissions() {
        // Request Accessibility permission
        if !isAccessibilityTrusted() {
            requestAccessibilityPermission()
        }
        
        // Screen Recording permission is requested automatically when screencapture is called
        // We can't proactively request it, but we can inform the user
    }
    
    /// Requests Accessibility permission by triggering the system prompt
    private func requestAccessibilityPermission() {
        // Invalidate cache before requesting (to ensure fresh check after user grants)
        invalidateCache()
        
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Refresh status after a short delay to check if user granted permission
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = self.refreshAccessibilityStatus()
        }
    }
    
    // MARK: - System Settings
    
    /// Opens System Settings to the Accessibility section
    func openAccessibilitySettings() {
        // Invalidate cache before opening settings (user might change permissions)
        invalidateCache()
        
        if #available(macOS 13.0, *) {
            // macOS Ventura and later
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            // macOS Monterey and earlier
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        
        // Note: handleAppActivation() will automatically refresh permissions when app becomes active
        // (observer is already set up in init)
    }
    
    /// Opens System Settings to the Screen Recording section
    func openScreenRecordingSettings() {
        if #available(macOS 13.0, *) {
            // macOS Ventura and later
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        } else {
            // macOS Monterey and earlier
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
    
    // MARK: - Permission Status
    
    /// Checks if Microphone permission is granted
    func isMicrophoneGranted() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    /// Checks if Speech Recognition permission is granted
    func isSpeechRecognitionGranted() -> Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    /// Opens System Settings to the Microphone section
    func openMicrophoneSettings() {
        if #available(macOS 13.0, *) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }
    
    /// Opens System Settings to the Speech Recognition section
    func openSpeechRecognitionSettings() {
        if #available(macOS 13.0, *) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        }
    }
    
    /// Returns a dictionary with the status of all required permissions (fresh check)
    func getAllPermissionStatus() -> [String: Bool] {
        // Force fresh check for all permissions
        return [
            "accessibility": refreshAccessibilityStatus(),
            "screenRecording": isScreenRecordingTrusted(),
            "microphone": isMicrophoneGranted(),
            "speechRecognition": isSpeechRecognitionGranted()
        ]
    }
    
    /// Checks if all required permissions are granted (fresh check)
    func hasAllPermissions() -> Bool {
        return refreshAccessibilityStatus() && 
               isScreenRecordingTrusted() && 
               isMicrophoneGranted() && 
               isSpeechRecognitionGranted()
    }
    
    /// Synchronizes permission status with system (forces refresh of all permissions)
    /// Call this when you suspect permissions might have changed
    /// This is especially important after installing the app or when returning from System Settings
    func synchronizePermissions() {
        print("🔄 Synchronizing permissions with system...")
        invalidateCache()
        let accessibilityStatus = refreshAccessibilityStatus()
        let screenRecordingStatus = isScreenRecordingTrusted()
        let microphoneStatus = isMicrophoneGranted()
        let speechRecognitionStatus = isSpeechRecognitionGranted()
        print("  - Accessibility: \(accessibilityStatus ? "✓ Granted" : "✗ Not granted")")
        print("  - Screen Recording: \(screenRecordingStatus ? "✓ Granted" : "✗ Not granted")")
        print("  - Microphone: \(microphoneStatus ? "✓ Granted" : "✗ Not granted")")
        print("  - Speech Recognition: \(speechRecognitionStatus ? "✓ Granted" : "✗ Not granted")")
    }
    
    // MARK: - Onboarding Alert
    
    /// Shows an alert explaining required permissions and provides buttons to grant them
    func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "JoyaFix Requires Permissions"
            alert.informativeText = """
            JoyaFix needs the following permissions to work properly:
            
            • Accessibility: Required to simulate keyboard shortcuts (Cmd+C, Cmd+V, Delete)
            • Screen Recording: Required to capture screen regions for OCR
            • Microphone: Required for voice input feature (⌘⌥V)
            • Speech Recognition: Required for voice input transcription
            
            Click "Open Settings" to grant these permissions, then return to this app.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                // Open Accessibility settings first
                self.openAccessibilitySettings()
                
                // After a delay, also show other permissions info
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let screenAlert = NSAlert()
                    screenAlert.messageText = "Additional Permissions"
                    screenAlert.informativeText = """
                    You may also need to grant:
                    
                    • Screen Recording: For OCR feature (⌥⌘X)
                    • Microphone: For voice input (⌘⌥V)
                    • Speech Recognition: For voice input transcription
                    
                    These can be granted in System Settings → Privacy & Security.
                    """
                    screenAlert.alertStyle = .informational
                    screenAlert.addButton(withTitle: "OK")
                    _ = screenAlert.runModal()
                }
            }
        }
    }
}

