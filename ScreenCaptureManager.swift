import Cocoa
import Vision
import CoreGraphics
import Foundation

@MainActor
class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()

    private var overlayWindow: SelectionOverlayWindow?
    private var completion: ((String?) -> Void)?
    private var escapeKeyMonitor: Any?
    private var escapeKeyLocalMonitor: Any?  // FIX: Store local monitor for cleanup
    
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

    // MARK: - Screen Capture

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

        // FIX: Hide overlay window immediately and wait a moment for it to fully disappear
        // This prevents screencapture from capturing the overlay window itself
        self.overlayWindow?.alphaValue = 0.0
        self.overlayWindow?.orderOut(nil)
        
        // Small delay to ensure overlay is completely gone before capturing
        // This is critical for screencapture CLI to work correctly
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
            
            // Convert to screen coordinates for screencapture
            // screencapture uses coordinates relative to the primary screen's origin
            let primaryScreen = NSScreen.main ?? NSScreen.screens.first!
            let primaryFrame = primaryScreen.frame
            
            // For multi-monitor setups, screencapture expects coordinates relative to the primary screen
            // But our rect is already in global coordinates, so we use it directly
            // Convert Y coordinate: Cocoa (0,0 at bottom-left) to screencapture (0,0 at top-left)
            let captureRect = NSRect(
                x: rect.origin.x,
                y: primaryFrame.height - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            
            // Validate converted rect (screencapture can fail with negative or invalid coordinates)
            guard captureRect.origin.x >= 0 && captureRect.origin.y >= 0 &&
                  captureRect.width > 0 && captureRect.height > 0 else {
                print("❌ Invalid capture rect after conversion: \(captureRect)")
                print("   Original rect: \(rect)")
                print("   Primary screen frame: \(primaryFrame)")
                self.completion?(nil)
                self.isCapturing = false
                return
            }
            
            print("📐 Converted rect for screencapture: \(captureRect)")
            
            // Use screencapture command-line tool to capture the region
            let tempFile = NSTemporaryDirectory() + "joyafix_\(UUID().uuidString).png"
            
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = [
                "-R", "\(Int(captureRect.origin.x)),\(Int(captureRect.origin.y)),\(Int(captureRect.size.width)),\(Int(captureRect.size.height))",
                "-x", // No sound
                "-t", "png",
                tempFile
            ]
            
            // Suppress output
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            
            task.launch()
            task.waitUntilExit()
            
            // Store completion handler before any async operations
            let completionHandler = self.completion
            
            // Check if capture was successful
            guard task.terminationStatus == 0 else {
                print("❌ screencapture command failed with status: \(task.terminationStatus)")
                try? FileManager.default.removeItem(atPath: tempFile)
                completionHandler?(nil)
                self.isCapturing = false
                return
            }
            
            // Verify file was created and has content
            guard FileManager.default.fileExists(atPath: tempFile) else {
                print("❌ screencapture file not created")
                completionHandler?(nil)
                self.isCapturing = false
                return
            }
            
            // Load the captured image
            guard let image = NSImage(contentsOfFile: tempFile),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("❌ Failed to load captured image")
                try? FileManager.default.removeItem(atPath: tempFile)
                completionHandler?(nil)
                self.isCapturing = false
                return
            }
            
            print("✓ Screen captured via screencapture CLI (\(Int(rect.width))×\(Int(rect.height))), starting OCR...")
            
            // Clean up temp file after OCR
            let tempFilePath = tempFile
            
            // Perform OCR directly with the CGImage
            self.extractText(from: cgImage) { text in
                // Clean up temp file
                try? FileManager.default.removeItem(atPath: tempFilePath)
                
                Task { @MainActor in
                    self.isCapturing = false
                    
                    // Save to OCR history if text was extracted
                    if let extractedText = text, !extractedText.isEmpty {
                        // Create scan first
                        let scan = OCRScan(extractedText: extractedText)
                        
                        // Save preview image
                        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                        var finalScan = scan
                        if let previewPath = OCRHistoryManager.shared.savePreviewImage(nsImage, for: scan) {
                            finalScan = scan.withPreviewImagePath(previewPath)
                        }
                        
                        // Add to history
                        OCRHistoryManager.shared.addScan(finalScan)
                        
                        print("📸 OCR scan saved to history: \(extractedText.prefix(50))...")
                    }
                    
                    completionHandler?(text)
                }
            }
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

    /// Extracts text from an image using Cloud OCR (OpenAI) or Vision framework
    private func extractText(from image: CGImage, completion: @escaping (String?) -> Void) {
        let settings = SettingsManager.shared
        
        // Check if Cloud OCR is enabled and API key is available
        if settings.useCloudOCR && !settings.geminiKey.isEmpty {
            print("☁️ Using Cloud OCR (Gemini 1.5 Flash)...")
            performGeminiOCR(image: image, apiKey: settings.geminiKey) { [weak self] text in
                if let text = text, !text.isEmpty {
                    print("✓ Cloud OCR Success!")
                    completion(text)
                } else {
                    print("⚠️ Cloud OCR failed, falling back to local OCR...")
                    // Fallback to local OCR
                    self?.extractTextWithVision(from: image, completion: completion)
                }
            }
        } else {
            // Use local Vision OCR
            extractTextWithVision(from: image, completion: completion)
        }
    }

    /// Extracts text from an image using Vision framework
    private func extractTextWithVision(from image: CGImage, completion: @escaping (String?) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("❌ OCR Error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }

            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            let fullText = recognizedStrings.joined(separator: "\n")

            if fullText.isEmpty {
                print("📝 No text recognized")
                completion(nil)
            } else {
                print("✓ OCR Success! Recognized \(recognizedStrings.count) lines")
                completion(fullText)
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "he-IL"]

        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                print("❌ Failed to perform OCR: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    // MARK: - Cloud OCR

    private func performGeminiOCR(image: CGImage, apiKey: String, completion: @escaping (String?) -> Void) {
        // FIX: Rate limiting check
        Task { @MainActor in
            guard OCRRateLimiter.shared.canMakeRequest() else {
                let waitTime = OCRRateLimiter.shared.timeUntilNextRequest()
                print("⚠️ Cloud OCR rate limit reached. Please wait \(Int(waitTime)) seconds.")
                print("   Current requests in window: \(OCRRateLimiter.shared.currentRequestCount)/\(JoyaFixConstants.maxCloudOCRRequestsPerMinute)")
                
                // Show user-friendly error
                DispatchQueue.main.async {
                    self.showRateLimitError(waitTime: waitTime)
                }
                
                completion(nil)
                return
            }
            
            // Record the request
            OCRRateLimiter.shared.recordRequest()
            
            // Perform OCR with retry logic
            self.performGeminiOCRWithRetry(image: image, apiKey: apiKey, attempt: 0, completion: completion)
        }
    }
    
    /// Performs Gemini OCR with exponential backoff retry logic
    private func performGeminiOCRWithRetry(image: CGImage, apiKey: String, attempt: Int, completion: @escaping (String?) -> Void) {
        // Validate API key
        guard !apiKey.isEmpty else {
            print("❌ Empty API key")
            completion(nil)
            return
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: JoyaFixConstants.cloudOCRCompressionFactor]) else {
            print("❌ Failed to convert image to JPEG")
            completion(nil)
            return
        }

        let base64Image = jpegData.base64EncodedString()

        guard let url = URL(string: "\(JoyaFixConstants.API.geminiBaseURL)?key=\(apiKey)") else {
            print("❌ Invalid API URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0 // 30 second timeout

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [ "text": "Extract text from this image exactly as it appears. Preserve Hebrew perfectly. Output ONLY the raw text." ],
                        [ "inline_data": [ "mime_type": "image/jpeg", "data": base64Image ] ]
                    ]
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to create JSON request body")
            completion(nil)
            return
        }

        request.httpBody = jsonData

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            // FIX: Enhanced error handling with retry logic
            if let error = error {
                print("❌ Cloud OCR network error (attempt \(attempt + 1)): \(error.localizedDescription)")
                
                // Retry with exponential backoff
                if attempt < JoyaFixConstants.ocrMaxRetryAttempts {
                    let delay = min(
                        JoyaFixConstants.ocrRetryInitialDelay * pow(2.0, Double(attempt)),
                        JoyaFixConstants.ocrRetryMaxDelay
                    )
                    print("🔄 Retrying in \(Int(delay)) seconds...")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self?.performGeminiOCRWithRetry(image: image, apiKey: apiKey, attempt: attempt + 1, completion: completion)
                    }
                } else {
                    print("❌ Max retry attempts reached")
                    completion(nil)
                }
                return
            }
            
            // FIX: Handle HTTP status codes
            if let httpResponse = response as? HTTPURLResponse {
                // Handle rate limit (429)
                if httpResponse.statusCode == 429 {
                    print("⚠️ Cloud OCR rate limit exceeded (HTTP 429)")
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        let waitTime = OCRRateLimiter.shared.timeUntilNextRequest()
                        self.showRateLimitError(waitTime: waitTime)
                    }
                    completion(nil)
                    return
                }
                
                // Handle other errors
                if httpResponse.statusCode != 200 {
                    print("❌ Cloud OCR HTTP error: \(httpResponse.statusCode)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("   Response: \(errorString.prefix(200))")
                    }
                    completion(nil)
                    return
                }
            }
            
            guard let data = data else {
                completion(nil)
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    print("⚠️ Cloud OCR: Invalid response structure")
                    completion(nil)
                    return
                }

                let extractedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if extractedText.isEmpty {
                    print("⚠️ Cloud OCR: Empty text extracted")
                    completion(nil)
                } else {
                    print("✓ Cloud OCR success (attempt \(attempt + 1)): \(extractedText.count) characters")
                    completion(extractedText)
                }
            } catch {
                print("❌ Failed to parse JSON response: \(error.localizedDescription)")
                completion(nil)
            }
        }

        task.resume()
    }
    
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
        
        hideSelectionOverlay()
        
        // FIX: No delay needed - CGWindowListCreateImage captures below the window, so overlay can stay
        // Capture immediately (overlay is already hidden with alphaValue = 0)
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
