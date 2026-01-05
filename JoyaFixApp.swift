import SwiftUI
import Combine

@main
struct JoyaFixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
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

        // Check accessibility permissions and register global hotkeys
        if HotkeyManager.checkAccessibilityPermissions() {
            let convertSuccess = HotkeyManager.shared.registerHotkey()
            let ocrSuccess = HotkeyManager.shared.registerOCRHotkey()

            if convertSuccess && ocrSuccess {
                print("✓ JoyaFix is ready!")
                print("  - Text conversion hotkey registered")
                print("  - OCR hotkey registered")
            } else {
                if !convertSuccess {
                    print("✗ Failed to register conversion hotkey")
                }
                if !ocrSuccess {
                    print("✗ Failed to register OCR hotkey")
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
        ScreenCaptureManager.shared.startScreenCapture { extractedText in
            guard let text = extractedText, !text.isEmpty else {
                print("⚠️ No text extracted from screen")
                return
            }

            // Write to clipboard (will be added to history automatically)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            // Play success sound
            SoundManager.shared.playSuccess()

            print("✓ OCR Success: \(text.count) characters extracted and copied")
        }
    }

    /// Opens the settings window
    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Quits the application
    @objc func quitApp() {
        clipboardManager.stopMonitoring()
        HotkeyManager.shared.unregisterHotkey()
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardManager.stopMonitoring()
        HotkeyManager.shared.unregisterHotkey()
    }
}
