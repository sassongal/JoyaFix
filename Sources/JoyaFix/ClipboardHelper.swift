import Cocoa
import Carbon

/// Helper class for clipboard operations and key simulations
/// Consolidated from PromptEnhancerManager logic
class ClipboardHelper {
    
    // MARK: - Clipboard Operations
    
    static func readFromClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
    }
    
    static func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
       
    static func getSelectedText() async -> String? {
        // Clear clipboard first to ensure we capture new copy
        let oldClipboard = readFromClipboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Simulate Cmd+C
        simulateCopy()
        
        // Wait asynchronously for system copy (100ms)
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)
        
        if let newText = readFromClipboard(), !newText.isEmpty {
            return newText
        }
        
        // Fallback: Restore old clipboard if copy failed
        if let old = oldClipboard {
            writeToClipboard(old)
        }
        return nil
    }

    static func pasteText(_ text: String) async {
        // Write to clipboard
        writeToClipboard(text)
        
        // Wait asynchronously for system to register clipboard change (50ms)
        try? await Task.sleep(nanoseconds: 50 * 1_000_000)
        
        // Simulate Cmd+V
        simulatePaste()
    }
    
    // MARK: - Key Simulation
    
    static func simulateCopy() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }
    
    static func simulatePaste() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }
    
    static func simulateDelete() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ForwardDelete), flags: [])
    }
    
    private static func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            print("Failed to create key down event")
            return
        }
        keyDownEvent.flags = flags
        
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            print("Failed to create key up event")
            return
        }
        keyUpEvent.flags = flags
        
        let location = CGEventTapLocation.cghidEventTap
        keyDownEvent.post(tap: location)
        // Keep a tiny sleep here as it's low-level input event handling, 
        // but it's very short (10ms) so minimal impact on Main Thread compared to logic waits.
        usleep(10000) 
        keyUpEvent.post(tap: location)
    }
}
