import SwiftUI
import AppKit

/// Prominent loading overlay for AI operations with animated visuals
struct AILoadingOverlayView: View {
    let status: String
    let onCancel: (() -> Void)?

    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var dotPhase: Int = 0

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Loading card
            VStack(spacing: 20) {
                // Animated AI icon
                ZStack {
                    // Outer spinning ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.orange, .purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(rotationAngle))

                    // Inner pulsing icon
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(pulseScale)
                }

                // Status text
                Text(status.isEmpty ? "Processing..." : status)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)

                // Animated progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                            .opacity(dotOpacity(for: index))
                    }
                }

                // Cancel button (optional)
                if let onCancel = onCancel {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 8)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 20)
            )
        }
        .onAppear {
            startAnimations()
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        let phase = (dotPhase + index) % 3
        return phase == 0 ? 1.0 : 0.3
    }

    private func startAnimations() {
        // Spinning ring animation
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }

        // Pulsing icon animation
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }

        // Progress dots animation
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                dotPhase = (dotPhase + 1) % 3
            }
        }
    }
}

// MARK: - Loading Overlay Window Controller

class AILoadingOverlayWindowController: NSWindowController {
    static var shared: AILoadingOverlayWindowController?

    private var statusObserver: NSKeyValueObservation?
    private var currentStatus: String = ""
    private var cancelHandler: (() -> Void)?

    /// Shows the loading overlay with dynamic status updates
    /// - Parameters:
    ///   - initialStatus: Initial status message to display
    ///   - onCancel: Optional callback when cancel button is pressed
    static func show(initialStatus: String = "Processing...", onCancel: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            // Dismiss existing overlay
            shared?.close()

            let controller = AILoadingOverlayWindowController()
            controller.currentStatus = initialStatus
            controller.cancelHandler = onCancel
            controller.setupWindow()
            shared = controller
            controller.showWindow(nil)
        }
    }

    /// Updates the status text displayed in the overlay
    /// - Parameter status: New status message
    static func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            guard let controller = shared else { return }
            controller.currentStatus = status
            controller.refreshView()
        }
    }

    /// Dismisses the loading overlay
    static func dismiss() {
        DispatchQueue.main.async {
            shared?.close()
            shared = nil
        }
    }

    private func setupWindow() {
        // Get the main screen size for centering
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 280),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.center()
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        // Make window cover the entire screen for backdrop effect
        window.setFrame(screenFrame, display: true)

        let view = AILoadingOverlayView(
            status: currentStatus,
            onCancel: cancelHandler
        )
        window.contentView = NSHostingView(rootView: view)

        self.window = window
    }

    private func refreshView() {
        guard let window = window else { return }

        let view = AILoadingOverlayView(
            status: currentStatus,
            onCancel: cancelHandler
        )
        window.contentView = NSHostingView(rootView: view)
    }

    override func close() {
        window?.orderOut(nil)
        window?.close()
    }
}

// MARK: - Preview

#if DEBUG
struct AILoadingOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        AILoadingOverlayView(
            status: "Enhancing with Gemini...",
            onCancel: { Logger.info("Loading cancelled", category: Logger.general) }
        )
        .frame(width: 400, height: 350)
    }
}
#endif
