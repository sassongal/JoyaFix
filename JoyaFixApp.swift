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
            // Option 1: Use text icon (א/A)
            button.title = "א/A"

            // Option 2: Use system symbol (uncomment to use instead)
            // button.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: "JoyaFix")

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
        
        // Check permissions and show onboarding if needed
        checkPermissionsAndShowOnboarding()
    }

    // MARK: - Popover Setup

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.animates = true

        let historyView = HistoryView(
            onPasteItem: { [weak self] item in
                self?.clipboardManager.pasteItem(item, simulatePaste: true)
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
    
    // MARK: - Permission Management
    
    /// Checks permissions and shows onboarding if permissions are missing
    private func checkPermissionsAndShowOnboarding() {
        // Check if this is first run (no permissions granted yet)
        let hasShownOnboarding = UserDefaults.standard.bool(forKey: "hasShownPermissionOnboarding")
        
        // Check current permission status
        let hasAccessibility = PermissionManager.shared.isAccessibilityTrusted()
        let hasScreenRecording = PermissionManager.shared.isScreenRecordingTrusted()
        
        // If permissions are missing, show onboarding
        if !hasAccessibility || !hasScreenRecording {
            if !hasShownOnboarding {
                // First time - show full onboarding
                print("📋 First run detected - showing permission onboarding")
                PermissionManager.shared.showPermissionAlert()
                UserDefaults.standard.set(true, forKey: "hasShownPermissionOnboarding")
            } else {
                // Not first time, but permissions still missing - show reminder
                print("⚠️ Permissions still missing - showing reminder")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showPermissionReminder()
                }
            }
        } else {
            print("✓ All permissions granted")
        }
    }
    
    /// Shows a reminder alert if permissions are still missing
    private func showPermissionReminder() {
        let hasAccessibility = PermissionManager.shared.isAccessibilityTrusted()
        let hasScreenRecording = PermissionManager.shared.isScreenRecordingTrusted()
        
        if !hasAccessibility || !hasScreenRecording {
            let alert = NSAlert()
            alert.messageText = "Permissions Still Required"
            
            var missingPermissions: [String] = []
            if !hasAccessibility {
                missingPermissions.append("Accessibility")
            }
            if !hasScreenRecording {
                missingPermissions.append("Screen Recording")
            }
            
            alert.informativeText = """
            The following permissions are still required:
            \(missingPermissions.joined(separator: "\n• "))
            
            Please grant these permissions in System Settings for JoyaFix to work properly.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                if !hasAccessibility {
                    PermissionManager.shared.openAccessibilitySettings()
                }
                if !hasScreenRecording {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        PermissionManager.shared.openScreenRecordingSettings()
                    }
                }
            }
        }
    }
}
