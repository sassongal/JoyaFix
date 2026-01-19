import Cocoa
import SwiftUI

/// Window controller for the AI Prompt Review HUD
class PromptReviewWindowController: NSWindowController {
    static var shared: PromptReviewWindowController?
    
    private var promptText: String
    private var onConfirm: () -> Void
    private var onCancel: () -> Void
    private var onRefine: (String) -> Void
    
    private init(promptText: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void, onRefine: @escaping (String) -> Void) {
        self.promptText = promptText
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onRefine = onRefine
        
        // Create HUD-style window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),  // Matches PromptReviewView
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.center()
        
        super.init(window: window)
        
        // Create SwiftUI view
        let hostingView = NSHostingView(rootView: PromptReviewView(
            promptText: Binding(
                get: { self.promptText },
                set: { self.promptText = $0 }
            ),
            onConfirm: {
                self.onConfirm()
                self.closeWindow()
            },
            onCancel: {
                self.onCancel()
                self.closeWindow()
            },
            onRefine: { refineRequest in
                self.onRefine(refineRequest)
            }
        ))
        
        window.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    static func show(promptText: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void, onRefine: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            // Close existing window if any
            shared?.closeWindow()
            
            // Create new window
            shared = PromptReviewWindowController(
                promptText: promptText,
                onConfirm: onConfirm,
                onCancel: onCancel,
                onRefine: onRefine
            )
            
            shared?.showWindow(nil)
            // HUD-style entrance animation (slide down + fade)
            shared?.window?.showWithHUDAnimation()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    /// Static method to close the review window
    static func closeWindow() {
        DispatchQueue.main.async {
            shared?.closeWindow()
        }
    }
    
    override func close() {
        DispatchQueue.main.async {
            self.window?.close()
            PromptReviewWindowController.shared = nil
        }
    }
    
    /// Closes the window programmatically
    func closeWindow() {
        DispatchQueue.main.async {
            self.window?.close()
            PromptReviewWindowController.shared = nil
        }
    }
}

