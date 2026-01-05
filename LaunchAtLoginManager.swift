import Foundation
import ServiceManagement
import AppKit
import CoreServices

/// Manages "Launch at Login" functionality using SMAppService (macOS 13+) or SMLoginItemSetEnabled (fallback)
@MainActor
class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    
    private init() {}
    
    // MARK: - Launch at Login
    
    /// Checks if app is set to launch at login
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            // Use modern SMAppService API
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback to legacy API
            return isLegacyLaunchAtLoginEnabled()
        }
    }
    
    /// Enables or disables launch at login
    /// - Parameter enabled: True to enable, false to disable
    /// - Returns: True if operation succeeded, false otherwise
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            // Use modern SMAppService API
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                print("✓ Launch at Login \(enabled ? "enabled" : "disabled") (SMAppService)")
                return true
            } catch {
                print("❌ Failed to \(enabled ? "enable" : "disable") Launch at Login: \(error.localizedDescription)")
                return false
            }
        } else {
            // Fallback to legacy API
            let success = SMLoginItemSetEnabled("com.joyafix.app.LaunchHelper" as CFString, enabled)
            if success {
                print("✓ Launch at Login \(enabled ? "enabled" : "disabled") (SMLoginItemSetEnabled)")
            } else {
                print("❌ Failed to \(enabled ? "enable" : "disable") Launch at Login (legacy API)")
            }
            return success
        }
    }
    
    /// Legacy method to check launch at login status (macOS < 13)
    private func isLegacyLaunchAtLoginEnabled() -> Bool {
        // Check if login item exists
        guard let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?.takeRetainedValue() else {
            return false
        }
        
        let appURL = Bundle.main.bundleURL
        let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue()
        
        guard let items = loginItemsSnapshot as? [LSSharedFileListItem] else {
            return false
        }
        
        for item in items {
            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL? {
                if itemURL.path == appURL.path {
                    return true
                }
            }
        }
        
        return false
    }
}

