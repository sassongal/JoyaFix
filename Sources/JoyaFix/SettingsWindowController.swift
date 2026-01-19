import Cocoa
import SwiftUI

class SettingsWindowController {
    static let shared = SettingsWindowController()
    
    private var settingsWindow: NSWindow?
    private var windowCloseObserver: NSObjectProtocol?
    
    private init() {}
    
    deinit {
        // Remove observer on deinit
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Shows the settings window, creating it if necessary
    func show() {
        DispatchQueue.main.async {
            // Check if window already exists and is visible
            if let existingWindow = self.settingsWindow, existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                existingWindow.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            
            // Create new settings window
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 550),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            window.title = "JoyaFix Settings"
            window.contentViewController = hostingController
            window.center()
            window.setFrameAutosaveName("JoyaFixSettings")
            window.isReleasedWhenClosed = false
            
            // Handle window closing - keep reference for reuse
            // Remove previous observer if exists
            if let previousObserver = self.windowCloseObserver {
                NotificationCenter.default.removeObserver(previousObserver)
            }
            
            self.windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] notification in
                // Window closed, but keep reference for reuse
                // Remove observer when window closes
                if let observer = self?.windowCloseObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self?.windowCloseObserver = nil
                }
            }
            
            // Premium entrance animation
            window.showWithPremiumAnimation()
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            
            self.settingsWindow = window
        }
    }
    
    /// Closes the settings window
    func close() {
        DispatchQueue.main.async {
            self.settingsWindow?.close()
        }
    }
}

