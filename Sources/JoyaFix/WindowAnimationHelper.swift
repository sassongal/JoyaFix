import AppKit

/// Premium window animation utilities for polished app feel
extension NSWindow {
    /// Shows window with smooth fade-in and subtle scale animation
    /// Creates expensive, premium app feel (like macOS Ventura+ system apps)
    func showWithPremiumAnimation(duration: TimeInterval = 0.25) {
        // Set initial state
        self.alphaValue = 0.0

        // Calculate initial scale transform (95% size)
        let initialFrame = self.frame
        let scaleX: CGFloat = 0.95
        let scaleY: CGFloat = 0.95

        // Calculate scaled frame (centered)
        let scaledWidth = initialFrame.width * scaleX
        let scaledHeight = initialFrame.height * scaleY
        let offsetX = (initialFrame.width - scaledWidth) / 2
        let offsetY = (initialFrame.height - scaledHeight) / 2

        var scaledFrame = initialFrame
        scaledFrame.size.width = scaledWidth
        scaledFrame.size.height = scaledHeight
        scaledFrame.origin.x += offsetX
        scaledFrame.origin.y += offsetY

        self.setFrame(scaledFrame, display: false)

        // Show window
        self.makeKeyAndOrderFront(nil)

        // Animate to final state
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true

            // Fade in
            self.animator().alphaValue = 1.0

            // Scale to normal size
            self.animator().setFrame(initialFrame, display: true)
        }
    }

    /// Shows window with HUD-style animation (slide down + fade)
    /// Perfect for borderless floating windows like PromptReviewWindowController
    func showWithHUDAnimation(duration: TimeInterval = 0.2, slideDistance: CGFloat = 20) {
        // Set initial state
        self.alphaValue = 0.0

        // Calculate initial position (slightly higher)
        var initialFrame = self.frame
        initialFrame.origin.y += slideDistance

        self.setFrame(initialFrame, display: false)

        // Show window
        self.makeKeyAndOrderFront(nil)

        // Animate to final state
        var finalFrame = initialFrame
        finalFrame.origin.y -= slideDistance

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            // Fade in
            self.animator().alphaValue = 1.0

            // Slide down to position
            self.animator().setFrame(finalFrame, display: true)
        }
    }

    /// Hides window with smooth fade-out animation
    /// Optional completion handler for cleanup
    func hideWithAnimation(duration: TimeInterval = 0.15, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true

            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            completion?()
        })
    }
}
