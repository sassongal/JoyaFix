import Cocoa
import SwiftUI

class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    
    private var onboardingWindow: NSWindow?
    
    private init() {}
    
    /// Shows the onboarding window
    func show(completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            // Create new onboarding window
            let onboardingView = OnboardingView(onComplete: {
                self.close()
                completion()
            })
            let hostingController = NSHostingController(rootView: onboardingView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            
            window.title = "Welcome to JoyaFix"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.isMovableByWindowBackground = true
            
            // Prevent closing via close button (user must complete onboarding)
            window.standardWindowButton(.closeButton)?.isHidden = true
            
            // Premium entrance animation
            window.showWithPremiumAnimation()
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            
            self.onboardingWindow = window
        }
    }
    
    /// Closes the onboarding window
    func close() {
        DispatchQueue.main.async {
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
        }
    }
}

