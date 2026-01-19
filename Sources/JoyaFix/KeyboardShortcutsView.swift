import SwiftUI
import Carbon

/// View displaying all available keyboard shortcuts in JoyaFix
struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Shortcuts List
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Global Hotkeys Section
                    ShortcutSection(
                        title: "Global Hotkeys",
                        description: "These shortcuts work system-wide, even when JoyaFix is in the background",
                        shortcuts: [
                            ShortcutItem(
                                name: "Text Conversion",
                                shortcut: settings.hotkeyDisplayString,
                                description: "Convert selected text between Hebrew and English keyboard layouts"
                            ),
                            ShortcutItem(
                                name: "Keyboard Cleaner",
                                shortcut: "⌘⌥L",
                                description: "Lock/unlock keyboard to prevent accidental input"
                            )
                        ]
                    )
                    
                    // Clipboard History Section
                    ShortcutSection(
                        title: "Clipboard History",
                        description: "Access clipboard history from the menubar popover",
                        shortcuts: [
                            ShortcutItem(
                                name: "Open Clipboard History",
                                shortcut: "Click menubar icon",
                                description: "Click the JoyaFix icon in the menubar to open clipboard history"
                            ),
                            ShortcutItem(
                                name: "Quick Access Items",
                                shortcut: "⌘1-9",
                                description: "Press Cmd+1 through Cmd+9 to quickly paste items from history"
                            ),
                            ShortcutItem(
                                name: "Paste as Plain Text",
                                shortcut: "⇧+Click or ⌥+Click",
                                description: "Hold Shift or Option while clicking an item to paste without formatting"
                            ),
                            ShortcutItem(
                                name: "Search History",
                                shortcut: "Type in search box",
                                description: "Start typing to filter clipboard history items"
                            )
                        ]
                    )
                    
                    // Tips Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tips")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TipItem(
                            icon: "info.circle.fill",
                            text: "You can customize hotkeys in Settings → General"
                        )
                        TipItem(
                            icon: "keyboard.fill",
                            text: "All hotkeys require at least one modifier key (Cmd, Option, Shift, or Control)"
                        )
                        TipItem(
                            icon: "exclamationmark.triangle.fill",
                            text: "If a hotkey doesn't work, it may be reserved by macOS or another app"
                        )
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Close", action: { dismiss() })
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 650)
    }
    
    private func hotkeyDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var modifierString = ""
        
        if modifiers & UInt32(controlKey) != 0 {
            modifierString += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            modifierString += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            modifierString += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            modifierString += "⌘"
        }
        
        let keyString = settings.keyCodeToString(Int(keyCode))
        return modifierString + keyString
    }
}

// MARK: - Shortcut Section

struct ShortcutSection: View {
    let title: String
    let description: String
    let shortcuts: [ShortcutItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    ShortcutRow(shortcut: shortcut)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Shortcut Item

struct ShortcutItem: Identifiable {
    let id = UUID()
    let name: String
    let shortcut: String
    let description: String
}

// MARK: - Shortcut Row

struct ShortcutRow: View {
    let shortcut: ShortcutItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shortcut.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(shortcut.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Shortcut badge
            Text(shortcut.shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlAccentColor).opacity(0.1))
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tip Item

struct TipItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .frame(width: 16)
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Window Controller

class KeyboardShortcutsWindowController: NSWindowController {
    static let shared = KeyboardShortcutsWindowController()
    
    private var shortcutsWindow: NSWindow?
    
    private init() {
        super.init(window: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if let existingWindow = shortcutsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingView = NSHostingView(rootView: KeyboardShortcutsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 650)
        
        let newWindow = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Keyboard Shortcuts - JoyaFix"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        // Premium entrance animation
        newWindow.showWithPremiumAnimation()
        
        self.shortcutsWindow = newWindow
        NSApp.activate(ignoringOtherApps: true)
    }
}

