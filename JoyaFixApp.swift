import SwiftUI
import Combine

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

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var clipboardManager = ClipboardHistoryManager.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Try to load custom logo
            var logoImage: NSImage?
            
            // Try with .png extension first
            if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: "png") {
                logoImage = NSImage(contentsOfFile: logoPath)
            }
            
            // Try without extension
            if logoImage == nil, let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: nil) {
                logoImage = NSImage(contentsOfFile: logoPath)
            }
            
            // Try loading from main bundle resources
            if logoImage == nil {
                logoImage = NSImage(named: "FLATLOGO")
            }
            
            if let logo = logoImage {
                // Resize logo to menubar size (typically 18-22px)
                let resizedLogo = NSImage(size: NSSize(width: 18, height: 18))
                resizedLogo.lockFocus()
                logo.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18),
                         from: NSRect(origin: .zero, size: logo.size),
                         operation: .sourceOver,
                         fraction: 1.0)
                resizedLogo.unlockFocus()
                resizedLogo.isTemplate = false  // Keep original colors
                button.image = resizedLogo
            } else {
                // Fallback to text icon
                button.title = "א/A"
            }

            // Set up button action
            button.action = #selector(statusBarButtonClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover
        setupPopover()

        // Start clipboard monitoring
        clipboardManager.startMonitoring()

        // CRITICAL FIX: Always register hotkeys, regardless of permission status
        // Permissions will be checked when hotkeys are actually pressed
        let convertSuccess = HotkeyManager.shared.registerHotkey()
        let ocrSuccess = HotkeyManager.shared.registerOCRHotkey()
        let keyboardLockSuccess = HotkeyManager.shared.registerKeyboardLockHotkey()

        if convertSuccess && ocrSuccess && keyboardLockSuccess {
            print("✓ Hotkeys registered successfully")
            print("  - Text conversion hotkey registered")
            print("  - OCR hotkey registered")
            print("  - Keyboard lock hotkey registered")
        } else {
            if !convertSuccess {
                print("✗ Failed to register conversion hotkey")
            }
            if !ocrSuccess {
                print("✗ Failed to register OCR hotkey")
            }
            if !keyboardLockSuccess {
                print("✗ Failed to register keyboard lock hotkey")
            }
        }
        
        // Check if this is first run and show onboarding
        checkAndShowOnboarding()
    }

    // MARK: - Popover Setup

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.animates = true

        let historyView = HistoryView(
            onPasteItem: { [weak self] item, plainTextOnly in
                self?.clipboardManager.pasteItem(item, simulatePaste: true, plainTextOnly: plainTextOnly)
                self?.closePopover()
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
        // Recreate the popover content to refresh the view
        setupPopover()

        popover?.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)

        // Activate the app to ensure keyboard input works
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Add "Convert Selection Layout" menu item at the top
        let convertItem = NSMenuItem(
            title: "Convert Selection Layout",
            action: #selector(convertSelectionFromMenu),
            keyEquivalent: ""
        )
        convertItem.target = self
        menu.addItem(convertItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add OCR menu item
        let ocrItem = NSMenuItem(
            title: "Extract Text from Screen...",
            action: #selector(extractTextFromScreen),
            keyEquivalent: "x"
        )
        ocrItem.keyEquivalentModifierMask = [.command, .option]
        ocrItem.target = self
        menu.addItem(ocrItem)
        
        // Add Keyboard Cleaner menu item
        let keyboardCleanerItem = NSMenuItem(
            title: KeyboardBlocker.shared.isKeyboardLocked ? "Unlock Keyboard" : "Keyboard Cleaner Mode",
            action: #selector(toggleKeyboardLock),
            keyEquivalent: "l"
        )
        keyboardCleanerItem.keyEquivalentModifierMask = [.command, .option]
        keyboardCleanerItem.target = self
        menu.addItem(keyboardCleanerItem)

        let clearHistoryItem = NSMenuItem(
            title: "Clear History",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearHistoryItem.target = self
        menu.addItem(clearHistoryItem)

        // Add Settings menu item
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add About menu item
        let aboutItem = NSMenuItem(
            title: "About JoyaFix",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitMenuItem = NSMenuItem(
            title: "Quit",
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
        clipboardManager.clearHistory(keepPinned: false)
    }

    /// Converts selected text layout from context menu
    @objc func convertSelectionFromMenu() {
        // Check permissions first
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "JoyaFix needs Accessibility permission to simulate keyboard shortcuts (Cmd+C, Cmd+V, Delete)."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                PermissionManager.shared.openAccessibilitySettings()
            }
            return
        }
        
        // Call the conversion method
        HotkeyManager.shared.performTextConversion()
    }

    /// Extracts text from screen using OCR
    @objc func extractTextFromScreen() {
        // ScreenCaptureManager now handles confirmation, OCR, saving to history, and copying to clipboard
        ScreenCaptureManager.shared.startScreenCapture { extractedText in
            if let text = extractedText, !text.isEmpty {
                print("✓ OCR completed: \(text.count) characters extracted and saved to history")
            } else {
                print("⚠️ OCR was cancelled or failed")
            }
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
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
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
            // Start InputMonitor if permissions are granted
            if PermissionManager.shared.isAccessibilityTrusted() {
                InputMonitor.shared.startMonitoring()
            }
        }
    }
}
