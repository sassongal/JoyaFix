import Cocoa
import ApplicationServices

/// Monitors keyboard input globally and expands snippets
class InputMonitor {
    static let shared = InputMonitor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isMonitoring = false
    
    private let snippetManager = SnippetManager.shared
    private var keyBuffer: String = ""
    private let maxBufferSize = 50  // Keep last 50 characters
    
    private init() {}
    
    // MARK: - Start/Stop Monitoring
    
    func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ InputMonitor already running")
            return
        }
        
        // Check Accessibility permissions
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            print("⚠️ Accessibility permission required for snippet expansion")
            return
        }
        
        // Create event tap
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            print("❌ Failed to create event tap for InputMonitor")
            return
        }
        
        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            print("❌ Failed to create run loop source")
            return
        }
        
        // Add to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the event tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        isMonitoring = true
        print("✓ InputMonitor started - snippet expansion active")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
        keyBuffer = ""
        print("✓ InputMonitor stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        // Get Unicode character from the event
        // Create a temporary event to get the character
        if let characters = event.characters, !characters.isEmpty {
            // Add to buffer
            keyBuffer.append(characters)
            
            // Keep buffer size manageable
            if keyBuffer.count > maxBufferSize {
                keyBuffer = String(keyBuffer.suffix(maxBufferSize))
            }
            
            // Check for snippet matches
            checkForSnippetMatch()
        } else {
            // For non-character keys, check if it's a space or other delimiter
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 49 { // Space
                keyBuffer.append(" ")
                if keyBuffer.count > maxBufferSize {
                    keyBuffer = String(keyBuffer.suffix(maxBufferSize))
                }
                checkForSnippetMatch()
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    // Legacy method kept for reference but not used
    private func getCharacter(from keyCode: Int64, flags: CGEventFlags) -> String? {
        // Map key codes to characters
        // This is a simplified version - you might want to use a more comprehensive mapping
        switch keyCode {
        case 0x00: return "a"
        case 0x01: return "s"
        case 0x02: return "d"
        case 0x03: return "f"
        case 0x04: return "h"
        case 0x05: return "g"
        case 0x06: return "z"
        case 0x07: return "x"
        case 0x08: return "c"
        case 0x09: return "v"
        case 0x0B: return "b"
        case 0x0C: return "q"
        case 0x0D: return "w"
        case 0x0E: return "e"
        case 0x0F: return "r"
        case 0x10: return "y"
        case 0x11: return "t"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "o"
        case 0x20: return "u"
        case 0x21: return "["
        case 0x22: return "i"
        case 0x23: return "p"
        case 0x25: return "l"
        case 0x26: return "j"
        case 0x27: return "'"
        case 0x28: return "k"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "n"
        case 0x2E: return "m"
        case 0x2F: return "."
        case 0x32: return "`"
        case 0x41: return "."  // Numpad
        case 0x43: return "*"  // Numpad
        case 0x45: return "+"  // Numpad
        case 0x47: return "⌧"  // Clear
        case 0x4B: return "/"  // Numpad
        case 0x4C: return "↩"  // Enter
        case 0x4E: return "-"  // Numpad
        case 0x51: return "="  // Numpad
        case 0x52: return "0"  // Numpad
        case 0x53: return "1"  // Numpad
        case 0x54: return "2"  // Numpad
        case 0x55: return "3"  // Numpad
        case 0x56: return "4"  // Numpad
        case 0x57: return "5"  // Numpad
        case 0x58: return "6"  // Numpad
        case 0x59: return "7"  // Numpad
        case 0x5B: return "8"  // Numpad
        case 0x5C: return "9"  // Numpad
        case 0x24: return "↩"  // Return
        case 0x30: return "⇥"  // Tab
        case 0x31: return " "  // Space
        case 0x33: return "⌫"  // Delete
        case 0x35: return "⎋"  // Escape
        default:
            // Try to get Unicode character from key code
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) {
                // This is a simplified approach - for production, use a proper key code to character mapping
                return nil
            }
            return nil
        }
    }
    
    private func checkForSnippetMatch() {
        // Check if buffer ends with any snippet trigger
        let triggers = snippetManager.getAllTriggers()
        
        for trigger in triggers {
            if keyBuffer.hasSuffix(trigger) {
                // Found a match!
                expandSnippet(trigger: trigger)
                return
            }
        }
    }
    
    private func expandSnippet(trigger: String) {
        guard let snippet = snippetManager.findSnippet(trigger: trigger) else {
            return
        }
        
        print("🔤 Expanding snippet: \(trigger) → \(snippet.content.prefix(30))...")
        
        // Delete the trigger text (simulate Backspace)
        for _ in 0..<trigger.count {
            simulateBackspace()
        }
        
        // Small delay to ensure backspaces are processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Paste the snippet content
            self.pasteText(snippet.content)
            
            // Clear buffer
            self.keyBuffer = ""
        }
    }
    
    private func simulateBackspace() {
        let keyCode = CGKeyCode(kVK_Delete)
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        keyDownEvent.post(tap: .cghidEventTap)
        usleep(5000) // 5ms delay
        keyUpEvent.post(tap: .cghidEventTap)
    }
    
    private func pasteText(_ text: String) {
        // Write to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        keyDownEvent.flags = .maskCommand
        keyUpEvent.flags = .maskCommand
        
        keyDownEvent.post(tap: .cghidEventTap)
        usleep(10000) // 10ms delay
        keyUpEvent.post(tap: .cghidEventTap)
    }
}

