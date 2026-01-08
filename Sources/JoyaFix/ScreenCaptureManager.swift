#if false
import Cocoa
@preconcurrency import Vision
import CoreGraphics
import Foundation
import CoreImage

@MainActor
class ScreenCaptureManager {
    static let shared = ScreenCaptureManager(
        ocrService: OCRService(
            settingsManager: SettingsManager.shared,
            geminiService: GeminiService.shared
        )
    )

    private let ocrService: OCRService
    private var overlayWindow: SelectionOverlayWindow?
    // FIX: Support multiple monitors - array of overlay windows (one per screen)
    private var overlayWindows: [SelectionOverlayWindow] = []
    private var completion: ((String?) -> Void)?
    private var escapeKeyMonitor: Any?
    private var escapeKeyLocalMonitor: Any?
    
    // OPTIMIZATION: Global mouse tracking for smooth cross-screen dragging
    private var globalMouseMonitor: Any?
    private var sharedSelectionState: SharedSelectionState?
    
    /// Shared state for cross-screen selection synchronization
    @MainActor
    class SharedSelectionState {
        var startPoint: NSPoint?
        var currentPoint: NSPoint?
        var isSelecting: Bool = false
        var confirmedSelection: NSRect?
        
        func reset() {
            startPoint = nil
            currentPoint = nil
            isSelecting = false
            confirmedSelection = nil
        }
    }
    
    // CRITICAL FIX: Simple flag to prevent concurrent captures
    // MUST be checked FIRST in startScreenCapture
    private var isCapturing = false
    
    // CRASH PREVENTION: Track cursor state to prevent unbalanced push/pop
    private var cursorPushed = false
    
    // Multi-monitor lifecycle: Track screen configuration to detect changes
    private var screenConfigurationObserver: NSObjectProtocol?
    private var lastKnownScreenCount: Int = 0

    private init(ocrService: OCRService) {
        self.ocrService = ocrService
        setupScreenConfigurationObserver()
    }
    
    deinit {
        // Remove observer on deallocation
        if let observer = screenConfigurationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Interface

    /// Starts the screen capture flow with selection overlay
    func startScreenCapture(completion: @escaping (String?) -> Void) {
        // CRITICAL FIX: This MUST be the first check to prevent concurrent captures
        guard !isCapturing else {
            print("⚠️ Screen capture already active, ignoring new request")
            completion(nil)
            return
        }
        
        // Set flag immediately to prevent race conditions
        isCapturing = true
        
        // Cleanup any existing state before starting new capture
        cleanupExistingSession()
        
        self.completion = completion
        showSelectionOverlay()
    }
    
    // MARK: - Safety Cleanup
    
    private func cleanupExistingSession() {
        // Remove monitors safely
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
        
        // FIX: Remove local monitor to prevent memory leak
        if let localMonitor = escapeKeyLocalMonitor {
            NSEvent.removeMonitor(localMonitor)
            escapeKeyLocalMonitor = nil
        }
        
        // CRITICAL FIX: Remove global mouse monitor to prevent memory leak
        if let mouseMonitor = globalMouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            globalMouseMonitor = nil
        }
        
        // FIX: Restore cursor safely - use set() instead of pop() to prevent crashes
        NSCursor.arrow.set() // Force cursor back to arrow (safe)
        cursorPushed = false
        
        // Clear shared selection state
        sharedSelectionState?.reset()
        sharedSelectionState = nil
        
        // Close all overlay windows safely
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        
        // Close single window reference (backward compatibility)
        if let window = overlayWindow {
            window.orderOut(nil)
            window.close()
            overlayWindow = nil
        }
    }

    // MARK: - Screen Configuration Monitoring
    
    /// Sets up observer for screen configuration changes (monitor connect/disconnect)
    private func setupScreenConfigurationObserver() {
        screenConfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenConfigurationChange()
        }
        
        // Store initial screen count
        lastKnownScreenCount = NSScreen.screens.count
    }
    
    /// Handles screen configuration changes (monitor connect/disconnect)
    /// Cleans up orphaned windows and recreates overlay if needed
    private func handleScreenConfigurationChange() {
        guard isCapturing else { return }
        
        let currentScreenCount = NSScreen.screens.count
        let screenCountChanged = currentScreenCount != lastKnownScreenCount
        
        print("📺 Screen configuration changed: \(lastKnownScreenCount) → \(currentScreenCount) screens")
        
        // Update stored screen count
        lastKnownScreenCount = currentScreenCount
        
        // Clean up orphaned windows (windows whose screen no longer exists)
        cleanupOrphanedWindows()
        
        // If screen count changed and we're still capturing, recreate overlay
        if screenCountChanged {
            print("🔄 Recreating overlay windows due to screen configuration change")
            // Recreate overlay to match new screen configuration
            showSelectionOverlay()
        } else {
            // Screen count unchanged but configuration might have changed (resolution, position, etc.)
            // Validate and update existing windows
            validateAndUpdateOverlayWindows()
        }
    }
    
    /// Removes overlay windows whose screen no longer exists
    private func cleanupOrphanedWindows() {
        let validScreens = Set(NSScreen.screens)
        var orphanedWindows: [SelectionOverlayWindow] = []
        
        // Find windows whose screen is no longer valid
        for window in overlayWindows {
            // Check if window's screen still exists
            if let windowScreen = window.screen {
                if !validScreens.contains(windowScreen) {
                    orphanedWindows.append(window)
                }
            } else {
                // Window has no screen - it's orphaned
                orphanedWindows.append(window)
            }
        }
        
        // Close and remove orphaned windows
        for orphanedWindow in orphanedWindows {
            print("🗑️ Removing orphaned overlay window")
            orphanedWindow.orderOut(nil)
            orphanedWindow.close()
            overlayWindows.removeAll { $0 === orphanedWindow }
        }
        
        // Update single window reference if it was orphaned
        if let window = overlayWindow, orphanedWindows.contains(where: { $0 === window }) {
            overlayWindow = overlayWindows.first(where: { $0.screen == NSScreen.main }) ?? overlayWindows.first
        }
    }
    
    /// Validates existing overlay windows and updates them if needed
    private func validateAndUpdateOverlayWindows() {
        let currentScreens = NSScreen.screens
        var windowsToKeep: [SelectionOverlayWindow] = []
        
        // Keep only windows that match current screens
        for screen in currentScreens {
            // Find window for this screen
            if let existingWindow = overlayWindows.first(where: { $0.screen == screen }) {
                // Validate window frame matches screen frame
                let screenFrame = screen.frame
                if existingWindow.frame != screenFrame {
                    print("🔄 Updating overlay window frame for screen: \(screenFrame)")
                    existingWindow.setFrame(screenFrame, display: true)
                }
                windowsToKeep.append(existingWindow)
            } else {
                // Missing window for this screen - create it
                print("➕ Creating missing overlay window for screen")
                let window = createOverlayWindow(for: screen)
                windowsToKeep.append(window)
            }
        }
        
        // Replace overlay windows array
        overlayWindows = windowsToKeep
        
        // Update single window reference
        overlayWindow = overlayWindows.first(where: { $0.screen == NSScreen.main }) ?? overlayWindows.first
    }
    
    /// Creates an overlay window for a specific screen
    private func createOverlayWindow(for screen: NSScreen) -> SelectionOverlayWindow {
        let screenFrame = screen.frame
        
        let window = SelectionOverlayWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.selectionDelegate = self
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        
        // Position window on the correct screen
        window.setFrameOrigin(screenFrame.origin)
        
        // Make sure window can receive key events
        window.makeKeyAndOrderFront(nil)
        
        // Set first responder only for main screen
        if screen == NSScreen.main {
            window.makeFirstResponder(window.contentView)
        }
        
        return window
    }

    // MARK: - Overlay Management

    private func showSelectionOverlay() {
        // Cleanup any existing overlay first
        cleanupExistingSession()
        
        // FIX: Create separate overlay window for each screen (multi-monitor support)
        // This fixes the issue where macOS "Displays have separate Spaces" prevents
        // a single window from spanning multiple screens properly
        
        // Clean up any orphaned windows first
        cleanupOrphanedWindows()
        
        // Remove existing windows (will be recreated)
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        
        // OPTIMIZATION: Create shared selection state for cross-screen synchronization
        sharedSelectionState = SharedSelectionState()
        
        // Create overlay window for each current screen
        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            // OPTIMIZATION: Share selection state across all windows for smooth cross-screen dragging
            if let selectionView = window.contentView as? SelectionView {
                selectionView.sharedState = sharedSelectionState
            }
            overlayWindows.append(window)
        }
        
        // Update stored screen count
        lastKnownScreenCount = NSScreen.screens.count
        
        // Keep backward compatibility with single overlayWindow reference
        // Use the main screen's window as the primary reference
        overlayWindow = overlayWindows.first(where: { $0.screen == NSScreen.main }) ?? overlayWindows.first
        
        // OPTIMIZATION: Add global mouse tracking for smooth cross-screen dragging
        setupGlobalMouseTracking()

        // Change cursor to crosshair
        NSCursor.crosshair.set()
        cursorPushed = true
        
        // Add global ESC key monitor as backup - use global monitor to catch ESC even when window loses focus
        // Note: Global monitors can't consume events, but we can still handle them
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isCapturing else { return }
            if event.keyCode == 53 { // ESC key
                print("⌨️ ESC pressed (Global Monitor)")
                Task { @MainActor in
                    self.didCancelSelection()
                }
            }
        }
        
        // Also add local monitor for window events - this CAN consume events
        // FIX: Store the local monitor so we can remove it in cleanup
        // Add monitor once (it will catch events from all windows)
        if !overlayWindows.isEmpty {
            escapeKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isCapturing else { return event }
                if event.keyCode == 53 { // ESC key
                    print("⌨️ ESC pressed (Local Monitor)")
                    Task { @MainActor in
                        self.didCancelSelection()
                    }
                    return nil // Consume the event to prevent it from propagating
                }
                return event
            }
        }
    }

    /// Sets up global mouse tracking for smooth cross-screen dragging
    private func setupGlobalMouseTracking() {
        // Remove existing monitor if any
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        
        // CRITICAL FIX: Throttle mouse updates to prevent Main Thread flooding
        // High polling rate mice (1000Hz+) can flood the queue, causing a "freeze"
        var lastUpdateTime: TimeInterval = 0
        let throttleInterval: TimeInterval = 0.016 // ~60fps Limit
        
        // Add global mouse tracking to synchronize selection across screens
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            guard let self = self, self.isCapturing, let sharedState = self.sharedSelectionState else { return }
            
            // THROTTLING CHECK: Only process if enough time has passed
            let currentTime = CACurrentMediaTime()
            if currentTime - lastUpdateTime < throttleInterval {
                return
            }
            lastUpdateTime = currentTime
            
            // Capture point locally to avoid capturing it inside the Task (which might be delayed)
            let globalPoint = NSEvent.mouseLocation
            
            Task { @MainActor in
                // Update shared state with global mouse position
                sharedState.currentPoint = globalPoint
                
                // Update all overlay windows to reflect the current selection
                for window in self.overlayWindows {
                    if let selectionView = window.contentView as? SelectionView {
                        // Update the view's display if the point is within this window's bounds
                        // expanded bounds slightly to handle edge cases
                        let paddedFrame = window.frame.insetBy(dx: -50, dy: -50)
                        if paddedFrame.contains(globalPoint) {
                            selectionView.updateFromSharedState()
                        }
                    }
                }
            }
        }
    }
    
    private func hideSelectionOverlay() {
        // Prevent double-cleanup with guard
        // CRITICAL FIX: Ensure we check all state variables that indicate active capture
        guard !overlayWindows.isEmpty || overlayWindow != nil || escapeKeyMonitor != nil || escapeKeyLocalMonitor != nil || cursorPushed else {
            return
        }

        print("🧹 Cleaning up selection overlay session...")

        // OPTIMIZATION: Remove global mouse tracking
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        
        // Clear shared selection state
        sharedSelectionState?.reset()
        sharedSelectionState = nil

        // Store references before clearing to avoid race conditions
        let windows = overlayWindows
        let window = overlayWindow
        let monitor = escapeKeyMonitor
        let localMonitor = escapeKeyLocalMonitor
        
        // Clear references immediately to prevent re-entry
        overlayWindows.removeAll()
        overlayWindow = nil
        escapeKeyMonitor = nil
        escapeKeyLocalMonitor = nil
        
        // FIX: Restore cursor safely - use set() instead of pop() to prevent crashes
        // NSCursor.pop() can crash if the cursor stack is empty or was reset by the system
        NSCursor.arrow.set() // Force cursor back to arrow (safe)
        cursorPushed = false
        
        // Remove Monitors safely
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // FIX: Remove local monitor to prevent memory leak
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        
        // Close all overlay windows safely
        for overlayWindow in windows {
            overlayWindow.orderOut(nil)
            overlayWindow.close()
        }
        
        // Close single window reference (backward compatibility)
        if let window = window {
            window.orderOut(nil)
            window.close()
        }
        
        // CRITICAL FIX: Reset capturing flag ONLY after everything is closed
        isCapturing = false
        print("✅ Selection overlay cleanup complete")
    }

    // MARK: - Native Screen Capture (CGWindowListCreateImage)

    /// Captures screen region using native CoreGraphics API
    /// Uses CGWindowListCreateImage to capture content underneath the overlay window
    private func captureScreen(rect: NSRect) {
        print("📸 Capturing screen region: \(rect)")
        print("📺 Available screens: \(NSScreen.screens.count)")

        // FIX: Check Screen Recording permission before attempting capture
        guard PermissionManager.shared.isScreenRecordingTrusted() else {
            print("⚠️ Screen Recording permission required for OCR")
            DispatchQueue.main.async {
                self.showScreenRecordingPermissionAlert()
            }
            // FIX: Clean up monitors and overlay in all error paths
            hideSelectionOverlay()
            completion?(nil)
            return
        }

        // Validate rect before capturing
        guard rect.width > 0 && rect.height > 0 && 
              rect.width < 100000 && rect.height < 100000 else {
            print("❌ Invalid capture rect: \(rect)")
            // FIX: Clean up monitors and overlay in all error paths
            hideSelectionOverlay()
            completion?(nil)
            return
        }

        // Validate rect
        guard rect.origin.x >= 0 && rect.origin.y >= 0 &&
              rect.width > 0 && rect.height > 0 else {
            print("❌ Invalid capture rect: \(rect)")
            // FIX: Clean up monitors and overlay in all error paths
            hideSelectionOverlay()
            completion?(nil)
            return
        }
        
        print("📐 Capturing screen region: \(rect)")
        
        // On macOS 15.0+, CGWindowListCreateImage is unavailable
        // Use screencapture CLI as fallback
        // Hide all overlay windows first, then capture
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindow?.orderOut(nil)
        
        // Small delay to ensure overlay is hidden
        // Store completion handler before async operation for safe access
        let completionHandler = self.completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            // Use screencapture CLI for screen capture
            self.captureScreenWithCLI(rect: rect, completion: completionHandler)
        }
    }
    
    /// Shows a user-friendly screen recording permission alert
    private func showScreenRecordingPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.screen.recording.title", comment: "Screen recording alert title")
        alert.informativeText = NSLocalizedString("alert.screen.recording.message", comment: "Screen recording alert message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("alert.button.open.settings", comment: "Open settings"))
        alert.addButton(withTitle: NSLocalizedString("alert.button.cancel", comment: "Cancel"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            PermissionManager.shared.openScreenRecordingSettings()
        }
    }
    
    // MARK: - Helper Methods
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.error.title", comment: "Error alert title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
        alert.runModal()
    }

    // MARK: - CLI Screen Capture (Fallback for macOS 15.0+)
    
    /// Captures screen region using screencapture CLI (fallback for macOS 15.0+)
    /// CRITICAL FIX: Runs on background thread to prevent UI freeze
    private func captureScreenWithCLI(rect: NSRect, completion: ((String?) -> Void)?) {
        let tempFile = NSTemporaryDirectory() + "joyafix_capture_\(UUID().uuidString).png"
        
        // Convert rect to screencapture format: x,y,width,height
        let captureRect = "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))"
        
        // CRITICAL FIX: Run CLI command on background thread to prevent UI freeze
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = [
                "-R", captureRect,
                "-x",  // No sound
                "-t", "png",
                tempFile
            ]
            
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            
            task.launch()
            task.waitUntilExit() // Now this doesn't block the main thread
            
            // Check results on background thread
            guard task.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: tempFile),
                  let image = NSImage(contentsOfFile: tempFile),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("❌ CLI screen capture failed")
                DispatchQueue.main.async {
                    // FIX: Clean up monitors and overlay in all error paths
                    self.hideSelectionOverlay()
                    completion?(nil)
                }
                // Clean up temp file
                do {
                    try FileManager.default.removeItem(atPath: tempFile)
                } catch {
                    print("🔥 Failed to remove temporary capture file at \(tempFile): \(error.localizedDescription)")
                }
                return
            }
            
            print("✓ Screen captured via CLI (\(Int(rect.width))×\(Int(rect.height))), starting OCR...")
            
            // Store completion handler before any async operations
            let completionHandler = self.completion
            
            // Perform OCR (this already handles threading internally)
            self.ocrService.extractText(from: cgImage) { text in
                Task { @MainActor in
                    self.isCapturing = false
                    
                    // Save to OCR history if text was extracted
                    if let extractedText = text, !extractedText.isEmpty {
                        let scan = OCRScan(extractedText: extractedText)
                        let nsImage = NSImage(contentsOfFile: tempFile)
                        if let previewImage = nsImage {
                            OCRHistoryManager.shared.savePreviewImage(previewImage, for: scan) { previewPath in
                                if let previewPath = previewPath {
                                    let scanWithImage = scan.withPreviewImagePath(previewPath)
                                    OCRHistoryManager.shared.addScan(scanWithImage)
                                } else {
                                    OCRHistoryManager.shared.addScan(scan)
                                }
                            }
                        } else {
                            OCRHistoryManager.shared.addScan(scan)
                        }
                        print("📸 OCR scan saved to history: \(extractedText.prefix(50))...")
                    } else {
                        // Handle no text found
                        print("⚠️ No text found in captured image")
                        self.showErrorAlert(message: NSLocalizedString("ocr.error.no.text", comment: "No text found in selection"))
                    }
                    
                    // Clean up temp file after OCR processing
                    do {
                        try FileManager.default.removeItem(atPath: tempFile)
                    } catch {
                        print("🔥 Failed to remove temporary capture file after OCR at \(tempFile): \(error.localizedDescription)")
                    }
                    
                    completionHandler?(text)
                }
            }
        }
    }
}

// MARK: - Selection Delegate

extension ScreenCaptureManager: SelectionOverlayDelegate {
    func didSelectRegion(_ rect: NSRect) {
        // Validate rect
        guard rect.width > 0 && rect.height > 0 else {
            print("⚠️ Invalid selection rect")
            didCancelSelection()
            return
        }
        
        // Hide overlay immediately (CGWindowListCreateImage will capture underneath it anyway)
        hideSelectionOverlay()
        
        // Capture immediately - no delays needed with CGWindowListCreateImage
        captureScreen(rect: rect)
    }

    func didCancelSelection() {
        // Store completion handler before clearing
        let completionHandler = completion
        completion = nil
        
        hideSelectionOverlay()
        
        // Call completion after cleanup
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(JoyaFixConstants.ocrCancelDelay * 1_000_000_000))
            completionHandler?(nil)
        }
    }
}

// MARK: - Selection Overlay Window

@MainActor
protocol SelectionOverlayDelegate: AnyObject {
    func didSelectRegion(_ rect: NSRect)
    func didCancelSelection()
}

class SelectionOverlayWindow: NSWindow {
    weak var selectionDelegate: SelectionOverlayDelegate?
    
    // CRASH PREVENTION: Track if window is closing to prevent operations during deallocation
    private var isClosing = false

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        let selectionView = SelectionView(frame: contentRect)
        selectionView.delegate = selectionDelegate
        contentView = selectionView
        
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { !isClosing }
    override var canBecomeMain: Bool { !isClosing }
    
    override func keyDown(with event: NSEvent) {
        // CRASH PREVENTION: Don't process events if closing
        guard !isClosing else { return }
        
        if event.keyCode == 53 { // ESC key
            print("⌨️ ESC pressed (Window)")
            // Call delegate safely
            if let delegate = selectionDelegate {
                Task { @MainActor in
                    delegate.didCancelSelection()
                }
            }
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func close() {
        // CRASH PREVENTION: Mark as closing before closing
        isClosing = true
        super.close()
    }
    
    deinit {
        // CRASH PREVENTION: Clean up when window is deallocated
        selectionDelegate = nil
        contentView = nil
    }
}

// MARK: - Selection View

class SelectionView: NSView {
    weak var delegate: SelectionOverlayDelegate?
    
    // OPTIMIZATION: Shared state for cross-screen synchronization
    var sharedState: ScreenCaptureManager.SharedSelectionState?

    private var startPoint: NSPoint? {
        get { sharedState?.startPoint }
        set { sharedState?.startPoint = newValue }
    }
    
    private var currentPoint: NSPoint? {
        get { sharedState?.currentPoint }
        set { sharedState?.currentPoint = newValue }
    }
    
    private var isSelecting: Bool {
        get { sharedState?.isSelecting ?? false }
        set { sharedState?.isSelecting = newValue }
    }
    
    private var confirmedSelection: NSRect? {
        get { sharedState?.confirmedSelection }
        set { sharedState?.confirmedSelection = newValue }
    }
    
    // CRASH PREVENTION: Track if view is being deallocated
    private var isValid = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = false
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // CRASH PREVENTION: Check validity
        guard isValid else { return }
        
        // OPTIMIZATION: Convert to global coordinates for cross-screen support
        guard let window = self.window else { return }
        // Convert window coordinates to global screen coordinates
        let windowFrame = window.frame
        let localPoint = event.locationInWindow
        let globalPoint = NSPoint(
            x: windowFrame.origin.x + localPoint.x,
            y: windowFrame.origin.y + localPoint.y
        )
        
        // Clear any previous confirmed selection when starting new selection
        confirmedSelection = nil
        
        // Store in shared state (global coordinates)
        startPoint = globalPoint
        currentPoint = globalPoint
        isSelecting = true
        
        // Update all views that share this state
        updateAllSharedViews()
    }
    
    /// Updates all views that share the same selection state
    private func updateAllSharedViews() {
        // Trigger redraw on all windows that share this state
        if let sharedState = sharedState {
            // Find all windows with views sharing this state
            for window in NSApplication.shared.windows {
                if let selectionView = window.contentView as? SelectionView,
                   selectionView.sharedState === sharedState {
                    selectionView.needsDisplay = true
                }
            }
        } else {
            needsDisplay = true
        }
    }
    
    /// Updates this view from shared state (called by global mouse tracking)
    func updateFromSharedState() {
        guard isValid else { return }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        // CRASH PREVENTION: Check validity
        guard isValid && isSelecting else { return }
        
        // OPTIMIZATION: Convert to global coordinates for cross-screen support
        guard let window = self.window else { return }
        // Convert window coordinates to global screen coordinates
        let windowFrame = window.frame
        let localPoint = event.locationInWindow
        let globalPoint = NSPoint(
            x: windowFrame.origin.x + localPoint.x,
            y: windowFrame.origin.y + localPoint.y
        )
        
        // Update shared state
        currentPoint = globalPoint
        
        // Update all views that share this state
        updateAllSharedViews()
    }

    override func mouseUp(with event: NSEvent) {
        // CRASH PREVENTION: Check validity
        guard isValid else { return }
        
        guard isSelecting, let start = startPoint, let end = currentPoint else {
            // Call delegate safely
            if let delegate = delegate {
                delegate.didCancelSelection()
            }
            return
        }

        // OPTIMIZATION: Points are already in global coordinates from shared state
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)

        // Prevent very small selections (clicks) from processing/crashing
        if width < JoyaFixConstants.minOCRSelectionSize || height < JoyaFixConstants.minOCRSelectionSize {
            print("⚠️ Selection too small - treating as cancel")
            isSelecting = false
            confirmedSelection = nil
            if let delegate = delegate {
                Task { @MainActor in
                    delegate.didCancelSelection()
                }
            }
            return
        }

        // OPTIMIZATION: Selection rect is already in global coordinates
        let globalRect = NSRect(x: minX, y: minY, width: width, height: height)
        
        print("📐 Selection rect (global): \(globalRect)")
        
        // Store the confirmed selection for ENTER key, but don't process it yet
        // User can press ENTER to confirm, or click again to start new selection
        confirmedSelection = globalRect
        isSelecting = false // Stop selecting, but keep the selection for ENTER
        
        // Update all views
        updateAllSharedViews()
        
        print("✓ Selection stored - press ENTER to confirm or click to start new selection")
    }

    override func keyDown(with event: NSEvent) {
        // CRASH PREVENTION: Check validity
        guard isValid else { return }
        
        // ENTER key (36) to confirm selection if one exists
        if event.keyCode == 36 {
            print("⌨️ ENTER pressed - confirming selection")
            
            // First check if we have a confirmed selection from mouseUp
            if let confirmed = confirmedSelection {
                print("📐 ENTER: Confirming stored selection: \(confirmed)")
                confirmedSelection = nil
                
                // Call delegate safely
                if let delegate = delegate {
                    Task { @MainActor in
                        delegate.didSelectRegion(confirmed)
                    }
                }
                return
            }
            
            // If we're currently selecting, confirm the current selection
            if isSelecting, let start = startPoint, let end = currentPoint {
                 // OPTIMIZATION: Points are already in global coordinates
                 let minX = min(start.x, end.x)
                 let minY = min(start.y, end.y)
                 let width = abs(end.x - start.x)
                 let height = abs(end.y - start.y)
                 
                 if width > 10 && height > 10 {
                     isSelecting = false
                     
                     // OPTIMIZATION: Selection rect is already in global coordinates
                     let globalRect = NSRect(x: minX, y: minY, width: width, height: height)
                     
                     print("📐 ENTER: Selection rect (global): \(globalRect)")
                     
                     // Call delegate safely
                     if let delegate = delegate {
                         Task { @MainActor in
                             delegate.didSelectRegion(globalRect)
                         }
                     }
                     return
                 } else {
                     print("⚠️ Selection too small for ENTER confirmation")
                 }
            } else {
                print("⚠️ No active selection to confirm with ENTER")
            }
        }
        
        // ESC to cancel
        if event.keyCode == 53 {
            print("⌨️ ESC pressed (Window keyDown)")
            // Call delegate safely
            if let delegate = delegate {
                Task { @MainActor in
                    delegate.didCancelSelection()
                }
            }
            // Don't call super - consume the event
            return
        }
        
        super.keyDown(with: event)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        // CRASH PREVENTION: Don't draw if invalid
        guard isValid else {
            super.draw(dirtyRect)
            return
        }
        
        super.draw(dirtyRect)

        let gradient = NSGradient(colors: [
            NSColor.black.withAlphaComponent(0.35),
            NSColor.black.withAlphaComponent(0.25)
        ])
        gradient?.draw(in: dirtyRect, angle: 0)

        // FIX: Draw prominent help text - always visible when no selection is active
        if !isSelecting && confirmedSelection == nil {
            let helpText = NSLocalizedString("ocr.selection.help", comment: "OCR selection help")
            let instructionText = NSLocalizedString("ocr.selection.instructions", comment: "OCR selection instructions")
            
            // Enhanced shadow for better visibility
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 5
            
            // Main help text - larger and more prominent
            let helpAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: NSColor.white,
                .shadow: shadow
            ]
            
            // Instruction text - smaller
            let instructionAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .shadow: shadow
            ]
            
            let helpSize = helpText.size(withAttributes: helpAttributes)
            let instructionSize = instructionText.size(withAttributes: instructionAttributes)
            
            // Center both texts
            let helpPoint = NSPoint(
                x: (dirtyRect.width - helpSize.width) / 2,
                y: dirtyRect.height / 2 + 30
            )
            let instructionPoint = NSPoint(
                x: (dirtyRect.width - instructionSize.width) / 2,
                y: dirtyRect.height / 2 - 10
            )
            
            helpText.draw(at: helpPoint, withAttributes: helpAttributes)
            instructionText.draw(at: instructionPoint, withAttributes: instructionAttributes)
        }

        // Draw selection
        guard let start = startPoint, let current = currentPoint else { return }
        
        // OPTIMIZATION: Convert global coordinates to local window coordinates for drawing
        guard let window = self.window else { return }
        let windowFrame = window.frame
        
        // Convert global points to local window coordinates
        let localStart = NSPoint(
            x: start.x - windowFrame.origin.x,
            y: start.y - windowFrame.origin.y
        )
        let localCurrent = NSPoint(
            x: current.x - windowFrame.origin.x,
            y: current.y - windowFrame.origin.y
        )

        let minX = min(localStart.x, localCurrent.x)
        let minY = min(localStart.y, localCurrent.y)
        let width = abs(localCurrent.x - localStart.x)
        let height = abs(localCurrent.y - localStart.y)

        let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)
        
        // Only draw if selection intersects with this window's frame
        guard selectionRect.intersects(bounds) else { return }

        NSColor.clear.setFill()
        selectionRect.fill(using: .sourceOver)

        let borderPath = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)
        borderPath.lineWidth = 2
        NSColor.systemBlue.setStroke()
        borderPath.stroke()
        
        // Size Label
        let sizeText = "\(Int(width)) × \(Int(height))"
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = sizeText.size(withAttributes: labelAttributes)
        let textRect = NSRect(
             x: selectionRect.maxX - textSize.width - 20,
             y: selectionRect.maxY + 8,
             width: textSize.width + 20,
             height: textSize.height + 10
        )
        
        NSColor.systemBlue.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: textRect, xRadius: 6, yRadius: 6).fill()
        sizeText.draw(at: NSPoint(x: textRect.minX + 10, y: textRect.minY + 5), withAttributes: labelAttributes)
    }

    override var acceptsFirstResponder: Bool { isValid }
    
    deinit {
        // CRASH PREVENTION: Mark as invalid during deallocation
        isValid = false
        delegate = nil
    }
}
#endif
