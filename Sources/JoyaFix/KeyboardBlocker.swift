import Cocoa
import ApplicationServices
import Carbon

// CRITICAL FIX: Global weak reference for C callback access (prevents retain cycle)
// Use thread-safe access with a lock
private let instanceLock = NSLock()
private weak var globalKeyboardBlockerInstance: KeyboardBlocker?
// Track if we're in an active lock state (for fail-safe event blocking during transitions)
private var globalIsInActiveLockState = false

// MARK: - Global C Callback Function
// CRITICAL FIX: Defined outside the class to prevent Swift closure capture crashes
private func globalKeyboardBlockerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    instanceLock.lock()
    defer { instanceLock.unlock() }

    guard let blocker = globalKeyboardBlockerInstance else {
        // SECURITY FIX: If instance is nil but we're in active lock state,
        // block the event to prevent bypass during transition
        if globalIsInActiveLockState {
            return nil  // Block event during transition (fail-safe)
        }
        return Unmanaged.passUnretained(event)
    }
    return blocker.handleEvent(proxy: proxy, type: type, event: event)
}

class KeyboardBlocker {
    static let shared = KeyboardBlocker()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isLocked = false
    private var isUnlocking = false  // Prevents hiding during unlock transition

    // CRITICAL FIX: Lock for state machine synchronization
    private let stateLock = NSLock()

    // Overlay window for lock indicator
    private var overlayWindow: NSWindow?

    // Unlock hotkey combination: Cmd+Option+L (same as lock)
    private let unlockKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_L)
    private let unlockModifiers: CGEventFlags = [.maskCommand, .maskAlternate]

    private init() {}
    
    // MARK: - Public Interface

    /// Toggles keyboard lock state (thread-safe)
    func toggleLock() {
        stateLock.lock()
        defer { stateLock.unlock() }

        if isLocked {
            unlockInternal()
        } else {
            lockInternal()
        }
    }

    /// Locks the keyboard (thread-safe)
    func lock() {
        stateLock.lock()
        defer { stateLock.unlock() }
        lockInternal()
    }

    /// Internal lock implementation - assumes stateLock is held
    private func lockInternal() {
        guard !isLocked else { return }

        // Check accessibility permissions with user prompt if needed
        guard checkAccessibilityPermissions() else {
            Logger.security("Accessibility permissions required for keyboard blocking", level: .warning)
            return
        }

        isLocked = true
        // Set global lock state for fail-safe event blocking
        instanceLock.lock()
        globalIsInActiveLockState = true
        instanceLock.unlock()

        setupEventTap()
        showOverlay()
        Logger.info("Keyboard locked")
        // Notify that lock state changed
        NotificationCenter.default.post(name: NSNotification.Name("JoyaFixKeyboardLockStateChanged"), object: nil)
    }

    /// Unlocks the keyboard (thread-safe)
    func unlock() {
        stateLock.lock()
        defer { stateLock.unlock() }
        unlockInternal()
    }

    /// Internal unlock implementation - assumes stateLock is held
    private func unlockInternal() {
        guard isLocked else { return }

        // Set unlocking flag to prevent app from hiding during transition
        isUnlocking = true
        isLocked = false

        // Clear global lock state
        instanceLock.lock()
        globalIsInActiveLockState = false
        instanceLock.unlock()

        removeEventTap()
        hideOverlay()
        Logger.info("Keyboard unlocked")
        // Notify that lock state changed
        NotificationCenter.default.post(name: NSNotification.Name("JoyaFixKeyboardLockStateChanged"), object: nil)

        // CRITICAL FIX: Use weak self to prevent retain cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.stateLock.lock()
            self?.isUnlocking = false
            self?.stateLock.unlock()
        }
    }

    /// Returns current lock state (thread-safe)
    var isKeyboardLocked: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isLocked
    }

    /// Returns true if app should stay visible (locked or unlocking) (thread-safe)
    var shouldPreventHiding: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isLocked || isUnlocking
    }
    
    // MARK: - Event Tap Setup
    
    private func setupEventTap() {
        // Remove existing tap if any
        removeEventTap()
        
        // CRITICAL FIX: Set global weak reference to prevent retain cycle (thread-safe)
        instanceLock.lock()
        globalKeyboardBlockerInstance = self
        instanceLock.unlock()
        
        // Create event mask for keyboard events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        // Create event tap
        // CRITICAL FIX: Use global C function pointer instead of closure to prevent retain cycle
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: globalKeyboardBlockerCallback,
            userInfo: nil // No need for userInfo with global reference
        )
        
        guard let eventTap = eventTap else {
            Logger.error("Failed to create event tap - keyboard blocking unavailable")
            isLocked = false // Reset state since we couldn't lock
            
            // Notify user that keyboard blocking failed
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Failed to enable keyboard lock. Please check accessibility permissions.",
                        style: .error,
                        duration: 3.0
                    )
                )
            }
            return
        }
        
        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            Logger.error("Failed to create run loop source for keyboard blocker")
            return
        }
        
        // CRITICAL FIX: Use main run loop explicitly for thread safety
        // Ensure we're on the main thread (event tap setup should be on main thread)
        assert(Thread.isMainThread, "setupEventTap must be called on main thread")
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        
        // Enable the tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func removeEventTap() {
        // CRITICAL FIX: Clear global reference thread-safely
        instanceLock.lock()
        globalKeyboardBlockerInstance = nil
        instanceLock.unlock()
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        if let runLoopSource = runLoopSource {
            // CRITICAL FIX: Always remove from main run loop (not current run loop)
            if Thread.isMainThread {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            } else {
                DispatchQueue.main.sync {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
                }
            }
            self.runLoopSource = nil
        }
    }
    
    // MARK: - Event Handling
    
    // CRITICAL FIX: Changed to fileprivate to allow access from global callback function
    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isLocked else {
            return Unmanaged.passUnretained(event)
        }
        
        // Check for unlock combination: Cmd+Option+L
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            
            // Check if it's the unlock combination
            if keyCode == Int64(unlockKeyCode) &&
               flags.contains(.maskCommand) &&
               flags.contains(.maskAlternate) {
                unlock()
                SoundManager.shared.playSuccess()
                return nil // Consume the event
            }
            
            // Check for ESC key (immediate unlock)
            if keyCode == Int64(kVK_Escape) {
                Logger.debug("ESC pressed - unlocking keyboard cleaner")

                // Immediately unlock on ESC press (no hold required)
                unlock()
                SoundManager.shared.playSuccess()

                Logger.debug("Keyboard cleaner unlocked successfully")

                // Keep the app active after unlocking to prevent it from hiding
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    Logger.debug("App activated after ESC unlock")

                    // Show toast notification for user feedback
                    NotificationCenter.default.post(
                        name: .showToast,
                        object: ToastMessage(text: "Keyboard unlocked", style: .success, duration: 2.0)
                    )
                }

                // Consume the ESC event to prevent it from being processed further
                return nil
            }
        }
        
        // ESC key handling is done in keyDown, no need for keyUp handling
        
        // Block all other keyboard events
        return nil // Consume all events when locked
    }
    
    // MARK: - Overlay Window
    
    private func showOverlay() {
        DispatchQueue.main.async {
            // Get all screens and calculate combined frame properly
            // (handles multi-monitor setups with negative coordinates)
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return }

            // Calculate bounds that properly handle all screen geometries
            var minX = CGFloat.infinity
            var minY = CGFloat.infinity
            var maxX = -CGFloat.infinity
            var maxY = -CGFloat.infinity

            for screen in screens {
                minX = min(minX, screen.frame.minX)
                minY = min(minY, screen.frame.minY)
                maxX = max(maxX, screen.frame.maxX)
                maxY = max(maxY, screen.frame.maxY)
            }

            let combinedFrame = NSRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )

            // Create overlay window
            let window = NSWindow(
                contentRect: combinedFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            window.backgroundColor = NSColor.black.withAlphaComponent(0.3)
            window.isOpaque = false
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            // Create content view with message
            let contentView = KeyboardLockOverlayView()
            window.contentView = contentView
            
            window.makeKeyAndOrderFront(nil)
            self.overlayWindow = window
        }
    }
    
    private func hideOverlay() {
        DispatchQueue.main.async {
            self.overlayWindow?.close()
            self.overlayWindow = nil
        }
    }
    
    // MARK: - Accessibility Check

    private func checkAccessibilityPermissions() -> Bool {
        // First check without prompting
        let checkOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(checkOptions)

        if !isTrusted {
            // Show user-friendly message before system prompt
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Keyboard lock requires Accessibility permission. Please enable it in System Settings.",
                        style: .warning,
                        duration: 5.0
                    )
                )
            }

            // Now prompt with system dialog
            let promptOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(promptOptions)
        }

        return isTrusted
    }
    
    deinit {
        removeEventTap()
        hideOverlay()
    }
}

// MARK: - Overlay View

class KeyboardLockOverlayView: NSView {
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
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw semi-transparent background
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()
        
        // Draw message
        let message = NSLocalizedString("keyboard.lock.overlay.message", comment: "Keyboard locked overlay message")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: NSColor.white,
            .shadow: {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
                shadow.shadowOffset = NSSize(width: 0, height: -2)
                shadow.shadowBlurRadius = 4
                return shadow
            }()
        ]
        
        let textSize = message.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (dirtyRect.width - textSize.width) / 2,
            y: (dirtyRect.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        message.draw(in: textRect, withAttributes: attributes)
    }
}

