import Cocoa
import SwiftUI

class AboutWindowController {
    static let shared = AboutWindowController()
    
    private var aboutWindow: NSWindow?
    
    private init() {}
    
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
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                // Window closed, but keep reference for reuse
            }
            
            window.makeKeyAndOrderFront(nil)
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

