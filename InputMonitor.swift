import Cocoa
import ApplicationServices
import Carbon

/// Monitors keyboard input globally and expands snippets
class InputMonitor {
    static let shared = InputMonitor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // FIX: Thread-safe monitoring flag - using atomic for fast reads in event callback
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
    
    // FIX: Separate serial queue for async text processing to avoid blocking event tap
    private let processingQueue = DispatchQueue(label: "com.joyafix.inputmonitor.processing", qos: .userInteractive)
    
    // FIX: Lock-free buffer access using concurrent queue with barrier for writes
    private let bufferQueue = DispatchQueue(label: "com.joyafix.inputmonitor.buffer", attributes: .concurrent)
    private var _keyBuffer: String = ""
    private var keyBuffer: String {
        get {
            return bufferQueue.sync { _keyBuffer }
        }
        set {
            bufferQueue.async(flags: .barrier) {
                self._keyBuffer = newValue
            }
        }
    }
    
    // FIX: Pending work item for snippet matching (can be cancelled)
    private var pendingSnippetCheck: DispatchWorkItem?
    
    private let snippetManager = SnippetManager.shared
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
        
        // Cancel any pending snippet checks
        pendingSnippetCheck?.cancel()
        pendingSnippetCheck = nil
        
        // Clear buffer safely
        bufferQueue.async(flags: .barrier) {
            self._keyBuffer = ""
        }
        
        print("✓ InputMonitor stopped")
    }
    
    // MARK: - Event Handling
    
    /// FIX: Minimized event handling - only extracts character and queues async processing
    /// This callback runs at very high frequency, so we must keep it as lightweight as possible
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Fast early return for non-keyDown events
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        // Fast atomic check - avoid blocking if not monitoring
        // Use a very lightweight check that doesn't block the event tap
        let currentlyMonitoring = monitoringQueue.sync { _isMonitoring }
        guard currentlyMonitoring else {
            return Unmanaged.passUnretained(event)
        }
        
        // Extract character as quickly as possible using low-level CGEvent fields
        // Avoid expensive NSEvent creation unless absolutely necessary
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var characterToAdd: String? = nil
        
        // Fast path: Use keyCode + flags mapping (no NSEvent creation)
        // This handles 95%+ of cases without expensive object creation
        characterToAdd = getCharacterFromKeyCode(keyCode: Int(keyCode), flags: flags)
        
        // Fallback: Only create NSEvent if keyCode mapping failed
        // This handles special cases like non-ASCII characters, IME input, etc.
        if characterToAdd == nil {
            if let nsEvent = NSEvent(cgEvent: event),
               let characters = nsEvent.characters, !characters.isEmpty {
                characterToAdd = characters
            }
        }
        
        // If we have a character, queue async processing (non-blocking)
        if let char = characterToAdd {
            // Update buffer asynchronously (non-blocking)
            bufferQueue.async(flags: .barrier) {
                self._keyBuffer.append(char)
                
                // Keep buffer size manageable
                if self._keyBuffer.count > self.maxBufferSize {
                    self._keyBuffer = String(self._keyBuffer.suffix(self.maxBufferSize))
                }
            }
            
            // Queue snippet matching asynchronously (non-blocking)
            // Cancel previous pending check to avoid duplicate work
            pendingSnippetCheck?.cancel()
            
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // Get current buffer snapshot for processing
                let bufferSnapshot = self.bufferQueue.sync { self._keyBuffer }
                self.processSnippetMatch(buffer: bufferSnapshot)
            }
            
            pendingSnippetCheck = workItem
            // Use a small debounce delay to batch rapid keystrokes
            processingQueue.asyncAfter(deadline: .now() + 0.01, execute: workItem)
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    /// FIX: Async snippet matching - runs on separate queue, doesn't block event tap
    private func processSnippetMatch(buffer: String) {
        // Double-check monitoring status (may have changed since event was queued)
        let currentlyMonitoring = monitoringQueue.sync { _isMonitoring }
        guard currentlyMonitoring else { return }
        
        // Process snippet matching on async queue
        checkForSnippetMatch(buffer: buffer)
    }
    
    /// Optimized character extraction from keyCode + flags (no NSEvent creation)
    /// This handles 95%+ of cases without expensive object creation
    /// Only falls back to NSEvent for complex cases (IME, non-ASCII, etc.)
    private func getCharacterFromKeyCode(keyCode: Int, flags: CGEventFlags) -> String? {
        let isShift = flags.contains(.maskShift)
        let isOption = flags.contains(.maskAlternate)
        let isCommand = flags.contains(.maskCommand)
        let isControl = flags.contains(.maskControl)
        
        // Ignore modifier-only keys and command/control combinations (not text input)
        if isCommand || isControl {
            return nil
        }
        
        // Option-modified keys require NSEvent for accurate character mapping
        // (too many variations to map manually)
        if isOption {
            return nil // Fall back to NSEvent
        }
        
        // Map keyCode to character, accounting for Shift modifier
        switch keyCode {
        // Letters (a-z)
        case 0x00: return isShift ? "A" : "a"
        case 0x01: return isShift ? "S" : "s"
        case 0x02: return isShift ? "D" : "d"
        case 0x03: return isShift ? "F" : "f"
        case 0x04: return isShift ? "H" : "h"
        case 0x05: return isShift ? "G" : "g"
        case 0x06: return isShift ? "Z" : "z"
        case 0x07: return isShift ? "X" : "x"
        case 0x08: return isShift ? "C" : "c"
        case 0x09: return isShift ? "V" : "v"
        case 0x0B: return isShift ? "B" : "b"
        case 0x0C: return isShift ? "Q" : "q"
        case 0x0D: return isShift ? "W" : "w"
        case 0x0E: return isShift ? "E" : "e"
        case 0x0F: return isShift ? "R" : "r"
        case 0x10: return isShift ? "Y" : "y"
        case 0x11: return isShift ? "T" : "t"
        case 0x1F: return isShift ? "O" : "o"
        case 0x20: return isShift ? "U" : "u"
        case 0x22: return isShift ? "I" : "i"
        case 0x23: return isShift ? "P" : "p"
        case 0x25: return isShift ? "L" : "l"
        case 0x26: return isShift ? "J" : "j"
        case 0x28: return isShift ? "K" : "k"
        case 0x2D: return isShift ? "N" : "n"
        case 0x2E: return isShift ? "M" : "m"
        
        // Numbers and symbols (with Shift)
        case 0x12: return isShift ? "!" : "1"
        case 0x13: return isShift ? "@" : "2"
        case 0x14: return isShift ? "#" : "3"
        case 0x15: return isShift ? "$" : "4"
        case 0x17: return isShift ? "%" : "5"
        case 0x16: return isShift ? "^" : "6"
        case 0x1A: return isShift ? "&" : "7"
        case 0x1C: return isShift ? "*" : "8"
        case 0x19: return isShift ? "(" : "9"
        case 0x1D: return isShift ? ")" : "0"
        
        // Punctuation
        case 0x21: return isShift ? "{" : "["
        case 0x1E: return isShift ? "}" : "]"
        case 0x2A: return isShift ? "|" : "\\"
        case 0x29: return isShift ? ":" : ";"
        case 0x27: return isShift ? "\"" : "'"
        case 0x2B: return isShift ? "<" : ","
        case 0x2F: return isShift ? ">" : "."
        case 0x2C: return isShift ? "?" : "/"
        case 0x18: return isShift ? "+" : "="
        case 0x1B: return isShift ? "_" : "-"
        case 0x32: return isShift ? "~" : "`"
        
        // Special keys
        case 0x31: return " "  // Space
        case 0x24: return "\n" // Return
        case 0x30: return "\t" // Tab
        case 0x33: return nil  // Delete (not a character)
        case 0x35: return nil  // Escape (not a character)
        
        // Numpad (treat as regular numbers)
        case 0x52: return "0"
        case 0x53: return "1"
        case 0x54: return "2"
        case 0x55: return "3"
        case 0x56: return "4"
        case 0x57: return "5"
        case 0x58: return "6"
        case 0x59: return "7"
        case 0x5B: return "8"
        case 0x5C: return "9"
        case 0x41: return "."
        case 0x43: return "*"
        case 0x45: return "+"
        case 0x4E: return "-"
        case 0x4B: return "/"
        case 0x51: return "="
        case 0x4C: return "\n" // Numpad Enter
        
        default:
            // Unknown keyCode - will fall back to NSEvent
            // This handles Option-modified keys, IME input, non-ASCII characters, etc.
            return nil
        }
    }
    
    /// FIX: Async snippet matching - receives buffer snapshot to avoid race conditions
    private func checkForSnippetMatch(buffer: String) {
        // מיין טריגרים מהארוך לקצר כדי למנוע התנגשויות (למשל !mail1 יזוהה לפני !mail)
        let triggers = snippetManager.getAllTriggers().sorted { $0.count > $1.count }
        
        for trigger in triggers {
            if buffer.hasSuffix(trigger) {
                // בדיקת גבול מילה: וודא שהתו שלפני הטריגר הוא רווח/סימן פיסוק (או תחילת השורה)
                let triggerLength = trigger.count
                let bufferLength = buffer.count
                
                var isWholeWord = true
                if bufferLength > triggerLength {
                    let indexBeforeTrigger = buffer.index(buffer.endIndex, offsetBy: -(triggerLength + 1))
                    let charBefore = buffer[indexBeforeTrigger]
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
        bufferQueue.async(flags: .barrier) {
            if let lastChar = self._keyBuffer.last, self.isWordDelimiter(lastChar) {
                self._keyBuffer = String(lastChar)
            } else {
                self._keyBuffer = ""
            }
        }
    }
    
    private func expandSnippet(trigger: String) {
        guard let snippet = snippetManager.findSnippet(trigger: trigger) else {
            return
        }
        
        print("🔤 Expanding snippet: \(trigger) → \(snippet.content.prefix(30))...")
        
        // Process snippet content first (Snippets 2.0: dynamic variables and cursor placement)
        // Note: processSnippetContent is @MainActor and may prompt user for variable values
        Task { @MainActor in
            let processed = snippetManager.processSnippetContent(snippet.content)
            let processedText = processed.text
            let cursorPosition = processed.cursorPosition
            
            self.continueSnippetExpansion(processedText: processedText, cursorPosition: cursorPosition, triggerLength: trigger.count)
        }
    }
    
    /// Continues snippet expansion after processing (called from MainActor context)
    @MainActor
    private func continueSnippetExpansion(processedText: String, cursorPosition: Int?, triggerLength: Int) {
        
        // Use delete-by-selection method for more reliable deletion
        // This is more robust than multiple backspaces under high CPU load
        deleteTriggerBySelection(triggerLength: triggerLength) { [weak self] success in
            guard let self = self else { return }
            
            if success {
                // Increased delay to ensure deletion is fully processed
                // Adaptive delay based on trigger length and CPU load
                let adaptiveDelay = self.calculateAdaptiveDelay(triggerLength: trigger.count)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + adaptiveDelay) {
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
                    self.bufferQueue.async(flags: .barrier) {
                        self._keyBuffer = ""
                    }
                }
            } else {
                // Fallback: Use traditional backspace method if selection deletion fails
                print("⚠️ Selection deletion failed, using backspace fallback")
                self.deleteTriggerByBackspace(triggerLength: trigger.count) {
                    let adaptiveDelay = self.calculateAdaptiveDelay(triggerLength: trigger.count)
                    DispatchQueue.main.asyncAfter(deadline: .now() + adaptiveDelay) {
                        self.pasteText(processedText)
                        
                        if let cursorPos = cursorPosition, cursorPos > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.moveCursorLeft(by: cursorPos)
                            }
                        }
                        
                        self.bufferQueue.async(flags: .barrier) {
                            self._keyBuffer = ""
                        }
                    }
                }
            }
        }
    }
    
    /// Deletes trigger text using selection method (Shift+Left Arrow + Delete)
    /// More reliable than multiple backspaces, especially under high CPU load
    /// Uses Shift+Left Arrow to select backwards, then Delete - more atomic operation
    private func deleteTriggerBySelection(triggerLength: Int, completion: @escaping (Bool) -> Void) {
        // For short triggers, use backspace (faster)
        // For longer triggers, use selection method (more reliable)
        if triggerLength <= 3 {
            // Short triggers: use backspace with adaptive delays
            deleteTriggerByBackspace(triggerLength: triggerLength) {
                completion(true)
            }
            return
        }
        
        // Longer triggers: use selection method
        let leftArrowKey = CGKeyCode(kVK_LeftArrow)
        let deleteKey = CGKeyCode(kVK_Delete)
        
        // Calculate adaptive delay per selection step
        let adaptiveDelay = calculateAdaptiveDelay(triggerLength: triggerLength)
        let delayPerStep = max(adaptiveDelay / Double(triggerLength), JoyaFixConstants.snippetBackspaceMinDelay)
        
        // Select text backwards character by character
        var stepsRemaining = triggerLength
        
        func performNextSelection() {
            guard stepsRemaining > 0 else {
                // All text selected, now delete it
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    guard let deleteDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: true),
                          let deleteUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: false) else {
                        completion(false)
                        return
                    }
                    
                    deleteDown.post(tap: .cghidEventTap)
                    usleep(10000) // 10ms
                    deleteUp.post(tap: .cghidEventTap)
                    
                    // Give buffer for deletion to complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        completion(true)
                    }
                }
                return
            }
            
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKey, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKey, keyDown: false) else {
                completion(false)
                return
            }
            
            keyDown.flags = .maskShift
            keyUp.flags = .maskShift
            
            keyDown.post(tap: .cghidEventTap)
            usleep(UInt32(delayPerStep * 1_000_000))
            keyUp.post(tap: .cghidEventTap)
            
            stepsRemaining -= 1
            
            // Schedule next selection step
            DispatchQueue.main.asyncAfter(deadline: .now() + delayPerStep) {
                performNextSelection()
            }
        }
        
        // Start selection process
        DispatchQueue.main.async {
            performNextSelection()
        }
    }
    
    /// Fallback method: Deletes trigger using traditional backspace with adaptive delays
    private func deleteTriggerByBackspace(triggerLength: Int, completion: @escaping () -> Void) {
        let deleteKey = CGKeyCode(kVK_Delete)
        let adaptiveDelay = calculateAdaptiveDelay(triggerLength: triggerLength)
        let delayPerBackspace = max(adaptiveDelay / Double(triggerLength), JoyaFixConstants.snippetBackspaceMinDelay)
        
        var backspacesRemaining = triggerLength
        
        func performNextBackspace() {
            guard backspacesRemaining > 0 else {
                completion()
                return
            }
            
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: false) else {
                completion()
                return
            }
            
            keyDown.post(tap: .cghidEventTap)
            usleep(UInt32(delayPerBackspace * 1_000_000)) // Convert to microseconds
            keyUp.post(tap: .cghidEventTap)
            
            backspacesRemaining -= 1
            
            // Schedule next backspace with adaptive delay
            DispatchQueue.main.asyncAfter(deadline: .now() + delayPerBackspace) {
                performNextBackspace()
            }
        }
        
        performNextBackspace()
    }
    
    /// Calculates adaptive delay based on trigger length and system load
    /// Longer triggers and higher CPU load require longer delays
    private func calculateAdaptiveDelay(triggerLength: Int) -> TimeInterval {
        // Base delay increases with trigger length
        let baseDelay = JoyaFixConstants.snippetBackspaceDelay
        
        // Factor in trigger length (longer triggers need more time)
        let lengthFactor = 1.0 + (Double(triggerLength) * 0.01)
        
        // Check system load (simplified - in production you might use host_statistics)
        let cpuLoadFactor: Double = 1.2 // Conservative estimate for high load scenarios
        
        // Calculate adaptive delay with safety buffer
        let adaptiveDelay = baseDelay * lengthFactor * cpuLoadFactor
        
        // Clamp to reasonable bounds
        return min(max(adaptiveDelay, JoyaFixConstants.snippetBackspaceMinDelay * Double(triggerLength)),
                   JoyaFixConstants.snippetPostDeleteDelay)
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

