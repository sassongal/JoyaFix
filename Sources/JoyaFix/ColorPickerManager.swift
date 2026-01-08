import Foundation
import AppKit

/// Manages color picking from screen
@MainActor
class ColorPickerManager {
    static let shared = ColorPickerManager()
    
    private init() {}
    
    /// Opens color picker and copies HEX code to clipboard
    func pickColor() {
        let colorSampler = NSColorSampler()
        colorSampler.show { [weak self] selectedColor in
            guard let color = selectedColor else {
                // User cancelled
                return
            }
            
            Task { @MainActor in
                self?.handleColorSelection(color)
            }
        }
    }
    
    private func handleColorSelection(_ color: NSColor) {
        // Convert to RGB
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else {
            Logger.error("Failed to convert color to RGB")
            return
        }
        
        // Convert to HEX
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        
        let hexString = String(format: "#%02X%02X%02X", r, g, b)
        
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hexString, forType: .string)
        
        Logger.info("🎨 Color picked: \(hexString)")
        
        // Play success sound
        SoundManager.shared.playSuccess()
    }
}

