import Cocoa
import SwiftUI

/// Custom view controller that adds native macOS blur background to SwiftUI content
class BlurredPopoverViewController: NSViewController {
    private let rootView: AnyView
    private var hostingView: NSView?

    init<Content: View>(rootView: Content) {
        self.rootView = AnyView(rootView)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        // Create the main container view
        let containerView = NSView()
        containerView.wantsLayer = true

        // Create visual effect view for native blur
        let visualEffectView = NSVisualEffectView()
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .popover  // Native popover material
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        // Add blur view to container
        containerView.addSubview(visualEffectView)

        // Create hosting controller for SwiftUI content
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        // Make SwiftUI view transparent so blur shows through
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = .clear

        // Add SwiftUI view on top of blur
        visualEffectView.addSubview(hostingController.view)

        // Setup constraints
        NSLayoutConstraint.activate([
            // Blur view fills container
            visualEffectView.topAnchor.constraint(equalTo: containerView.topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            // SwiftUI view fills blur view
            hostingController.view.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        // Add hosting controller as child
        addChild(hostingController)

        self.view = containerView
        self.hostingView = hostingController.view
    }
}
