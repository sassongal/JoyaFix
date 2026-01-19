import AppKit

/// Utility for opening macOS System Preferences to specific permission panels
enum PermissionDeepLinker {
    /// Opens System Preferences to Accessibility settings
    static func openAccessibility() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: open System Preferences manually
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
        }
    }
    
    /// Opens System Preferences to Input Monitoring settings
    static func openInputMonitoring() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback
            openAccessibility()
        }
    }
    
    /// Opens System Preferences to Screen Recording settings
    static func openScreenRecording() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            openAccessibility()
        }
    }
    
    /// Opens System Preferences to Microphone settings
    static func openMicrophone() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            openAccessibility()
        }
    }
    
    /// Opens System Preferences to Camera settings
    static func openCamera() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            openAccessibility()
        }
    }
}
