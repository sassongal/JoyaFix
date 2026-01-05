import Cocoa
import ApplicationServices

class KeyboardBlocker {
    static let shared = KeyboardBlocker()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isLocked = false
    private var unlockTimer: Timer?
    private var escKeyPressStartTime: Date?
    private let escHoldDuration: TimeInterval = 3.0 // Hold ESC for 3 seconds to unlock
    
    // Overlay window for lock indicator
    private var overlayWindow: NSWindow?
    
    // Unlock hotkey combination: Cmd+Option+L (same as lock)
    private let unlockKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_L)
    private let unlockModifiers: CGEventFlags = [.maskCommand, .maskAlternate]
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Toggles keyboard lock state
    func toggleLock() {
        if isLocked {
            unlock()
        } else {
            lock()
        }
    }
    
    /// Locks the keyboard
    func lock() {
        guard !isLocked else { return }
        
        // Check accessibility permissions
        guard checkAccessibilityPermissions() else {
            print("⚠️ Accessibility permissions required for keyboard blocking")
            return
        }
        
        isLocked = true
        setupEventTap()
        showOverlay()
        print("🔒 Keyboard locked")
    }
    
    /// Unlocks the keyboard
    func unlock() {
        guard isLocked else { return }
        
        isLocked = false
        removeEventTap()
        hideOverlay()
        escKeyPressStartTime = nil
        unlockTimer?.invalidate()
        unlockTimer = nil
        print("🔓 Keyboard unlocked")
    }
    
    /// Returns current lock state
    var isKeyboardLocked: Bool {
        return isLocked
    }
    
    // MARK: - Event Tap Setup
    
    private func setupEventTap() {
        // Remove existing tap if any
        removeEventTap()
        
        // Create event mask for keyboard events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        // Create event tap
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon!).takeUnretainedValue()
                return blocker.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            print("❌ Failed to create event tap")
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
        
        // Enable the tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func removeEventTap() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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
                return nil // Consume the event
            }
            
            // Check for ESC key (hold for 3 seconds to unlock)
            if keyCode == Int64(kVK_Escape) {
                if escKeyPressStartTime == nil {
                    escKeyPressStartTime = Date()
                    startEscHoldTimer()
                }
                return nil // Consume ESC key
            }
        }
        
        if type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // Reset ESC hold timer if ESC is released
            if keyCode == Int64(kVK_Escape) {
                escKeyPressStartTime = nil
                unlockTimer?.invalidate()
                unlockTimer = nil
            }
        }
        
        // Block all other keyboard events
        return nil // Consume all events when locked
    }
    
    private func startEscHoldTimer() {
        unlockTimer = Timer.scheduledTimer(withTimeInterval: escHoldDuration, repeats: false) { [weak self] _ in
            guard let self = self, let startTime = self.escKeyPressStartTime else { return }
            
            // Check if ESC is still being held
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed >= self.escHoldDuration {
                self.unlock()
            }
        }
    }
    
    // MARK: - Overlay Window
    
    private func showOverlay() {
        DispatchQueue.main.async {
            // Get all screens
            let screens = NSScreen.screens
            let combinedFrame = screens.reduce(NSRect.zero) { result, screen in
                return result.union(screen.frame)
            }
            
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
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
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
        let message = "Keyboard Locked - Hold ESC for 3 seconds to Unlock"
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

