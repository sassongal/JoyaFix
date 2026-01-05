import Cocoa
@preconcurrency import Vision
import CoreGraphics
import Foundation

@MainActor
class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()

    private var overlayWindow: SelectionOverlayWindow?
    private var completion: ((String?) -> Void)?
    private var escapeKeyMonitor: Any?
    private var escapeKeyLocalMonitor: Any?
    
    // CRITICAL FIX: Simple flag to prevent concurrent captures
    // MUST be checked FIRST in startScreenCapture
    private var isCapturing = false
    
    // CRASH PREVENTION: Track cursor state to prevent unbalanced push/pop
    private var cursorPushed = false

    private init() {}

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
        
        // FIX: Restore cursor safely - use set() instead of pop() to prevent crashes
        NSCursor.arrow.set() // Force cursor back to arrow (safe)
        cursorPushed = false
        
        // Close window safely - validate it exists before closing
        if let window = overlayWindow {
            window.orderOut(nil)
            window.close()
            overlayWindow = nil
        }
    }

    // MARK: - Overlay Management

    private func showSelectionOverlay() {
        // Cleanup any existing overlay first
        cleanupExistingSession()
        
        // Create full-screen overlay covering all screens
        let combinedFrame = NSScreen.screens.reduce(NSRect.zero) { result, screen in
            return result.union(screen.frame)
        }

        let window = SelectionOverlayWindow(
            contentRect: combinedFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.overlayWindow = window

        window.selectionDelegate = self
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        
        // Make sure window can receive key events
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)

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

    private func hideSelectionOverlay() {
        // Prevent double-cleanup with guard
        guard overlayWindow != nil || escapeKeyMonitor != nil || escapeKeyLocalMonitor != nil || cursorPushed else {
            return
        }

        // Store references before clearing to avoid race conditions
        let window = overlayWindow
        let monitor = escapeKeyMonitor
        let localMonitor = escapeKeyLocalMonitor
        
        // Clear references immediately to prevent re-entry
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
        
        // Close Window safely - validate it exists
        if let window = window {
            window.orderOut(nil)
            window.close()
        }
        
        // CRITICAL FIX: Reset capturing flag ONLY after everything is closed
        isCapturing = false
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
            completion?(nil)
            isCapturing = false
            return
        }

        // Validate rect before capturing
        guard rect.width > 0 && rect.height > 0 && 
              rect.width < 100000 && rect.height < 100000 else {
            print("❌ Invalid capture rect: \(rect)")
            completion?(nil)
            isCapturing = false
            return
        }

        // Get overlay window for hiding during capture
        guard let overlayWindow = self.overlayWindow else {
            print("❌ Overlay window not available")
            completion?(nil)
            isCapturing = false
            return
        }
        
        // Validate rect
        guard rect.origin.x >= 0 && rect.origin.y >= 0 &&
              rect.width > 0 && rect.height > 0 else {
            print("❌ Invalid capture rect: \(rect)")
            completion?(nil)
            isCapturing = false
            return
        }
        
        print("📐 Capturing screen region: \(rect)")
        
        // On macOS 15.0+, CGWindowListCreateImage is unavailable
        // Use screencapture CLI as fallback
        // Hide overlay first, then capture
        overlayWindow.orderOut(nil)
        
        // Small delay to ensure overlay is hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            // Use screencapture CLI for screen capture
            self.captureScreenWithCLI(rect: rect, completion: self.completion)
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

    // MARK: - OCR Processing

    /// Extracts text from an image using Cloud OCR (Gemini) or Vision framework
    private func extractText(from image: CGImage, completion: @escaping (String?) -> Void) {
        let settings = SettingsManager.shared
        
        // Check if Cloud OCR is enabled and API key is available
        if settings.useCloudOCR {
            print("☁️ Using Cloud OCR (Gemini 1.5 Flash)...")
            Task { @MainActor in
                GeminiService.shared.performOCR(image: image) { [weak self] text in
                    if let text = text, !text.isEmpty {
                        print("✓ Cloud OCR Success!")
                        completion(text)
                    } else {
                        print("⚠️ Cloud OCR failed, falling back to local OCR...")
                        // Fallback to local OCR
                        self?.extractTextWithVision(from: image, completion: completion)
                    }
                }
            }
        } else {
            // Use local Vision OCR
            extractTextWithVision(from: image, completion: completion)
        }
    }

    /// Extracts text from an image using Vision framework
    /// Performs both text recognition and barcode/QR code detection in parallel
    /// VNImageRequestHandler is created inside the background queue to avoid Sendable warnings
    private func extractTextWithVision(from image: CGImage, completion: @escaping (String?) -> Void) {
        // Create text recognition request
        let textRequest = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("❌ OCR Error: \(error.localizedDescription)")
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["en-US", "he-IL"]
        
        // Create barcode detection request
        let barcodeRequest = VNDetectBarcodesRequest { request, error in
            if let error = error {
                print("❌ Barcode Detection Error: \(error.localizedDescription)")
            }
        }
        // Configure barcode request to detect all supported symbologies
        barcodeRequest.symbologies = [
            .QR, .Aztec, .Code128, .Code39, .Code93,
            .DataMatrix, .EAN13, .EAN8, .I2of5, .ITF14, .PDF417,
            .UPCE
        ]
        
        // Process both requests in parallel on background thread
        // Vision framework processes multiple requests efficiently in a single pass
        DispatchQueue.global(qos: .userInitiated).async {
            let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
            
            var recognizedText: String?
            var barcodePayload: String?
            var barcodeType: String?
            
            // Perform both requests in a single call (Vision processes them efficiently)
            do {
                try requestHandler.perform([textRequest, barcodeRequest])
                
                // Process text recognition results
                if let observations = textRequest.results as? [VNRecognizedTextObservation] {
                    let recognizedStrings = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }
                    recognizedText = recognizedStrings.joined(separator: "\n")
                    
                    if !recognizedText!.isEmpty {
                        print("✓ OCR Success! Recognized \(recognizedStrings.count) lines")
                    }
                }
                
                // Process barcode detection results
                if let observations = barcodeRequest.results as? [VNBarcodeObservation] {
                    // Get the first detected barcode (prioritize QR codes)
                    let qrCodes = observations.filter { $0.symbology == .QR }
                    let otherBarcodes = observations.filter { $0.symbology != .QR }
                    
                    let priorityBarcode = (qrCodes.first ?? otherBarcodes.first)
                    
                    if let barcode = priorityBarcode, let payload = barcode.payloadStringValue {
                        barcodePayload = payload
                        barcodeType = barcode.symbology == .QR ? "QR" : "Barcode"
                        print("✓ \(barcodeType!) detected: \(payload.prefix(50))...")
                    }
                }
            } catch {
                print("❌ Failed to perform Vision requests: \(error.localizedDescription)")
            }
            
            // Combine results: append barcode to text if found
            var finalResult: String?
            
            // Start with recognized text (if any)
            var result = recognizedText ?? ""
            
            // Append barcode/QR code payload if detected
            if let barcode = barcodePayload {
                let prefix = barcodeType == "QR" ? "[QR]: " : "[Barcode]: "
                if result.isEmpty {
                    result = prefix + barcode
                } else {
                    result += "\n" + prefix + barcode
                }
            }
            
            // Only return result if we have content
            if !result.isEmpty {
                finalResult = result
            }
            
            // Return result on main thread
            DispatchQueue.main.async {
                if finalResult == nil {
                    print("📝 No text or barcode recognized")
                }
                completion(finalResult)
            }
        }
    }

    // MARK: - CLI Screen Capture (Fallback for macOS 15.0+)
    
    /// Captures screen region using screencapture CLI (fallback for macOS 15.0+)
    private func captureScreenWithCLI(rect: NSRect, completion: ((String?) -> Void)?) {
        let tempFile = NSTemporaryDirectory() + "joyafix_capture_\(UUID().uuidString).png"
        
        // Convert rect to screencapture format: x,y,width,height
        let captureRect = "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))"
        
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
        task.waitUntilExit()
        
        defer {
            // Clean up temp file
            try? FileManager.default.removeItem(atPath: tempFile)
        }
        
        guard task.terminationStatus == 0,
              FileManager.default.fileExists(atPath: tempFile),
              let image = NSImage(contentsOfFile: tempFile),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ CLI screen capture failed")
            completion?(nil)
            isCapturing = false
            return
        }
        
        print("✓ Screen captured via CLI (\(Int(rect.width))×\(Int(rect.height))), starting OCR...")
        
        // Store completion handler before any async operations
        let completionHandler = self.completion
        
        // Perform OCR
        self.extractText(from: cgImage) { text in
            Task { @MainActor in
                self.isCapturing = false
                
                // Save to OCR history if text was extracted
                if let extractedText = text, !extractedText.isEmpty {
                    let scan = OCRScan(extractedText: extractedText)
                    let nsImage = NSImage(contentsOfFile: tempFile)
                    var finalScan = scan
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
                }
                
                completionHandler?(text)
            }
        }
    }
    
    // MARK: - Rate Limit Error
    
    /// Shows a user-friendly rate limit error
    private func showRateLimitError(waitTime: TimeInterval) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.rate.limit.title", comment: "Rate limit alert title")
        alert.informativeText = String(format: NSLocalizedString("alert.rate.limit.message", comment: "Rate limit alert message"), JoyaFixConstants.maxCloudOCRRequestsPerMinute, Int(waitTime))
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
        alert.runModal()
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

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isSelecting = false
    private var confirmedSelection: NSRect? // Store confirmed selection for ENTER key
    
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
        
        // Clear any previous confirmed selection when starting new selection
        confirmedSelection = nil
        
        startPoint = event.locationInWindow
        currentPoint = startPoint
        isSelecting = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        // CRASH PREVENTION: Check validity
        guard isValid && isSelecting else { return }
        
        currentPoint = event.locationInWindow
        needsDisplay = true
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

        let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)

        // Convert to global screen coordinates (works with multiple monitors)
        // The window's frame is already in global coordinates covering all screens
        let globalRect = NSRect(
            x: selectionRect.origin.x + self.frame.origin.x,
            y: selectionRect.origin.y + self.frame.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )
        
        print("📐 Selection rect (local): \(selectionRect)")
        print("📐 Selection rect (global): \(globalRect)")
        
        // Store the confirmed selection for ENTER key, but don't process it yet
        // User can press ENTER to confirm, or click again to start new selection
        confirmedSelection = globalRect
        isSelecting = false // Stop selecting, but keep the selection for ENTER
        
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
                 let minX = min(start.x, end.x)
                 let minY = min(start.y, end.y)
                 let width = abs(end.x - start.x)
                 let height = abs(end.y - start.y)
                 
                 if width > 10 && height > 10 {
                     isSelecting = false
                     
                     let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)
                     
                     // Convert to global screen coordinates (works with multiple monitors)
                     let globalRect = NSRect(
                         x: selectionRect.origin.x + self.frame.origin.x,
                         y: selectionRect.origin.y + self.frame.origin.y,
                         width: selectionRect.width,
                         height: selectionRect.height
                     )
                     
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

        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)

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
