import Foundation
import AppKit
import SwiftUI
import CoreGraphics

/// Manages color picking from screen with live preview and HEX code display
@MainActor
class ColorPickerManager: ObservableObject {
    static let shared = ColorPickerManager()
    
    @Published var currentColor: NSColor? = nil
    @Published var currentHexCode: String = ""
    @Published var isPicking = false
    
    private var colorSampler: NSColorSampler?
    private var colorPickerWindow: NSWindow?
    private var mouseMonitor: Any?
    private var clickMonitor: Any?
    
    private init() {}
    
    /// Opens color picker with live preview and HEX code display
    func pickColor() {
        isPicking = true
        currentColor = nil
        currentHexCode = ""
        
        // Start color sampling (this will show the system color picker)
        // Note: NSColorSampler already shows color preview during hover
        let colorSampler = NSColorSampler()
        self.colorSampler = colorSampler
        
        colorSampler.show { [weak self] selectedColor in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let color = selectedColor {
                    self.handleColorSelection(color)
                } else {
                    // User cancelled
                    self.isPicking = false
                }
            }
        }
    }
    
    /// Updates the current color being hovered (called during color picking)
    func updateHoveredColor(_ color: NSColor) {
        guard isPicking else { return }
        
        // Convert to RGB
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else { return }
        
        currentColor = rgbColor
        currentHexCode = colorToHex(rgbColor)
    }
    
    /// Handles final color selection
    private func handleColorSelection(_ color: NSColor) {
        // Ensure we're on main thread
        Task { @MainActor in
            // Convert to RGB
            guard let rgbColor = color.usingColorSpace(.deviceRGB) else {
                Logger.error("Failed to convert color to RGB")
                isPicking = false
                return
            }
            
            // Convert to HEX
            let hexString = colorToHex(rgbColor)
            currentColor = rgbColor
            currentHexCode = hexString
            
            // Copy to clipboard automatically first
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(hexString, forType: .string)
            
            Logger.info("🎨 Color picked: \(hexString) (copied to clipboard)")
            
            // Show color preview window with HEX code (after clipboard copy)
            showColorPreviewWindow(color: rgbColor, hexCode: hexString)
            
            // Play success sound
            SoundManager.shared.playSuccess()
        }
    }
    
    /// Shows a preview window with the selected color and HEX code
    private func showColorPreviewWindow(color: NSColor, hexCode: String) {
        // Ensure we're on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Close existing window if any
            self.colorPickerWindow?.close()
            
            // Create preview window
            let previewView = ColorPreviewView(color: color, hexCode: hexCode, onCopy: {
                // Already copied, just show confirmation
                SoundManager.shared.playSuccess()
            })
            let hostingController = NSHostingController(rootView: previewView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 160),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            window.title = "Color Picked"
            window.contentViewController = hostingController
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.canJoinAllSpaces]
            
            // Position window near cursor
            let mouseLocation = NSEvent.mouseLocation
            let screenFrame = NSScreen.main?.frame ?? NSRect.zero
            let windowX = mouseLocation.x - 130
            let windowY = screenFrame.height - mouseLocation.y - 80
            window.setFrameOrigin(NSPoint(x: windowX, y: windowY))
            
            window.orderFrontRegardless()
            self.colorPickerWindow = window
            
            // Auto-close after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.isPicking = false
                self.colorPickerWindow?.close()
                self.colorPickerWindow = nil
            }
        }
    }
    
    /// Converts NSColor to HEX string
    private func colorToHex(_ color: NSColor) -> String {
        let r = Int(color.redComponent * 255)
        let g = Int(color.greenComponent * 255)
        let b = Int(color.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Color Preview View

struct ColorPreviewView: View {
    let color: NSColor
    let hexCode: String
    let onCopy: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Color preview
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: color))
                .frame(width: 100, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 2)
                )
            
            // HEX code display
            HStack(spacing: 8) {
                Text(hexCode)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                
                Button(action: {
                    // Copy to clipboard again
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(hexCode, forType: .string)
                    onCopy()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Copy again")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            Text("Copied to clipboard")
                .font(.system(size: 10))
                .foregroundColor(.green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
    }
}

