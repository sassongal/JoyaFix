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
    private var settingsWindow: NSWindow?
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

        // Check accessibility permissions and register global hotkeys
        if HotkeyManager.checkAccessibilityPermissions() {
            let convertSuccess = HotkeyManager.shared.registerHotkey()
            let ocrSuccess = HotkeyManager.shared.registerOCRHotkey()
            let keyboardLockSuccess = HotkeyManager.shared.registerKeyboardLockHotkey()

            if convertSuccess && ocrSuccess && keyboardLockSuccess {
                print("✓ JoyaFix is ready!")
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
        } else {
            print("⚠️ Please grant Accessibility permissions to use global hotkeys")
        }
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
        // Activate the app first to bring it to front
        NSApp.activate(ignoringOtherApps: true)
        
        // Close popover if open
        if let popover = popover, popover.isShown {
            closePopover()
        }
        
        // Check if settings window already exists
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            return
        }
        
        // Create new settings window
        DispatchQueue.main.async {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 550),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            window.title = "JoyaFix Settings"
            window.contentViewController = hostingController
            window.center()
            window.setFrameAutosaveName("JoyaFixSettings")
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            
            self.settingsWindow = window
            
            // Handle window closing
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                // Don't set to nil, keep reference for reuse
            }
        }
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
}
