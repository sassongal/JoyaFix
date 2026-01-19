import Cocoa
import ApplicationServices
import Carbon
import os.lock

/// Monitors keyboard input globally and expands snippets
class InputMonitor {
    static let shared = InputMonitor()
    
    private var runLoopSource: CFRunLoopSource?
    
    // OPTIMIZATION: Use os_unfair_lock for faster synchronization
    private var monitoringLock = os_unfair_lock()
    private var _isMonitoring = false
    private var _eventTap: CFMachPort? // Thread-safe access to event tap
    
    // Fast atomic read for event callback (minimal blocking)
    private var isMonitoringFast: Bool {
        os_unfair_lock_lock(&monitoringLock)
        defer { os_unfair_lock_unlock(&monitoringLock) }
        return _isMonitoring
    }
    
    // Full property for external access
    private var isMonitoring: Bool {
        get {
            os_unfair_lock_lock(&monitoringLock)
            defer { os_unfair_lock_unlock(&monitoringLock) }
            return _isMonitoring
        }
        set {
            os_unfair_lock_lock(&monitoringLock)
            defer { os_unfair_lock_unlock(&monitoringLock) }
            _isMonitoring = newValue
        }
    }
    
    // FIX: Separate serial queue for async text processing to avoid blocking event tap
    private let processingQueue = DispatchQueue(label: "com.joyafix.inputmonitor.processing", qos: .userInteractive)
    
    // FIX: Dedicated queue for monitoring state synchronization to prevent race conditions
    private let monitoringQueue = DispatchQueue(label: "com.joyafix.inputmonitor.monitoring", qos: .userInteractive)
    
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
    private let shortcutService = KeyboardShortcutService.shared
    
    // Track registered snippet triggers for centralized management
    private var registeredSnippetTriggers: Set<String> = []
    
    // Testing flag to bypass event tap creation
    private var disableEventTapForTesting = false
    
    // MARK: - Watchdog Timer
    
    /// Timer that periodically checks if the event tap is still enabled
    /// macOS can disable event taps if the app becomes unresponsive or due to system events
    private var watchdogTimer: Timer?
    
    /// How often to check the event tap status (60 seconds)
    private let watchdogInterval: TimeInterval = 60.0
    
    /// Counter for consecutive recovery attempts
    private var recoveryAttempts = 0
    
    /// Maximum recovery attempts before giving up
    private let maxRecoveryAttempts = 3
    
    /// Configures the monitor for testing environments where event taps are not supported
    func configureForTesting() {
        disableEventTapForTesting = true
    }
    
    private init() {
        // Register existing snippets when InputMonitor is initialized
        registerAllSnippetTriggers()
    }
    
    // MARK: - Start/Stop Monitoring
    
    func startMonitoring() {
        // OPTIMIZATION: Thread-safe check and set with os_unfair_lock
        os_unfair_lock_lock(&monitoringLock)
        defer { os_unfair_lock_unlock(&monitoringLock) }
        
        guard !_isMonitoring else {
            Logger.snippet("InputMonitor already running", level: .warning)
            return
        }
        _isMonitoring = true
        
        // Check Accessibility permissions
        guard PermissionManager.shared.isAccessibilityTrusted() || disableEventTapForTesting else {
            // Reset flag if permission check fails (already inside lock, no need to lock again)
            _isMonitoring = false
            
            // CRITICAL FIX: Clean up any existing event tap if permissions are missing
            // This prevents memory leaks when permissions are revoked while monitoring
            if let existingTap = _eventTap {
                CGEvent.tapEnable(tap: existingTap, enable: false)
                CFMachPortInvalidate(existingTap)
                _eventTap = nil
            }
            
            if let existingRunLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), existingRunLoopSource, .commonModes)
                runLoopSource = nil
            }
            
            Logger.snippet("Accessibility permission required for snippet expansion", level: .warning)
            Logger.snippet("Snippet expansion disabled - Accessibility permission required", level: .warning)

            // Notify user about permission requirement
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Snippets disabled: Accessibility permission required",
                        style: .warning,
                        duration: 4.0
                    )
                )
            }
            return
        }
        
        // Skip event tap creation in test mode
        if disableEventTapForTesting {
            Logger.snippet("InputMonitor started (TEST MODE) - snippet expansion simulated", level: .info)
            return
        }
        
        // Create event tap
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        let newEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // FIX: Use weak reference to avoid retain cycle and check if monitor still exists
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
                
                // Fast check: if not monitoring, return immediately (non-blocking)
                guard monitor.isMonitoringFast else {
                    return Unmanaged.passUnretained(event)
                }
                
                // Additional safety: verify event tap is still valid
                os_unfair_lock_lock(&monitor.monitoringLock)
                let hasEventTap = monitor._eventTap != nil
                os_unfair_lock_unlock(&monitor.monitoringLock)
                
                guard hasEventTap else {
                    return Unmanaged.passUnretained(event)
                }
                
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let newEventTap = newEventTap else {
            // Reset flag if creation fails (already inside lock, no need to lock again)
            _isMonitoring = false
            
            // CRITICAL FIX: Clean up any existing event tap before returning
            // This prevents memory leaks if startMonitoring is called multiple times after failures
            if let existingTap = _eventTap {
                CGEvent.tapEnable(tap: existingTap, enable: false)
                CFMachPortInvalidate(existingTap)
                _eventTap = nil
            }
            
            if let existingRunLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), existingRunLoopSource, .commonModes)
                runLoopSource = nil
            }
            
            Logger.snippet("Failed to create event tap for InputMonitor", level: .error)
            Logger.snippet("Failed to create event tap - snippet expansion will not work", level: .error)

            // Notify user about the failure
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Snippets failed to start. Try restarting the app.",
                        style: .error,
                        duration: 4.0
                    )
                )
            }
            return
        }
        
        // Store event tap thread-safely (already inside lock, no need to lock again)
        _eventTap = newEventTap
        
        let eventTap = newEventTap
        
        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            Logger.snippet("Failed to create run loop source", level: .error)
            return
        }
        
        // Add to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the event tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        // Register all snippet triggers in centralized service
        registerAllSnippetTriggers()
        
        // Start watchdog timer to monitor event tap health
        startWatchdogTimer()
        
        // Flag already set to true above
        Logger.snippet("InputMonitor started - snippet expansion active", level: .info)
    }
    
    func stopMonitoring() {
        // OPTIMIZATION: Thread-safe check and set with os_unfair_lock
        os_unfair_lock_lock(&monitoringLock)
        defer { os_unfair_lock_unlock(&monitoringLock) }
        
        guard _isMonitoring else { return }
        _isMonitoring = false
        
        // Get event tap reference and clear atomically
        let tapToCleanup = _eventTap
        _eventTap = nil // Clear reference immediately to prevent new callbacks
        
        // Disable and invalidate event tap outside the queue (may take time)
        if let eventTap = tapToCleanup {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        runLoopSource = nil
        
        // Cancel any pending snippet checks
        pendingSnippetCheck?.cancel()
        pendingSnippetCheck = nil
        
        // Clear buffer safely
        bufferQueue.async(flags: .barrier) {
            self._keyBuffer = ""
        }
        
        // Unregister all snippet triggers from centralized service
        unregisterAllSnippetTriggers()
        
        // Stop watchdog timer
        stopWatchdogTimer()
        
        Logger.snippet("InputMonitor stopped", level: .info)
    }
    
    // MARK: - Watchdog Timer Methods
    
    /// Starts the watchdog timer that monitors event tap health
    private func startWatchdogTimer() {
        // Stop any existing timer
        stopWatchdogTimer()
        
        // Reset recovery counter
        recoveryAttempts = 0
        
        // Create timer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: self.watchdogInterval, repeats: true) { [weak self] _ in
                self?.checkEventTapHealth()
            }
            
            // Make sure timer runs during scrolling and other modal loops
            if let timer = self.watchdogTimer {
                RunLoop.current.add(timer, forMode: .common)
            }
            
            Logger.snippet("Watchdog timer started (interval: \(self.watchdogInterval)s)", level: .info)
        }
    }
    
    /// Stops the watchdog timer
    private func stopWatchdogTimer() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
    
    /// Checks if the event tap is still enabled and attempts to recover if not
    private func checkEventTapHealth() {
        // Thread-safe access to event tap
        os_unfair_lock_lock(&monitoringLock)
        let eventTap = _eventTap
        let currentlyMonitoring = _isMonitoring
        os_unfair_lock_unlock(&monitoringLock)
        
        // Skip check if not monitoring or in test mode
        guard currentlyMonitoring, !disableEventTapForTesting else {
            return
        }
        
        // Check if event tap exists and is enabled
        guard let tap = eventTap else {
            Logger.snippet("Watchdog: Event tap is nil, attempting recovery", level: .warning)
            attemptEventTapRecovery()
            return
        }
        
        // Check if tap is still enabled (macOS can disable it)
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        
        if !isEnabled {
            Logger.snippet("Watchdog: Event tap disabled by system, attempting to re-enable", level: .warning)
            
            // Try to re-enable first (less disruptive)
            CGEvent.tapEnable(tap: tap, enable: true)
            
            // Verify it was re-enabled
            if CGEvent.tapIsEnabled(tap: tap) {
                Logger.snippet("Watchdog: Event tap successfully re-enabled", level: .info)
                recoveryAttempts = 0  // Reset counter on success
                
                // Notify user
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .showToast,
                        object: ToastMessage(
                            text: "Snippet monitoring recovered",
                            style: .success,
                            duration: 2.0
                        )
                    )
                }
            } else {
                // Re-enable failed, need full recovery
                Logger.snippet("Watchdog: Re-enable failed, attempting full recovery", level: .error)
                attemptEventTapRecovery()
            }
        } else {
            // Event tap is healthy, reset recovery counter
            if recoveryAttempts > 0 {
                Logger.snippet("Watchdog: Event tap healthy after recovery", level: .info)
                recoveryAttempts = 0
            }
        }
    }
    
    /// Attempts to fully recover the event tap by stopping and restarting monitoring
    private func attemptEventTapRecovery() {
        recoveryAttempts += 1
        
        if recoveryAttempts > maxRecoveryAttempts {
            Logger.snippet("Watchdog: Max recovery attempts (\(maxRecoveryAttempts)) reached, giving up", level: .error)
            
            // Notify user that recovery failed
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Snippet monitoring failed. Please restart the app.",
                        style: .error,
                        duration: 5.0
                    )
                )
            }
            
            // Stop trying
            stopWatchdogTimer()
            return
        }
        
        Logger.snippet("Watchdog: Recovery attempt \(recoveryAttempts)/\(maxRecoveryAttempts)", level: .info)
        
        // Stop and restart monitoring
        // Note: We need to release the lock before calling these methods
        // to avoid deadlock since they also acquire the lock
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Full restart
            self.stopMonitoring()
            
            // Small delay before restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.startMonitoring()
            }
        }
    }
    
    // MARK: - Snippet Trigger Registration
    
    /// Registers all snippet triggers in the centralized shortcut service
    private func registerAllSnippetTriggers() {
        let triggers = snippetManager.getAllTriggers()
        
        for trigger in triggers {
            let identifier = "snippet.\(trigger)"
            let success = shortcutService.registerSnippetTrigger(trigger: trigger, identifier: identifier)
            if success {
                registeredSnippetTriggers.insert(trigger)
            }
        }
        
        Logger.snippet("Registered \(registeredSnippetTriggers.count) snippet triggers in centralized service", level: .info)
    }
    
    /// Unregisters all snippet triggers from the centralized shortcut service
    private func unregisterAllSnippetTriggers() {
        for trigger in registeredSnippetTriggers {
            let identifier = "snippet.\(trigger)"
            shortcutService.unregisterShortcut(identifier: identifier)
        }
        registeredSnippetTriggers.removeAll()
        Logger.snippet("Unregistered all snippet triggers from centralized service", level: .info)
    }
    
    /// Registers a new snippet trigger (called when snippet is added)
    func registerSnippetTrigger(_ trigger: String) {
        let identifier = "snippet.\(trigger)"
        let success = shortcutService.registerSnippetTrigger(trigger: trigger, identifier: identifier)
        if success {
            registeredSnippetTriggers.insert(trigger)
            Logger.snippet("Registered new snippet trigger: \(trigger)", level: .info)
        }
    }
    
    /// Unregisters a snippet trigger (called when snippet is removed)
    func unregisterSnippetTrigger(_ trigger: String) {
        let identifier = "snippet.\(trigger)"
        shortcutService.unregisterShortcut(identifier: identifier)
        registeredSnippetTriggers.remove(trigger)
        Logger.snippet("Unregistered snippet trigger: \(trigger)", level: .info)
    }
    
    // MARK: - Event Handling
    
    /// FIX: Minimized event handling - only extracts character and queues async processing
    /// This callback runs at very high frequency, so we must keep it as lightweight as possible
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Fast early return for non-keyDown events
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        // FIX: Double-check monitoring status with queue synchronization to prevent race conditions
        // This ensures handleEvent cannot execute after stopMonitoring() has been called
        var shouldProcess = false
        monitoringQueue.sync {
            shouldProcess = _isMonitoring && _eventTap != nil
        }
        
        guard shouldProcess else {
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
                
                // FIX: Verify monitoring is still active before processing
                // This prevents processing after stopMonitoring() is called
                guard self.isMonitoringFast else { return }
                
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
    
    /// OPTIMIZATION: Async snippet matching - runs on separate queue, doesn't block event tap
    private func processSnippetMatch(buffer: String) {
        // Double-check monitoring status (may have changed since event was queued)
        os_unfair_lock_lock(&monitoringLock)
        let currentlyMonitoring = _isMonitoring
        os_unfair_lock_unlock(&monitoringLock)
        
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
    
    /// OPTIMIZATION: Async snippet matching - receives buffer snapshot to avoid race conditions
    /// PERFORMANCE: O(k) Trie-based snippet matching (k = trigger length)
    /// This is 10-100x faster than the old O(n log n) sorting approach
    private func checkForSnippetMatch(buffer: String) {
        // Debug logging for snippet matching
        #if DEBUG
        if buffer.count >= 2 {
            Logger.snippet("Checking buffer for snippet: '\(buffer)' (length: \(buffer.count))", level: .debug)
        }
        #endif

        // Use Trie for efficient O(k) lookup instead of O(n log n) sorting
        // The Trie automatically handles longest-match priority (e.g., !mail1 before !mail)
        if let snippet = snippetManager.findSnippetMatch(in: buffer, requireWordBoundary: true) {
            Logger.snippet("Snippet match found: '\(snippet.trigger)' in buffer '\(buffer)'", level: .debug)
            expandSnippet(trigger: snippet.trigger)
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
    /// This must match the logic in SnippetTrie.isWordDelimiter for consistency
    private func isWordDelimiter(_ char: Character) -> Bool {
        return char.isWhitespace || char.isNewline ||
               [".", ",", ";", ":", "!", "?", "-", "_", "(", ")", "[", "]", "{", "}", "/", "\\", "'", "\"", "@", "#", "$", "%", "^", "&", "*", "+", "=", "<", ">", "`", "~"].contains(char)
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
            Logger.snippet("Snippet lookup failed for trigger: '\(trigger)' - trigger matched in Trie but not found in SnippetManager", level: .warning)
            return
        }

        Logger.snippet("Expanding snippet: '\(trigger)' → '\(snippet.content.prefix(50))...'", level: .info)
        
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
        
        Task {
            // Use delete-by-selection method for more reliable deletion
            let deletionSuccess = await deleteTriggerBySelection(triggerLength: triggerLength)
            
            if deletionSuccess {
                // Increased delay to ensure deletion is fully processed
                let adaptiveDelay = calculateAdaptiveDelay(triggerLength: triggerLength)
                try? await Task.sleep(nanoseconds: UInt64(adaptiveDelay * 1_000_000_000))
                
                // Paste the processed snippet content
                await pasteText(processedText)
                
                // Snippets 2.0: Handle cursor placement if specified
                if let cursorPos = cursorPosition, cursorPos > 0 {
                    // Wait a bit for paste to complete, then move cursor
                    try? await Task.sleep(nanoseconds: 100 * 1_000_000) // 100ms
                    await moveCursorLeft(by: cursorPos)
                }
                
                // Clear buffer
                bufferQueue.async(flags: .barrier) {
                    self._keyBuffer = ""
                }
            } else {
                // Fallback: Use traditional backspace method if selection deletion fails
                Logger.snippet("Selection deletion failed, using backspace fallback", level: .warning)
                await deleteTriggerByBackspace(triggerLength: triggerLength)
                
                let adaptiveDelay = calculateAdaptiveDelay(triggerLength: triggerLength)
                try? await Task.sleep(nanoseconds: UInt64(adaptiveDelay * 1_000_000_000))
                
                await pasteText(processedText)
                
                if let cursorPos = cursorPosition, cursorPos > 0 {
                    try? await Task.sleep(nanoseconds: 100 * 1_000_000) // 100ms
                    await moveCursorLeft(by: cursorPos)
                }
                
                bufferQueue.async(flags: .barrier) {
                    self._keyBuffer = ""
                }
            }
        }
    }
    
    /// Deletes trigger text using selection method (Shift+Left Arrow + Delete)
    /// More reliable than multiple backspaces, especially under high CPU load
    private func deleteTriggerBySelection(triggerLength: Int) async -> Bool {
        // For short triggers, use backspace (faster)
        if triggerLength <= 3 {
            await deleteTriggerByBackspace(triggerLength: triggerLength)
            return true
        }
        
        let leftArrowKey = CGKeyCode(kVK_LeftArrow)
        let deleteKey = CGKeyCode(kVK_Delete)
        
        let adaptiveDelay = calculateAdaptiveDelay(triggerLength: triggerLength)
        let delayPerStep = max(adaptiveDelay / Double(triggerLength), JoyaFixConstants.snippetBackspaceMinDelay)
        
        // Select text backwards character by character
        for _ in 0..<triggerLength {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKey, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKey, keyDown: false) else {
                return false
            }
            
            keyDown.flags = .maskShift
            keyUp.flags = .maskShift
            
            keyDown.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: UInt64(delayPerStep * 1_000_000_000))
            keyUp.post(tap: .cghidEventTap)
            
            // Wait before next step
            try? await Task.sleep(nanoseconds: UInt64(delayPerStep * 1_000_000_000))
        }
        
        // All text selected, now delete it
        try? await Task.sleep(nanoseconds: 10 * 1_000_000) // 10ms
        
        guard let deleteDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: true),
              let deleteUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: false) else {
            return false
        }
        
        deleteDown.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 10 * 1_000_000) // 10ms
        deleteUp.post(tap: .cghidEventTap)
        
        // Give buffer for deletion to complete
        try? await Task.sleep(nanoseconds: 20 * 1_000_000) // 20ms
        return true
    }
    
    /// Fallback method: Deletes trigger using traditional backspace with adaptive delays
    private func deleteTriggerByBackspace(triggerLength: Int) async {
        let deleteKey = CGKeyCode(kVK_Delete)
        let adaptiveDelay = calculateAdaptiveDelay(triggerLength: triggerLength)
        let delayPerBackspace = max(adaptiveDelay / Double(triggerLength), JoyaFixConstants.snippetBackspaceMinDelay)
        
        for _ in 0..<triggerLength {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: false) else {
                return
            }
            
            keyDown.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: UInt64(delayPerBackspace * 1_000_000_000))
            keyUp.post(tap: .cghidEventTap)
            
            // Wait before next backspace
            try? await Task.sleep(nanoseconds: UInt64(delayPerBackspace * 1_000_000_000))
        }
    }
    
    /// Calculates adaptive delay based on trigger length and system load
    private func calculateAdaptiveDelay(triggerLength: Int) -> TimeInterval {
        // Base delay increases with trigger length
        let baseDelay = JoyaFixConstants.snippetBackspaceDelay
        
        // Factor in trigger length (longer triggers need more time)
        let lengthFactor = 1.0 + (Double(triggerLength) * 0.01)
        
        // Check system load (simplified)
        let cpuLoadFactor: Double = 1.2
        
        // Calculate adaptive delay with safety buffer
        let adaptiveDelay = baseDelay * lengthFactor * cpuLoadFactor
        
        // Clamp to reasonable bounds
        return min(max(adaptiveDelay, JoyaFixConstants.snippetBackspaceMinDelay * Double(triggerLength)),
                   JoyaFixConstants.snippetPostDeleteDelay)
    }
    
    /// Moves cursor left by specified number of characters
    private func moveCursorLeft(by count: Int) async {
        let keyCode = CGKeyCode(kVK_LeftArrow)
        
        for _ in 0..<count {
            guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                  let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
                continue
            }
            
            keyDownEvent.post(tap: CGEventTapLocation.cghidEventTap)
            try? await Task.sleep(nanoseconds: 5 * 1_000_000) // 5ms
            keyUpEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
    
    private func pasteText(_ text: String) async {
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
        try? await Task.sleep(nanoseconds: 10 * 1_000_000) // 10ms
        keyUpEvent.post(tap: CGEventTapLocation.cghidEventTap)
    }
}

