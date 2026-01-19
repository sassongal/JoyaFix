import Cocoa
import SwiftUI

class AboutWindowController {
    static let shared = AboutWindowController()
    
    private var aboutWindow: NSWindow?
    private var windowCloseObserver: NSObjectProtocol?
    
    private init() {}
    
    deinit {
        // Remove observer on deinit
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Shows the About window, creating it if necessary
    func show() {
        DispatchQueue.main.async {
            // Check if window already exists and is visible
            if let existingWindow = self.aboutWindow, existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                existingWindow.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            
            // Create new About window
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            
            window.title = "About JoyaFix"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            
            // Handle window closing
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
            
            self.aboutWindow = window
        }
    }
    
    /// Closes the About window
    func close() {
        DispatchQueue.main.async {
            self.aboutWindow?.close()
        }
    }
}

