import Cocoa
import ApplicationServices
import Carbon

/// Monitors keyboard input globally and expands snippets
class InputMonitor {
    static let shared = InputMonitor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // FIX: Thread-safe monitoring flag with synchronization
    private let monitoringQueue = DispatchQueue(label: "com.joyafix.inputmonitor", attributes: .concurrent)
    private var _isMonitoring = false
    private var isMonitoring: Bool {
        get {
            return monitoringQueue.sync { _isMonitoring }
        }
        set {
            monitoringQueue.async(flags: .barrier) {
                self._isMonitoring = newValue
            }
        }
    }
    
    private let snippetManager = SnippetManager.shared
    private var keyBuffer: String = ""
    private let maxBufferSize = JoyaFixConstants.maxSnippetBufferSize
    
    private init() {}
    
    // MARK: - Start/Stop Monitoring
    
    func startMonitoring() {
        // FIX: Thread-safe check and set
        let shouldStart = monitoringQueue.sync { () -> Bool in
            guard !_isMonitoring else {
                print("⚠️ InputMonitor already running")
                return false
            }
            _isMonitoring = true
            return true
        }
        
        guard shouldStart else { return }
        
        // Check Accessibility permissions
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            // Reset flag if permission check fails
            monitoringQueue.async(flags: .barrier) {
                self._isMonitoring = false
            }
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
        
        // Flag already set to true above
        print("✓ InputMonitor started - snippet expansion active")
    }
    
    func stopMonitoring() {
        // FIX: Thread-safe check and set
        let shouldStop = monitoringQueue.sync { () -> Bool in
            guard _isMonitoring else { return false }
            _isMonitoring = false
            return true
        }
        
        guard shouldStop else { return }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        
        // Clear buffer safely
        monitoringQueue.async(flags: .barrier) {
            self.keyBuffer = ""
        }
        
        print("✓ InputMonitor stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // FIX: Thread-safe check - return early if not monitoring
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        // Check if monitoring in a thread-safe way
        let currentlyMonitoring = monitoringQueue.sync { _isMonitoring }
        guard currentlyMonitoring else {
            return Unmanaged.passUnretained(event)
        }
        
        // Get key code
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Convert CGEvent to NSEvent to get characters
        if let nsEvent = NSEvent(cgEvent: event) {
            // Get the character(s) typed
            if let characters = nsEvent.characters, !characters.isEmpty {
                // FIX: Thread-safe buffer update
                monitoringQueue.async(flags: .barrier) {
                    self.keyBuffer.append(characters)
                    
                    // Keep buffer size manageable
                    if self.keyBuffer.count > self.maxBufferSize {
                        self.keyBuffer = String(self.keyBuffer.suffix(self.maxBufferSize))
                    }
                }
                
                // Check for snippet matches (synchronously to ensure buffer is up to date)
                monitoringQueue.sync {
                    checkForSnippetMatch()
                }
            } else if keyCode == 49 { // Space key
                handleSpaceKey()
            }
        } else {
            // Fallback: check for space key
            if keyCode == 49 { // Space
                handleSpaceKey()
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    /// Handles space key input (unified logic)
    private func handleSpaceKey() {
        // FIX: Thread-safe buffer update
        monitoringQueue.async(flags: .barrier) {
            self.keyBuffer.append(" ")
            if self.keyBuffer.count > self.maxBufferSize {
                self.keyBuffer = String(self.keyBuffer.suffix(self.maxBufferSize))
            }
        }
        
        monitoringQueue.sync {
            checkForSnippetMatch()
        }
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
            // For other keys, we'll rely on NSEvent conversion in handleEvent
            return nil
        }
    }
    
    private func checkForSnippetMatch() {
        guard _isMonitoring else { return }
        
        // מיין טריגרים מהארוך לקצר כדי למנוע התנגשויות (למשל !mail1 יזוהה לפני !mail)
        let triggers = snippetManager.getAllTriggers().sorted { $0.count > $1.count }
        
        for trigger in triggers {
            if keyBuffer.hasSuffix(trigger) {
                // בדיקת גבול מילה: וודא שהתו שלפני הטריגר הוא רווח/סימן פיסוק (או תחילת השורה)
                let triggerLength = trigger.count
                let bufferLength = keyBuffer.count
                
                var isWholeWord = true
                if bufferLength > triggerLength {
                    let indexBeforeTrigger = keyBuffer.index(keyBuffer.endIndex, offsetBy: -(triggerLength + 1))
                    let charBefore = keyBuffer[indexBeforeTrigger]
                    // אם התו שלפני הוא אות או מספר, זה לא סניפט (למשל hotmail לא יפעיל את mail)
                    if charBefore.isLetter || charBefore.isNumber {
                        isWholeWord = false
                    }
                }
                
                if isWholeWord {
                    expandSnippet(trigger: trigger)
                    return
                }
            }
        }
    }
    
    /// Checks if trigger matches as a whole word with proper word boundary validation
    /// Word Boundary Rule: Trigger must be preceded by a separator OR be at the start of buffer
    /// This prevents false positives like "gmail" triggering "!mail"
    private func isWholeWordMatch(trigger: String, in buffer: String) -> Bool {
        // First check: buffer must end with the trigger
        guard buffer.hasSuffix(trigger) else { return false }
        
        // Edge case: If buffer equals trigger exactly, it's a match (at start of buffer)
        if buffer.count == trigger.count {
            return true
        }
        
        // Calculate the index where the trigger starts in the buffer
        let triggerStartIndex = buffer.index(buffer.endIndex, offsetBy: -trigger.count)
        
        // Word Boundary Check: Character before trigger must be a separator OR trigger must be at start
        if triggerStartIndex == buffer.startIndex {
            // Trigger is at the start of buffer - valid match
            return true
        }
        
        // Get the character immediately before the trigger
        let charBeforeIndex = buffer.index(before: triggerStartIndex)
        let charBefore = buffer[charBeforeIndex]
        
        // Verify it's a word delimiter (separator) - this prevents false positives
        // Example: "gmail" should NOT match "!mail" because 'g' is not a delimiter
        return isWordDelimiter(charBefore)
    }
    
    /// Determines if a character is a word delimiter
    private func isWordDelimiter(_ char: Character) -> Bool {
        return char.isWhitespace || char.isNewline || 
               [".", ",", ";", ":", "!", "?", "-", "_", "(", ")", "[", "]", "{", "}", "/", "\\"].contains(char)
    }
    
    /// Clears buffer when word delimiter is encountered and no snippet matched
    private func clearBufferOnDelimiter() {
        // Keep only the last delimiter in buffer (for potential future matches)
        if let lastChar = keyBuffer.last, isWordDelimiter(lastChar) {
            keyBuffer = String(lastChar)
        } else {
            keyBuffer = ""
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
        
        // Process snippet content (Snippets 2.0: dynamic variables and cursor placement)
        let processed = snippetManager.processSnippetContent(snippet.content)
        let processedText = processed.text
        let cursorPosition = processed.cursorPosition
        
        // Small delay to ensure backspaces are processed
        DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.snippetBackspaceDelay) {
            // Paste the processed snippet content
            self.pasteText(processedText)
            
            // Snippets 2.0: Handle cursor placement if specified
            if let cursorPos = cursorPosition, cursorPos > 0 {
                // Wait a bit for paste to complete, then move cursor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.moveCursorLeft(by: cursorPos)
                }
            }
            
            // Clear buffer
            self.keyBuffer = ""
        }
    }
    
    /// Moves cursor left by specified number of characters
    private func moveCursorLeft(by count: Int) {
        let keyCode = CGKeyCode(kVK_LeftArrow)
        
        for _ in 0..<count {
            guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                  let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
                continue
            }
            
            keyDownEvent.post(tap: CGEventTapLocation.cghidEventTap)
            usleep(5000) // 5ms delay between key presses
            keyUpEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
    
    private func simulateBackspace() {
        let keyCode = CGKeyCode(kVK_Delete)
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        keyDownEvent.post(tap: CGEventTapLocation.cghidEventTap)
        usleep(5000) // 5ms delay
        keyUpEvent.post(tap: CGEventTapLocation.cghidEventTap)
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
        
        keyDownEvent.flags = CGEventFlags.maskCommand
        keyUpEvent.flags = CGEventFlags.maskCommand
        
        keyDownEvent.post(tap: CGEventTapLocation.cghidEventTap)
        usleep(10000) // 10ms delay
        keyUpEvent.post(tap: CGEventTapLocation.cghidEventTap)
    }
}

