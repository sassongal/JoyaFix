import Cocoa
import Foundation
import Carbon

class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    // MARK: - Published Properties

    @Published private(set) var history: [ClipboardItem] = []

    // MARK: - Private Properties

    private var pollTimer: Timer?
    private var lastChangeCount: Int = 0
    private var lastCopiedText: String?
    private var isInternalWrite: Bool = false // Flag to prevent internal writes from being recorded

    // Configuration
    private let settings = SettingsManager.shared
    private let pollInterval: TimeInterval = 0.5
    private let userDefaultsKey = "ClipboardHistory"

    private var maxHistoryCount: Int {
        return settings.maxHistoryCount
    }

    // MARK: - Initialization

    private init() {
        loadHistory()
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Start/Stop Monitoring

    /// Starts monitoring the clipboard for changes
    func startMonitoring() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkForClipboardChanges()
        }
        print("✓ Clipboard monitoring started")
    }

    /// Stops monitoring the clipboard
    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        print("✓ Clipboard monitoring stopped")
    }

    // MARK: - Clipboard Monitoring

    /// Checks if the clipboard has changed and processes new content
    private func checkForClipboardChanges() {
        let currentChangeCount = NSPasteboard.general.changeCount

        // Check if clipboard has changed
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        // If this was an internal write (from our app), skip recording
        if isInternalWrite {
            isInternalWrite = false
            return
        }

        // Capture clipboard content (RTF + plain text)
        guard let item = captureClipboardContent() else { return }

        // Ignore empty strings
        guard !item.plainTextPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Get full text for comparison (handles both preview and full text)
        let itemFullText = item.textForPasting

        // Strict deduplication: Check against all items in history
        let isDuplicate = history.contains { historyItem in
            historyItem.textForPasting == itemFullText
        }

        if isDuplicate {
            print("📝 Skipping duplicate: \(item.plainTextPreview.prefix(30))...")
            return
        }

        // Add to history
        addToHistory(item)
        lastCopiedText = itemFullText
    }

    /// Captures the current clipboard content including RTF data
    private func captureClipboardContent() -> ClipboardItem? {
        let pasteboard = NSPasteboard.general

        // Try to get plain text (required)
        guard let plainText = pasteboard.string(forType: .string) else {
            return nil
        }

        // Try to get RTF data (optional, preserves formatting)
        var rtfData: Data?
        var htmlData: Data?

        // Priority 1: Check for RTFD (Rich Text with attachments)
        if let rtfdData = pasteboard.data(forType: .rtfd) {
            rtfData = rtfdData
            print("📝 Captured RTFD data (\(rtfdData.count) bytes)")
        }
        // Priority 2: Check for RTF
        else if let rtfDataFound = pasteboard.data(forType: .rtf) {
            rtfData = rtfDataFound
            print("📝 Captured RTF data (\(rtfDataFound.count) bytes)")
        }

        // Also capture HTML if available (for web content)
        if let htmlDataFound = pasteboard.data(forType: .html) {
            htmlData = htmlDataFound
            print("🌐 Captured HTML data (\(htmlDataFound.count) bytes)")
        }

        return ClipboardItem(
            plainTextPreview: plainText,
            rtfData: rtfData,
            htmlData: htmlData,
            timestamp: Date(),
            isPinned: false
        )
    }

    // MARK: - History Management

    /// Adds a new item to the clipboard history
    private func addToHistory(_ item: ClipboardItem) {
        // Remove duplicate if it exists elsewhere in the list (preserve pin status if it was pinned)
        var wasPinned = false
        if let existingIndex = history.firstIndex(where: { $0.textForPasting == item.textForPasting }) {
            wasPinned = history[existingIndex].isPinned
            history.remove(at: existingIndex)
        }

        // Create item with preserved pin status
        var itemToAdd = item
        itemToAdd.isPinned = wasPinned

        // Separate pinned and unpinned items
        let pinnedItems = history.filter { $0.isPinned }
        let unpinnedItems = history.filter { !$0.isPinned }

        // Add new item at the top of unpinned section
        var newUnpinnedItems = [itemToAdd] + unpinnedItems

        // Limit unpinned items (pinned items don't count toward the limit)
        if newUnpinnedItems.count > maxHistoryCount {
            newUnpinnedItems = Array(newUnpinnedItems.prefix(maxHistoryCount))
        }

        // Reconstruct history: pinned items first, then unpinned
        history = pinnedItems + newUnpinnedItems

        // Persist to UserDefaults
        saveHistory()

        let formatInfo = item.rtfData != nil ? " [RTF]" : ""
        print("📋 Added to clipboard history: \(item.plainTextPreview.prefix(30))...\(formatInfo)")
    }

    /// Clears all clipboard history (optionally keeping pinned items)
    func clearHistory(keepPinned: Bool = false) {
        if keepPinned {
            history.removeAll { !$0.isPinned }
            print("🗑️ Clipboard history cleared (kept pinned items)")
        } else {
            history.removeAll()
            print("🗑️ Clipboard history cleared")
        }
        lastCopiedText = nil
        saveHistory()
    }

    /// Toggles the pin status of a clipboard item
    func togglePin(for item: ClipboardItem) {
        guard let index = history.firstIndex(where: { $0.id == item.id }) else { return }

        // Toggle the pin status
        var updatedItem = history[index]
        updatedItem.isPinned.toggle()

        // Remove the old item
        history.remove(at: index)

        // Re-insert based on new pin status
        if updatedItem.isPinned {
            // Insert at the end of pinned section
            let pinnedCount = history.filter { $0.isPinned }.count
            history.insert(updatedItem, at: pinnedCount)
            print("📌 Pinned: \(updatedItem.plainTextPreview.prefix(30))...")
        } else {
            // Insert at the start of unpinned section (right after pinned items)
            let pinnedCount = history.filter { $0.isPinned }.count
            history.insert(updatedItem, at: pinnedCount)
            print("📍 Unpinned: \(updatedItem.plainTextPreview.prefix(30))...")
        }

        // Persist changes
        saveHistory()
    }

    /// Deletes a specific clipboard item from history
    func deleteItem(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        saveHistory()
        print("🗑️ Deleted from history: \(item.plainTextPreview.prefix(30))...")
    }

    // MARK: - Paste from History

    /// Writes the selected history item back to the clipboard and optionally pastes it
    func pasteItem(_ item: ClipboardItem, simulatePaste: Bool = true, plainTextOnly: Bool = false) {
        // Mark this as an internal write to prevent it from being re-recorded
        isInternalWrite = true

        // Write to clipboard with proper formatting
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var writtenTypes: [NSPasteboard.PasteboardType] = []

        if plainTextOnly {
            // Plain text only - strip all formatting
            pasteboard.setString(item.textForPasting, forType: .string)
            writtenTypes.append(.string)
            print("📋 Restored plain text only to clipboard: \(item.plainTextPreview.prefix(30))...")
        } else {
            // Write RTF data if available (preserves formatting)
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
                writtenTypes.append(.rtf)
                print("📝 Restored RTF data to clipboard (\(rtfData.count) bytes)")
            }

            // Write HTML data if available
            if let htmlData = item.htmlData {
                pasteboard.setData(htmlData, forType: .html)
                writtenTypes.append(.html)
                print("🌐 Restored HTML data to clipboard")
            }

            // Always write plain text as fallback (use full text if available)
            pasteboard.setString(item.textForPasting, forType: .string)
            writtenTypes.append(.string)

            let typesInfo = writtenTypes.map { $0.rawValue }.joined(separator: ", ")
            print("📋 Restored to clipboard: \(item.plainTextPreview.prefix(30))... [Types: \(typesInfo)]")
        }

        // Optionally simulate Cmd+V to paste immediately
        if simulatePaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.simulatePaste()
            }
        }
    }

    /// Simulates Cmd+V key press to paste
    private func simulatePaste() {
        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDownEvent.flags = .maskCommand
        keyUpEvent.flags = .maskCommand

        let location = CGEventTapLocation.cghidEventTap
        keyDownEvent.post(tap: location)
        usleep(10000) // 10ms delay
        keyUpEvent.post(tap: location)
    }

    // MARK: - Internal Write Notification

    /// Call this before writing to clipboard from within the app (e.g., TextConverter)
    /// to prevent the write from being recorded in history
    func notifyInternalWrite() {
        isInternalWrite = true
    }

    // MARK: - Persistence

    /// Saves clipboard history to UserDefaults
    private func saveHistory() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(history) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    /// Loads clipboard history from UserDefaults
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([ClipboardItem].self, from: data) {
                history = decoded
                print("✓ Loaded \(history.count) items from clipboard history")
            }
        }
    }
}

// MARK: - ClipboardItem Model

struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    let plainTextPreview: String  // Truncated text for display (max 200 chars)
    let fullText: String?         // Full text stored separately for large content
    let rtfData: Data?            // Rich Text Format data (preserves formatting)
    let htmlData: Data?           // HTML data (for web content)
    let timestamp: Date
    var isPinned: Bool

    // Constants for memory optimization
    private static let maxPreviewLength = 200
    private static let largeTextThreshold = 500 // Characters

    init(plainTextPreview: String, rtfData: Data? = nil, htmlData: Data? = nil, timestamp: Date, isPinned: Bool = false) {
        self.id = UUID()

        // Memory optimization: Truncate preview if text is large
        if plainTextPreview.count > Self.maxPreviewLength {
            self.plainTextPreview = String(plainTextPreview.prefix(Self.maxPreviewLength))
            // Store full text only if it's reasonably sized (not multi-MB)
            if plainTextPreview.count < 1_000_000 { // Max 1MB of text
                self.fullText = plainTextPreview
            } else {
                // For extremely large text, only keep preview + RTF data
                self.fullText = nil
                print("⚠️ Extremely large text truncated (\(plainTextPreview.count) chars)")
            }
        } else {
            self.plainTextPreview = plainTextPreview
            self.fullText = nil // No need to duplicate small text
        }

        self.rtfData = rtfData
        self.htmlData = htmlData
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    // MARK: - Legacy Support (for backward compatibility)

    /// Legacy initializer for backward compatibility with old plain-text-only items
    init(text: String, timestamp: Date, isPinned: Bool = false) {
        self.id = UUID()

        // Apply same truncation logic as main initializer
        if text.count > Self.maxPreviewLength {
            self.plainTextPreview = String(text.prefix(Self.maxPreviewLength))
            if text.count < 1_000_000 {
                self.fullText = text
            } else {
                self.fullText = nil
            }
        } else {
            self.plainTextPreview = text
            self.fullText = nil
        }

        self.rtfData = nil
        self.htmlData = nil
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    // MARK: - Computed Properties

    /// For backward compatibility - returns plainTextPreview
    var text: String {
        return plainTextPreview
    }

    /// Returns the full text for pasting (uses fullText if available, otherwise preview)
    var textForPasting: String {
        return fullText ?? plainTextPreview
    }

    /// Indicates if this item has rich formatting
    var hasRichFormatting: Bool {
        return rtfData != nil || htmlData != nil
    }

    // MARK: - Display Helpers

    /// Returns a truncated version of the text for display in menus
    func displayText(maxLength: Int = 30) -> String {
        if plainTextPreview.count > maxLength {
            return String(plainTextPreview.prefix(maxLength)) + "..."
        }
        return plainTextPreview
    }

    /// Returns a single-line version (replaces newlines with spaces)
    func singleLineText(maxLength: Int = 30) -> String {
        let singleLine = plainTextPreview.replacingOccurrences(of: "\n", with: " ")
                             .replacingOccurrences(of: "\r", with: " ")
        if singleLine.count > maxLength {
            return String(singleLine.prefix(maxLength)) + "..."
        }
        return singleLine
    }
}
