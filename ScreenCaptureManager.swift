import Cocoa
import Vision
import CoreGraphics
import Foundation

class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()

    private var overlayWindow: SelectionOverlayWindow?
    private var completion: ((String?) -> Void)?
    private var escapeKeyMonitor: Any?
    private var capturedImagePath: String?
    
    // CRASH PREVENTION: Track cursor state to prevent unbalanced push/pop
    private var cursorPushed = false
    
    // CRASH PREVENTION: Serial queue for state management to prevent race conditions
    private let stateQueue = DispatchQueue(label: "com.joyafix.screencapture.state", attributes: .concurrent)
    
    // CRASH PREVENTION: Flag to prevent concurrent sessions
    private var isActive = false

    private init() {}

    // MARK: - Public Interface

    /// Starts the screen capture flow with selection overlay
    func startScreenCapture(completion: @escaping (String?) -> Void) {
        // CRASH PREVENTION: Prevent concurrent sessions
        stateQueue.sync(flags: .barrier) {
            guard !isActive else {
                print("⚠️ Screen capture already active, ignoring new request")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            isActive = true
        }
        
        // CRASH PREVENTION: Cleanup any existing state before starting new capture
        cleanupExistingSession()
        
        self.completion = completion

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.showSelectionOverlay()
        }
    }
    
    // MARK: - Safety Cleanup
    
    private func cleanupExistingSession() {
        // CRASH PREVENTION: Ensure cleanup happens on main thread
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                cleanupExistingSession()
            }
            return
        }
        
        // CRASH PREVENTION: Remove monitor safely
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
        
        // CRASH PREVENTION: Restore cursor if needed
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        
        // CRASH PREVENTION: Close window safely
        if let window = overlayWindow {
            window.orderOut(nil)
            window.close()
            overlayWindow = nil
        }
    }

    // MARK: - Overlay Management

    private func showSelectionOverlay() {
        // CRASH PREVENTION: Ensure we're on main thread
        assert(Thread.isMainThread, "showSelectionOverlay must be called on main thread")
        
        // CRASH PREVENTION: Cleanup any existing overlay first
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
        
        // CRASH PREVENTION: Make sure window can receive key events
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)

        // CRASH PREVENTION: Change cursor to crosshair and track state
        NSCursor.crosshair.push()
        cursorPushed = true
        
        // CRASH PREVENTION: Add global ESC key monitor as backup
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // ESC key
                print("⌨️ ESC pressed (Monitor)")
                DispatchQueue.main.async {
                    self.didCancelSelection()
                }
                return nil // Consume the event
            }
            return event
        }
    }

    private func hideSelectionOverlay() {
        // CRASH PREVENTION: Ensure this runs on Main Thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.hideSelectionOverlay()
            }
            return
        }

        // CRASH PREVENTION: Prevent double-cleanup with guard
        guard overlayWindow != nil || escapeKeyMonitor != nil || cursorPushed else {
            return
        }

        // CRASH PREVENTION: Store references before clearing to avoid race conditions
        let window = overlayWindow
        let monitor = escapeKeyMonitor
        
        // CRASH PREVENTION: Clear references immediately to prevent re-entry
        overlayWindow = nil
        escapeKeyMonitor = nil
        
        // CRASH PREVENTION: Restore Cursor safely
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        
        // CRASH PREVENTION: Remove Monitor safely
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // CRASH PREVENTION: Close Window Immediately (Avoid animation race conditions causing crashes)
        if let window = window {
            window.orderOut(nil)
            window.close()
        }
        
        // CRASH PREVENTION: Mark session as inactive
        stateQueue.async(flags: .barrier) { [weak self] in
            self?.isActive = false
        }
    }

    // MARK: - Screen Capture

    private func captureScreen(rect: NSRect) {
        print("📸 Capturing screen region: \(rect)")

        // CRASH PREVENTION: Validate rect before capturing
        guard rect.width > 0 && rect.height > 0 && 
              rect.width < 100000 && rect.height < 100000 else {
            print("❌ Invalid capture rect: \(rect)")
            DispatchQueue.main.async { [weak self] in
                self?.completion?(nil)
            }
            return
        }

        // Use screencapture command-line tool to capture the region
        let tempFile = NSTemporaryDirectory() + "joyafix_\(UUID().uuidString).png"

        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = [
            "-R", "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.size.width)),\(Int(rect.size.height))",
            "-x", "-t", "png", tempFile
        ]

        task.launch()
        task.waitUntilExit()

        // CRASH PREVENTION: Store completion handler before any async operations
        let completionHandler = completion
        
        // Check if capture was successful
        guard task.terminationStatus == 0 else {
            print("❌ screencapture command failed")
            try? FileManager.default.removeItem(atPath: tempFile)
            DispatchQueue.main.async {
                completionHandler?(nil)
            }
            return
        }

        // Load the captured image
        guard let image = NSImage(contentsOfFile: tempFile),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to load captured image")
            try? FileManager.default.removeItem(atPath: tempFile)
            DispatchQueue.main.async {
                completionHandler?(nil)
            }
            return
        }

        print("✓ Screen captured (\(Int(rect.width))×\(Int(rect.height))), starting OCR...")

        // Store image path for potential preview
        capturedImagePath = tempFile

        // Perform OCR (Cloud or local)
        extractText(from: cgImage) { [weak self] text in
            // CRASH PREVENTION: Clean up temp file
            if let imagePath = self?.capturedImagePath {
                try? FileManager.default.removeItem(atPath: imagePath)
                self?.capturedImagePath = nil
            }
            completionHandler?(text)
        }
    }
    
    // MARK: - Helper Methods
    
    private func showErrorAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "JoyaFix Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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
        // CRASH PREVENTION: Validate API key
        guard !apiKey.isEmpty else {
            print("❌ Empty API key")
            completion(nil)
            return
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            print("❌ Failed to convert image to JPEG")
            completion(nil)
            return
        }

        let base64Image = jpegData.base64EncodedString()

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)") else {
            print("❌ Invalid API URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Cloud OCR network error: \(error.localizedDescription)")
                completion(nil)
                return
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
                    completion(nil)
                    return
                }

                let extractedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(extractedText)
            } catch {
                print("❌ Failed to parse JSON response: \(error.localizedDescription)")
                completion(nil)
            }
        }

        task.resume()
    }
}

// MARK: - Selection Delegate

extension ScreenCaptureManager: SelectionOverlayDelegate {
    func didSelectRegion(_ rect: NSRect) {
        // CRASH PREVENTION: Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // CRASH PREVENTION: Validate rect
            guard rect.width > 0 && rect.height > 0 else {
                print("⚠️ Invalid selection rect")
                self.didCancelSelection()
                return
            }
            
            self.hideSelectionOverlay()
            
            // CRASH PREVENTION: Small delay to ensure overlay is completely gone before capturing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.captureScreen(rect: rect)
            }
        }
    }

    func didCancelSelection() {
        // CRASH PREVENTION: Store completion handler before clearing
        let completionHandler = completion
        completion = nil
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completionHandler?(nil)
                return
            }
            
            self.hideSelectionOverlay()
            
            // CRASH PREVENTION: Call completion after cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completionHandler?(nil)
            }
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
            // CRASH PREVENTION: Call delegate safely
            if let delegate = selectionDelegate {
                DispatchQueue.main.async { [weak delegate] in
                    delegate?.didCancelSelection()
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
            // CRASH PREVENTION: Call delegate safely
            if let delegate = delegate {
                DispatchQueue.main.async { [weak delegate] in
                    delegate?.didCancelSelection()
                }
            }
            return
        }

        isSelecting = false

        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)

        // CRASH PREVENTION: Prevent very small selections (clicks) from processing/crashing
        if width < 10 || height < 10 {
            print("⚠️ Selection too small - treating as cancel")
            if let delegate = delegate {
                DispatchQueue.main.async { [weak delegate] in
                    delegate?.didCancelSelection()
                }
            }
            return
        }

        let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)

        // CRASH PREVENTION: Safely convert to screen coordinates
        if let window = window, isValid {
            let screenRect = window.convertToScreen(selectionRect)
            // CRASH PREVENTION: Call delegate safely on main thread
            if let delegate = delegate {
                DispatchQueue.main.async { [weak delegate] in
                    delegate?.didSelectRegion(screenRect)
                }
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        // CRASH PREVENTION: Check validity
        guard isValid else { return }
        
        // ENTER key (36) to confirm selection if one exists
        if event.keyCode == 36 {
            if let start = startPoint, let end = currentPoint {
                 let minX = min(start.x, end.x)
                 let minY = min(start.y, end.y)
                 let width = abs(end.x - start.x)
                 let height = abs(end.y - start.y)
                 
                 if width > 10 && height > 10, let window = window {
                     let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)
                     let screenRect = window.convertToScreen(selectionRect)
                     // CRASH PREVENTION: Call delegate safely
                     if let delegate = delegate {
                         DispatchQueue.main.async { [weak delegate] in
                             delegate?.didSelectRegion(screenRect)
                         }
                     }
                     return
                 }
            }
        }
        
        // ESC to cancel
        if event.keyCode == 53 {
            // CRASH PREVENTION: Call delegate safely
            if let delegate = delegate {
                DispatchQueue.main.async { [weak delegate] in
                    delegate?.didCancelSelection()
                }
            }
        } else {
            super.keyDown(with: event)
        }
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

        // Draw help text
        if !isSelecting {
            let helpText = "גרור לסריקה • Enter לאישור • ESC לביטול"
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 3
            
            let helpAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.7),
                .shadow: shadow
            ]
            
            let helpSize = helpText.size(withAttributes: helpAttributes)
            let helpPoint = NSPoint(
                x: (dirtyRect.width - helpSize.width) / 2,
                y: dirtyRect.height - 100
            )
            helpText.draw(at: helpPoint, withAttributes: helpAttributes)
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
