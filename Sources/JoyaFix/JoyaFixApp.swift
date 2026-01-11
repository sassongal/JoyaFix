import SwiftUI
import Combine
import Pulse

@main
struct JoyaFixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty - we use LSUIElement and manage windows manually
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var clipboardManager = ClipboardHistoryManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    /// Resizes the popover based on the selected tab
    func resizePopover(for tab: Int) {
        guard let popover = popover else { return }
        
        let newSize: NSSize
        switch tab {
        case 0: // Clipboard
            newSize = NSSize(width: 500, height: 600)
        case 1: // Scratchpad
            newSize = NSSize(width: 500, height: 600)
        case 2: // Library
            newSize = NSSize(width: 1200, height: 900)
        case 3: // Vision Lab
            newSize = NSSize(width: 600, height: 700)
        default:
            newSize = NSSize(width: 500, height: 600)
        }
        
        // Animate the size change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            popover.contentSize = newSize
        }
    }

    /// Fail-safe logo loading for menubar - tries multiple methods
    private func loadMenubarLogo() -> NSImage? {
        // Priority 1: Bundle.main (final app bundle) - this is the primary method
        if let image = NSImage(named: "FLATLOGO") {
            return image
        }

        // Priority 2: Try from bundle with path
        if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: "png"),
           let logoImage = NSImage(contentsOfFile: logoPath) {
            return logoImage
        }

        // Priority 3: Try from source directory (for swift run during development)
        let sourcePath = #file.replacingOccurrences(of: "/JoyaFixApp.swift", with: "/Resources/FLATLOGO.png")
        if FileManager.default.fileExists(atPath: sourcePath),
           let logoImage = NSImage(contentsOfFile: sourcePath) {
            Logger.info("Loaded logo from source path (development mode)")
            return logoImage
        }

        return nil
    }
    
    // FIX: Prevent app from terminating when windows close (LSUIElement apps should stay running)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // CRITICAL FIX: Prevent app from hiding when ESC is pressed during keyboard lock
    func applicationShouldHide(_ sender: NSApplication) -> Bool {
        // If keyboard is locked, don't allow the app to hide (ESC should only unlock, not hide)
        if KeyboardBlocker.shared.isKeyboardLocked {
            return false
        }
        return true
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set activation policy early for LSUIElement apps
        // This must be done before applicationDidFinishLaunching
        NSApp.setActivationPolicy(.accessory)
        print("✓ Activation policy set to .accessory")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup crash reporting first
        CrashReporter.setup()
        
        Logger.info("🚀 applicationDidFinishLaunching called")
        
        // CRITICAL: Synchronize permissions with system on startup
        // This ensures we have the latest permission status and clears any stale cache
        PermissionManager.shared.synchronizePermissions()
        Logger.info("✓ Permissions synchronized with system")
        
        // Initialize Pulse logging system for network request logging
        // Pulse automatically intercepts URLSession requests when imported
        // For full UI integration, import PulseUI and add PulseView to your settings
        
        // CRITICAL: Activate app to ensure menubar icon appears
        NSApp.activate(ignoringOtherApps: true)
        
        // Create the status bar item
        print("📊 Creating status bar item...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        print("✓ Status bar item created: \(statusItem != nil)")

        if let button = statusItem?.button {
            print("✓ Status bar button exists")
            updateMenubarIcon(button: button)
            
            // Set up button action
            button.action = #selector(statusBarButtonClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            print("✓ Button actions configured")
            
            // Observe keyboard lock state changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardLockStateChanged),
                name: NSNotification.Name("JoyaFixKeyboardLockStateChanged"),
                object: nil
            )
        } else {
            print("❌ Status bar button is nil!")
        }
        
        print("✅ Status bar setup complete")
        
        // CRITICAL: Force status bar item to be visible
        // Sometimes the icon doesn't appear immediately, so we ensure it's visible
        if let button = statusItem?.button {
            button.isHidden = false
            button.appearsDisabled = false
            print("✓ Status bar button visibility ensured")
        }

        // Create popover
        setupPopover()
        
        // Listen for popover resize notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopoverResize(_:)),
            name: NSNotification.Name("JoyaFixResizePopover"),
            object: nil
        )

        // Start clipboard monitoring
        clipboardManager.startMonitoring()
        
        // Cleanup orphaned files (files not referenced in history JSON)
        // This should run after history is loaded to remove unused files
        DispatchQueue.main.async {
            ClipboardHistoryManager.shared.cleanupOrphanedFiles()
        }

        // CRITICAL FIX: Always register hotkeys, regardless of permission status
        // Permissions will be checked when hotkeys are actually pressed
        let convertSuccess = HotkeyManager.shared.registerHotkey()
        // let ocrSuccess = HotkeyManager.shared.registerOCRHotkey() // Disabled
        let keyboardLockSuccess = HotkeyManager.shared.registerKeyboardLockHotkey()
        let promptSuccess = HotkeyManager.shared.registerPromptHotkey()

        if convertSuccess && keyboardLockSuccess && promptSuccess {
            print("✓ Hotkeys registered successfully")
            print("  - Text conversion hotkey registered")
            print("  - Keyboard lock hotkey registered")
            print("  - Prompt enhancer hotkey registered")
        } else {
            if !convertSuccess {
                print("✗ Failed to register conversion hotkey")
            }
            if !convertSuccess {
                print("✗ Failed to register conversion hotkey")
            }
            // if !ocrSuccess { print("✗ Failed to register OCR hotkey") }
            if !keyboardLockSuccess {
                print("✗ Failed to register keyboard lock hotkey")
            }
            if !promptSuccess {
                print("✗ Failed to register prompt enhancer hotkey")
            }
        }
        
        // OCR Hotkey disabled for now (feature refactored to upcoming)
        // HotkeyManager.shared.registerOCRHotkey()
        
        // Check if this is first run and show onboarding
        checkAndShowOnboarding()
    }

    // MARK: - Popover Setup

    private func setupPopover() {
        let popover = NSPopover()
        // Initial size for Clipboard/Scratchpad tab (default)
        popover.contentSize = NSSize(width: 500, height: 600)
        popover.behavior = .transient
        popover.animates = true

        let historyView = HistoryView(
            onPasteItem: { [weak self] item, plainTextOnly in
                Task { @MainActor in
                    self?.clipboardManager.pasteItem(item, simulatePaste: true, plainTextOnly: plainTextOnly)
                    self?.closePopover()
                }
            },
            onClose: { [weak self] in
                self?.closePopover()
            }
        )

        // Use custom view controller with native blur background
        popover.contentViewController = BlurredPopoverViewController(rootView: historyView)
        self.popover = popover
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        // Right-click shows context menu
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            // Left-click toggles popover
            togglePopover()
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }

        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo view: NSView) {
        // Recreate the popover content to refresh the view state
        setupPopover()
        
        Logger.info("📂 Showing History Popover")
        
        // Show immediately without delay
        popover?.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        
        // Refresh history in background just in case
        Task { @MainActor in
            // Trigger property access to ensure latest data
            if !clipboardManager.history.isEmpty {
                Logger.info("📚 History contains \(clipboardManager.history.count) items")
            } else {
                Logger.info("⚠️ History is empty")
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }
    
    @objc private func handlePopoverResize(_ notification: Notification) {
        if let tab = notification.userInfo?["tab"] as? Int {
            resizePopover(for: tab)
        }
    }
    
    /// Updates the menubar icon with optional keyboard lock indicator
    private func updateMenubarIcon(button: NSStatusBarButton) {
        // Fail-safe logo loading for menubar icon
        if let logoImage = loadMenubarLogo() {
            print("✓ Logo loaded successfully")
            // Resize logo to menubar size (22px)
            let resizedLogo = NSImage(size: NSSize(width: JoyaFixConstants.menubarIconSize, height: JoyaFixConstants.menubarIconSize))
            resizedLogo.lockFocus()
            logoImage.draw(in: NSRect(x: 0, y: 0, width: JoyaFixConstants.menubarIconSize, height: JoyaFixConstants.menubarIconSize),
                          from: NSRect(origin: .zero, size: logoImage.size),
                          operation: .sourceOver,
                          fraction: 1.0)
            
            // Add lock badge if keyboard is locked
            if KeyboardBlocker.shared.isKeyboardLocked {
                // Draw orange circle background
                NSColor.orange.setFill()
                let badgeRect = NSRect(x: JoyaFixConstants.menubarIconSize - 10, y: JoyaFixConstants.menubarIconSize - 10, width: 10, height: 10)
                NSBezierPath(ovalIn: badgeRect).fill()
                
                // Draw white lock icon on top
                if let lockIcon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Keyboard Locked") {
                    NSColor.white.set()
                    let iconRect = NSRect(x: JoyaFixConstants.menubarIconSize - 8, y: JoyaFixConstants.menubarIconSize - 8, width: 6, height: 6)
                    lockIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }
            
            resizedLogo.unlockFocus()
            resizedLogo.isTemplate = true  // Enable template mode for Dark Mode support
            button.image = resizedLogo
            print("✓ Logo set on button")
        } else {
            // Fallback to text icon if logo not found
            let fallbackTitle = KeyboardBlocker.shared.isKeyboardLocked ? "🔒 א/A" : "א/A"
            button.title = fallbackTitle
            print("⚠️ Logo not found - using text fallback: '\(fallbackTitle)'")
        }
    }
    
    @objc private func keyboardLockStateChanged() {
        if let button = statusItem?.button {
            updateMenubarIcon(button: button)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Add "Convert Selection Layout" menu item at the top
        let convertItem = NSMenuItem(
            title: L("menu.convert.selection", comment: "Convert selection"),
            action: #selector(convertSelectionFromMenu),
            keyEquivalent: ""
        )
        convertItem.target = self
        convertItem.image = createColoredIcon(systemName: "arrow.left.arrow.right", color: .blue)
        menu.addItem(convertItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add Prompt Enhancer menu item
        let promptItem = NSMenuItem(
            title: L("menu.enhance.prompt", comment: "Enhance prompt"),
            action: #selector(enhancePrompt),
            keyEquivalent: "p"
        )
        promptItem.keyEquivalentModifierMask = [.command, .option]
        promptItem.target = self
        promptItem.image = createColoredIcon(systemName: "sparkles", color: .purple)
        menu.addItem(promptItem)
        
        // Add Smart Translate menu item (New Feature)
        let translateItem = NSMenuItem(
            title: L("menu.smart.translate", comment: "Smart Translate"),
            action: #selector(smartTranslate),
            keyEquivalent: "t"
        )
        translateItem.keyEquivalentModifierMask = [.command, .shift] 
        translateItem.target = self
        translateItem.image = createColoredIcon(systemName: "globe", color: .green)
        menu.addItem(translateItem)
        
        // Add Keyboard Cleaner menu item
        let keyboardCleanerItem = NSMenuItem(
            title: KeyboardBlocker.shared.isKeyboardLocked ? L("menu.unlock.keyboard", comment: "Unlock keyboard") : L("menu.keyboard.cleaner", comment: "Keyboard cleaner"),
            action: #selector(toggleKeyboardLock),
            keyEquivalent: "l"
        )
        keyboardCleanerItem.keyEquivalentModifierMask = [.command, .option]
        keyboardCleanerItem.target = self
        keyboardCleanerItem.image = createColoredIcon(systemName: KeyboardBlocker.shared.isKeyboardLocked ? "lock.fill" : "lock.open", color: .orange)
        menu.addItem(keyboardCleanerItem)

        let clearHistoryItem = NSMenuItem(
            title: L("menu.clear.history", comment: "Clear history"),
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearHistoryItem.target = self
        clearHistoryItem.image = createColoredIcon(systemName: "trash", color: .red)
        menu.addItem(clearHistoryItem)

        // Add Settings menu item
        let settingsItem = NSMenuItem(
            title: L("menu.settings", comment: "Settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.isEnabled = true
        settingsItem.image = createColoredIcon(systemName: "gearshape", color: .gray)
        menu.addItem(settingsItem)
        
        // Add Keyboard Shortcuts menu item
        let shortcutsItem = NSMenuItem(
            title: L("menu.keyboard.shortcuts", comment: "Keyboard shortcuts"),
            action: #selector(showKeyboardShortcuts),
            keyEquivalent: "?"
        )
        shortcutsItem.keyEquivalentModifierMask = [.command, .shift]
        shortcutsItem.target = self
        shortcutsItem.image = createColoredIcon(systemName: "keyboard", color: .blue)
        menu.addItem(shortcutsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add About menu item
        let aboutItem = NSMenuItem(
            title: L("menu.about", comment: "About"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = createColoredIcon(systemName: "info.circle", color: .blue)
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitMenuItem = NSMenuItem(
            title: L("menu.quit", comment: "Quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Actions

    /// Clears all clipboard history
    @objc func clearHistory() {
        Task { @MainActor in
            clipboardManager.clearHistory(keepPinned: false)
        }
    }

    /// Converts selected text layout from context menu
    @objc func convertSelectionFromMenu() {
        // Check permissions first
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.accessibility.title", comment: "Accessibility alert title")
            alert.informativeText = NSLocalizedString("alert.accessibility.message", comment: "Accessibility alert message")
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("alert.button.open.settings", comment: "Open settings"))
            alert.addButton(withTitle: NSLocalizedString("alert.button.cancel", comment: "Cancel"))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                PermissionManager.shared.openAccessibilitySettings()
            }
            return
        }
        
        // Call the conversion method
        HotkeyManager.shared.performTextConversion()
    }


    
    /// Translates selected text using AI Context-Aware Translation
    @objc func smartTranslate() {
        // Check permissions first
        guard PermissionManager.shared.isAccessibilityTrusted() else {
             PermissionManager.shared.openAccessibilitySettings()
             return
        }
        
        Task { @MainActor in
            TranslationManager.shared.translateSelectedText()
        }
    }
    
    /// Enhances selected text prompt
    @objc func enhancePrompt() {
        // Check permissions first
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.accessibility.title", comment: "Accessibility alert title")
            alert.informativeText = NSLocalizedString("alert.accessibility.message", comment: "Accessibility alert message")
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("alert.button.open.settings", comment: "Open settings"))
            alert.addButton(withTitle: NSLocalizedString("alert.button.cancel", comment: "Cancel"))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                PermissionManager.shared.openAccessibilitySettings()
            }
            return
        }
        
        // Call the prompt enhancement method
        Task { @MainActor in
            PromptEnhancerManager.shared.enhanceSelectedText()
        }
    }

    /// Opens the settings window
    @objc func openSettings() {
        // Close popover if open
        if let popover = popover, popover.isShown {
            closePopover()
        }
        
        // Use SettingsWindowController to manage the window
        SettingsWindowController.shared.show()
    }
    
    /// Shows the About window
    @objc func showAbout() {
        // Close popover if open
        if let popover = popover, popover.isShown {
            closePopover()
        }
        
        AboutWindowController.shared.show()
    }
    
    /// Shows the Keyboard Shortcuts help window
    @objc func showKeyboardShortcuts() {
        // Close popover if open
        if let popover = popover, popover.isShown {
            closePopover()
        }
        
        KeyboardShortcutsWindowController.shared.show()
    }

    /// Toggles keyboard lock mode
    @objc func toggleKeyboardLock() {
        KeyboardBlocker.shared.toggleLock()
    }
    
    /// Quits the application
    @objc func quitApp() {
        clipboardManager.stopMonitoring()
        HotkeyManager.shared.unregisterHotkey()
        KeyboardBlocker.shared.unlock()
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardManager.stopMonitoring()
        HotkeyManager.shared.unregisterHotkey()
        KeyboardBlocker.shared.unlock()
    }
    
    // MARK: - Onboarding
    
    /// Checks if onboarding is needed and shows it
    private func checkAndShowOnboarding() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: JoyaFixConstants.UserDefaultsKeys.hasCompletedOnboarding)
        
        if !hasCompletedOnboarding {
            print("📋 First run detected - showing onboarding")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OnboardingWindowController.shared.show {
                    // Onboarding completed
                    print("✓ Onboarding completed")
                    // Start InputMonitor if permissions are granted
                    if PermissionManager.shared.isAccessibilityTrusted() {
                        InputMonitor.shared.startMonitoring()
                    }
                }
            }
        } else {
            // Synchronize permissions before checking (ensure fresh status)
            PermissionManager.shared.synchronizePermissions()
            // Start InputMonitor if permissions are granted
            if PermissionManager.shared.isAccessibilityTrusted() {
                InputMonitor.shared.startMonitoring()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Creates a colored SF Symbol icon for menu items
    private func createColoredIcon(systemName: String, color: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return nil
        }
        
        let coloredImage = NSImage(size: image.size)
        coloredImage.lockFocus()
        
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: rect, operation: .sourceAtop, fraction: 1.0)
        
        coloredImage.unlockFocus()
        coloredImage.isTemplate = false
        
        return coloredImage
    }
}
