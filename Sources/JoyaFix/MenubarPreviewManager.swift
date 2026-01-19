import SwiftUI
import AppKit

/// Manages the menubar hover preview for clipboard items
@MainActor
class MenubarPreviewManager: ObservableObject {
    static let shared = MenubarPreviewManager()
    
    private var previewPopover: NSPopover?
    private var statusButton: NSStatusBarButton?
    private var hoverTimer: Timer?
    
    private init() {}
    
    func setupPreview(for button: NSStatusBarButton) {
        guard SettingsManager.shared.enableMenubarPreview else { return }
        
        self.statusButton = button
        
        // Use NSPopover with hover behavior instead of tracking area
        // This is more reliable for status bar items
        setupHoverPopover(for: button)
        
        // Observe clipboard changes to update preview
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipboardChanged),
            name: NSNotification.Name("JoyaFixClipboardChanged"),
            object: nil
        )
    }
    
    private func setupHoverPopover(for button: NSStatusBarButton) {
        // Monitor mouse position periodically
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard SettingsManager.shared.enableMenubarPreview else { return }
            
            let mouseLocation = NSEvent.mouseLocation
            let screenFrame = NSScreen.main?.frame ?? .zero
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
            
            // Check if mouse is over button
            if buttonFrame.contains(mouseLocation) {
                if previewPopover?.isShown != true {
                    showPreview()
                }
            } else {
                if previewPopover?.isShown == true {
                    hidePreview()
                }
            }
        }
    }
    
    @objc private func clipboardChanged() {
        // Update preview if it's currently shown
        if previewPopover?.isShown == true {
            hidePreview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showPreview()
            }
        }
    }
    
    private func showPreview() {
        guard let button = statusButton else { return }
        guard let lastItem = ClipboardHistoryManager.shared.history.first else { return }
        
        // Don't show if popover is already open
        if let existingPopover = previewPopover, existingPopover.isShown {
            return
        }
        
        // Create preview popover
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 300, height: 200)
        
        let previewView = MenubarPreviewView(item: lastItem) { [weak self] in
            // Copy again action
            self?.copyItemAgain(lastItem)
        }
        
        popover.contentViewController = NSHostingController(rootView: previewView)
        self.previewPopover = popover
        
        // Show popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Auto-hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if popover.isShown {
                self.hidePreview()
            }
        }
    }
    
    private func hidePreview() {
        previewPopover?.close()
        previewPopover = nil
    }
    
    private func copyItemAgain(_ item: ClipboardItem) {
        ClipboardHistoryManager.shared.pasteItem(item, simulatePaste: false, formattingOption: .normal)
        hidePreview()
    }
}

// MARK: - Menubar Preview View

struct MenubarPreviewView: View {
    let item: ClipboardItem
    let onCopyAgain: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: item.isImage ? "photo" : "doc.text")
                    .foregroundColor(.accentColor)
                Text("Last Clipboard Item")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            
            Divider()
            
            // Content Preview
            if item.isImage {
                if let imagePath = item.imagePath, let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 100)
                } else {
                    Text("Image")
                        .foregroundColor(.secondary)
                }
            } else {
                Text(item.plainTextPreview)
                    .font(.system(size: 10))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            // Action Button
            Button(action: onCopyAgain) {
                HStack {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                    Text("Copy Again")
                        .font(.system(size: 10))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300, height: 200)
    }
}
