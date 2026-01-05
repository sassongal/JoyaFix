import Cocoa
import Vision
import CoreGraphics
import Foundation

class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()

    private var overlayWindow: SelectionOverlayWindow?
    private var completion: ((String?) -> Void)?
    private var escapeKeyMonitor: Any?

    private init() {}

    // MARK: - Public Interface

    /// Starts the screen capture flow with selection overlay
    func startScreenCapture(completion: @escaping (String?) -> Void) {
        self.completion = completion

        DispatchQueue.main.async {
            self.showSelectionOverlay()
        }
    }

    // MARK: - Overlay Management

    private func showSelectionOverlay() {
        // Create full-screen overlay covering all screens
        let combinedFrame = NSScreen.screens.reduce(NSRect.zero) { result, screen in
            return result.union(screen.frame)
        }

        overlayWindow = SelectionOverlayWindow(
            contentRect: combinedFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlayWindow?.selectionDelegate = self
        overlayWindow?.backgroundColor = NSColor.clear
        overlayWindow?.isOpaque = false
        overlayWindow?.level = .screenSaver
        overlayWindow?.ignoresMouseEvents = false
        overlayWindow?.makeKeyAndOrderFront(nil)
        
        // Make sure window can receive key events
        overlayWindow?.makeFirstResponder(overlayWindow?.contentView)

        // Change cursor to crosshair
        NSCursor.crosshair.push()
        
        // Add global ESC key monitor as backup
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.didCancelSelection()
                return nil // Consume the event
            }
            return event
        }
    }

    private func hideSelectionOverlay() {
        NSCursor.pop()
        
        // Remove ESC key monitor
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
        
        // Animate window fade out
        if let window = overlayWindow {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.allowsImplicitAnimation = true
                window.alphaValue = 0.0
            }, completionHandler: {
                window.close()
            })
        }
        
        overlayWindow = nil
    }

    // MARK: - Screen Capture

    private func captureScreen(rect: NSRect) {
        print("📸 Capturing screen region: \(rect)")

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

        // Check if capture was successful
        guard task.terminationStatus == 0 else {
            print("❌ screencapture command failed")
            completion?(nil)
            return
        }

        // Load the captured image
        guard let image = NSImage(contentsOfFile: tempFile),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to load captured image")
            completion?(nil)

            // Clean up temp file
            try? FileManager.default.removeItem(atPath: tempFile)
            return
        }

        print("✓ Screen captured (\(Int(rect.width))×\(Int(rect.height))), starting OCR...")

        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempFile)

        // Perform OCR (Cloud or local)
        extractText(from: cgImage) { [weak self] text in
            self?.completion?(text)
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
        // Create Vision request
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("❌ OCR Error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            // Extract recognized text
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("❌ No text found")
                completion(nil)
                return
            }

            // Combine all recognized text
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            let fullText = recognizedStrings.joined(separator: "\n")

            if fullText.isEmpty {
                print("📝 No text recognized")
                completion(nil)
            } else {
                print("✓ OCR Success! Recognized \(recognizedStrings.count) lines")
                print("📝 Text: \(fullText.prefix(100))...")
                completion(fullText)
            }
        }

        // Configure for accurate recognition
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // Support English and Hebrew
        request.recognitionLanguages = ["en-US", "he-IL"]

        // Perform request
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

    /// Performs OCR using Google's Gemini 1.5 Flash API
    private func performGeminiOCR(image: CGImage, apiKey: String, completion: @escaping (String?) -> Void) {
        // Convert CGImage to JPEG Data
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            print("❌ Failed to convert image to JPEG")
            completion(nil)
            return
        }

        // Encode image to Base64
        let base64Image = jpegData.base64EncodedString()

        // Create the API request URL with API key as query parameter
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)") else {
            print("❌ Invalid API URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create JSON body according to Gemini API format
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": "Extract text from this image exactly as it appears. Preserve Hebrew perfectly. Output ONLY the raw text."
                        ],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]

        // Convert to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to create JSON request body")
            completion(nil)
            return
        }

        request.httpBody = jsonData

        // Perform the network request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Cloud OCR network error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                completion(nil)
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ Cloud OCR API error: HTTP \(httpResponse.statusCode)")
                if let data = data, let errorMessage = String(data: data, encoding: .utf8) {
                    print("   Error details: \(errorMessage)")
                }
                completion(nil)
                return
            }

            guard let data = data else {
                print("❌ No data received from API")
                completion(nil)
                return
            }

            // Parse JSON response according to Gemini API format
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    print("❌ Invalid JSON response structure")
                    // Print the actual response for debugging
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("   Response: \(jsonString.prefix(500))")
                    }
                    completion(nil)
                    return
                }

                let extractedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if extractedText.isEmpty {
                    print("⚠️ Cloud OCR returned empty text")
                    completion(nil)
                } else {
                    print("✓ Cloud OCR extracted \(extractedText.count) characters")
                    completion(extractedText)
                }
            } catch {
                print("❌ Failed to parse JSON response: \(error.localizedDescription)")
                // Print the actual response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("   Response: \(jsonString.prefix(500))")
                }
                completion(nil)
            }
        }

        task.resume()
    }
}

// MARK: - Selection Delegate

extension ScreenCaptureManager: SelectionOverlayDelegate {
    func didSelectRegion(_ rect: NSRect) {
        hideSelectionOverlay()

        // Small delay to ensure overlay is completely gone
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.captureScreen(rect: rect)
        }
    }

    func didCancelSelection() {
        hideSelectionOverlay()
        completion?(nil)
    }
}

// MARK: - Selection Overlay Window

protocol SelectionOverlayDelegate: AnyObject {
    func didSelectRegion(_ rect: NSRect)
    func didCancelSelection()
}

class SelectionOverlayWindow: NSWindow {
    weak var selectionDelegate: SelectionOverlayDelegate?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        let selectionView = SelectionView(frame: contentRect)
        selectionView.delegate = selectionDelegate
        contentView = selectionView
        
        // Enable key events
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            selectionDelegate?.didCancelSelection()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Selection View

class SelectionView: NSView {
    weak var delegate: SelectionOverlayDelegate?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isSelecting = false

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
        startPoint = event.locationInWindow
        currentPoint = startPoint
        isSelecting = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isSelecting, let start = startPoint, let end = currentPoint else {
            delegate?.didCancelSelection()
            return
        }

        isSelecting = false

        // Calculate selection rectangle
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)

        // Minimum size check
        if width < 10 || height < 10 {
            print("⚠️ Selection too small")
            delegate?.didCancelSelection()
            return
        }

        let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)

        // Convert to screen coordinates
        if let window = window {
            let screenRect = window.convertToScreen(selectionRect)
            delegate?.didSelectRegion(screenRect)
        }
    }

    override func keyDown(with event: NSEvent) {
        // ESC to cancel
        if event.keyCode == 53 { // ESC key
            delegate?.didCancelSelection()
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func flagsChanged(with event: NSEvent) {
        // Allow ESC to work even when modifiers are pressed
        super.flagsChanged(with: event)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Modern dark overlay with gradient effect
        let gradient = NSGradient(colors: [
            NSColor.black.withAlphaComponent(0.35),
            NSColor.black.withAlphaComponent(0.25)
        ])
        gradient?.draw(in: dirtyRect, angle: 0)

        // Draw help text when not selecting
        if !isSelecting {
            let helpText = "גרור כדי לבחור אזור • לחץ ESC לביטול"
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

        // Draw selection rectangle
        guard isSelecting, let start = startPoint, let current = currentPoint else { return }

        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)

        // Clear the selected area with modern look
        NSColor.clear.setFill()
        selectionRect.fill(using: .sourceOver)

        // Modern border with shadow effect
        let borderPath = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)
        
        // Outer glow effect
        let glowColor = NSColor.systemBlue.withAlphaComponent(0.3)
        let glowRect = NSRect(
            x: selectionRect.origin.x - 2,
            y: selectionRect.origin.y - 2,
            width: selectionRect.width + 4,
            height: selectionRect.height + 4
        )
        let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: 6, yRadius: 6)
        glowColor.setStroke()
        glowPath.lineWidth = 4
        glowPath.stroke()
        
        // Main border with gradient-like effect
        let borderGradient = NSGradient(colors: [
            NSColor.systemBlue,
            NSColor.systemBlue.withAlphaComponent(0.8)
        ])
        borderGradient?.draw(in: borderPath, angle: 45)
        
        borderPath.lineWidth = 2.5
        NSColor.systemBlue.setStroke()
        borderPath.stroke()
        
        // Inner highlight
        let innerRect = NSRect(
            x: selectionRect.origin.x + 1,
            y: selectionRect.origin.y + 1,
            width: selectionRect.width - 2,
            height: selectionRect.height - 2
        )
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.3).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()

        // Modern size label with better styling
        let sizeText = "\(Int(width)) × \(Int(height))"
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]

        let textSize = sizeText.size(withAttributes: labelAttributes)
        let padding: CGFloat = 10
        let cornerRadius: CGFloat = 8
        let textRect = NSRect(
            x: selectionRect.maxX - textSize.width - padding * 2,
            y: selectionRect.maxY + 8,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        // Modern label background with blur effect simulation
        let labelPath = NSBezierPath(roundedRect: textRect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Background with gradient
        let labelGradient = NSGradient(colors: [
            NSColor.systemBlue.withAlphaComponent(0.95),
            NSColor.systemBlue.withAlphaComponent(0.85)
        ])
        labelGradient?.draw(in: labelPath, angle: 0)
        
        // Border
        NSColor.white.withAlphaComponent(0.2).setStroke()
        labelPath.lineWidth = 1
        labelPath.stroke()

        // Draw text
        let textPoint = NSPoint(
            x: textRect.minX + padding,
            y: textRect.minY + (textRect.height - textSize.height) / 2
        )
        sizeText.draw(at: textPoint, withAttributes: labelAttributes)
    }

    override var acceptsFirstResponder: Bool { true }
}
