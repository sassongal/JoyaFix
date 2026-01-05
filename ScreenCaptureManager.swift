import Cocoa
import Vision
import CoreGraphics

class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()

    private var overlayWindow: SelectionOverlayWindow?
    private var completion: ((String?) -> Void)?

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
        overlayWindow?.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        overlayWindow?.isOpaque = false
        overlayWindow?.level = .screenSaver
        overlayWindow?.ignoresMouseEvents = false
        overlayWindow?.makeKeyAndOrderFront(nil)

        // Change cursor to crosshair
        NSCursor.crosshair.push()
    }

    private func hideSelectionOverlay() {
        NSCursor.pop()
        overlayWindow?.close()
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

        // Perform OCR
        extractText(from: cgImage) { [weak self] text in
            self?.completion?(text)
        }
    }

    // MARK: - OCR Processing

    /// Extracts text from an image using Vision framework
    private func extractText(from image: CGImage, completion: @escaping (String?) -> Void) {
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw semi-transparent overlay
        NSColor.black.withAlphaComponent(0.2).setFill()
        dirtyRect.fill()

        // Draw selection rectangle
        guard isSelecting, let start = startPoint, let current = currentPoint else { return }

        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        let selectionRect = NSRect(x: minX, y: minY, width: width, height: height)

        // Clear the selected area (make it less dark)
        NSColor.clear.setFill()
        selectionRect.fill(using: .sourceOver)

        // Draw border
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 2
        NSColor.systemBlue.setStroke()
        border.stroke()

        // Draw size label
        let sizeText = "\(Int(width)) × \(Int(height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.8)
        ]

        let textSize = sizeText.size(withAttributes: attributes)
        let textRect = NSRect(
            x: selectionRect.maxX - textSize.width - 8,
            y: selectionRect.maxY + 4,
            width: textSize.width + 8,
            height: textSize.height + 4
        )

        NSColor.systemBlue.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()

        sizeText.draw(at: NSPoint(x: textRect.minX + 4, y: textRect.minY + 2), withAttributes: attributes)
    }

    override var acceptsFirstResponder: Bool { true }
}
