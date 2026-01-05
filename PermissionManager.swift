import Cocoa
import ApplicationServices

/// Manages system permissions required by JoyaFix
class PermissionManager {
    static let shared = PermissionManager()
    
    private init() {}
    
    // MARK: - Permission Checks
    
    /// Checks if Accessibility permissions are granted
    func isAccessibilityTrusted() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
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
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - System Settings
    
    /// Opens System Settings to the Accessibility section
    func openAccessibilitySettings() {
        if #available(macOS 13.0, *) {
            // macOS Ventura and later
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            // macOS Monterey and earlier
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
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
    
    /// Returns a dictionary with the status of all required permissions
    func getAllPermissionStatus() -> [String: Bool] {
        return [
            "accessibility": isAccessibilityTrusted(),
            "screenRecording": isScreenRecordingTrusted()
        ]
    }
    
    /// Checks if all required permissions are granted
    func hasAllPermissions() -> Bool {
        return isAccessibilityTrusted() && isScreenRecordingTrusted()
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
            
            Click "Open Settings" to grant these permissions, then return to this app.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                // Open Accessibility settings first
                self.openAccessibilitySettings()
                
                // After a delay, also show screen recording info
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let screenAlert = NSAlert()
                    screenAlert.messageText = "Screen Recording Permission"
                    screenAlert.informativeText = """
                    Screen Recording permission will be requested automatically when you use the OCR feature (⌥⌘X).
                    
                    You can also grant it now in System Settings → Privacy & Security → Screen Recording.
                    """
                    screenAlert.alertStyle = .informational
                    screenAlert.addButton(withTitle: "Open Screen Recording Settings")
                    screenAlert.addButton(withTitle: "OK")
                    
                    let screenResponse = screenAlert.runModal()
                    if screenResponse == .alertFirstButtonReturn {
                        self.openScreenRecordingSettings()
                    }
                }
            }
        }
    }
}

