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
    private let userDefaultsKey = JoyaFixConstants.UserDefaultsKeys.clipboardHistory
    private let dataDirectory: URL
    
    // Migration flag
    private let migrationKey = "ClipboardHistoryMigrationCompleted"

    private var maxHistoryCount: Int {
        return settings.maxHistoryCount
    }

    // MARK: - Initialization

    private init() {
        // Create directory for clipboard data files (RTF/HTML)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDirectory = appSupport.appendingPathComponent(JoyaFixConstants.FilePaths.clipboardDataDirectory, isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Load history (before migration)
        loadHistory()
        
        // Migrate old data if needed
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            migrateOldHistory()
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        
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

        // Save RTF/HTML to disk and get paths
        var rtfDataPath: String? = nil
        var htmlDataPath: String? = nil
        
        if let rtf = rtfData {
            rtfDataPath = saveRichData(rtf, type: .rtf)
        }
        
        if let html = htmlData {
            htmlDataPath = saveRichData(html, type: .html)
        }

        return ClipboardItem(
            plainTextPreview: plainText,
            rtfData: nil,  // Don't store in struct, only on disk
            htmlData: nil,  // Don't store in struct, only on disk
            timestamp: Date(),
            isPinned: false,
            rtfDataPath: rtfDataPath,
            htmlDataPath: htmlDataPath
        )
    }
    
    // MARK: - File Storage
    
    /// Rich data type for file storage
    private enum RichDataType {
        case rtf
        case html
        
        var fileExtension: String {
            switch self {
            case .rtf: return "rtf"
            case .html: return "html"
            }
        }
    }
    
    /// Saves RTF/HTML data to disk and returns the file path
    private func saveRichData(_ data: Data, type: RichDataType) -> String? {
        let fileName = "\(UUID().uuidString).\(type.fileExtension)"
        let fileURL = dataDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            print("✓ Saved \(type.fileExtension.uppercased()) data to disk: \(fileURL.path) (\(fileSize) bytes)")
            return fileURL.path
        } catch {
            print("❌ Failed to save \(type.fileExtension.uppercased()) data to disk: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Loads RTF/HTML data from disk
    private func loadRichData(from path: String) -> Data? {
        guard FileManager.default.fileExists(atPath: path) else {
            print("⚠️ Rich data file not found: \(path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            print("✓ Loaded rich data from disk: \(path) (\(data.count) bytes)")
            return data
        } catch {
            print("❌ Failed to load rich data from disk: \(error.localizedDescription)")
            return nil
        }
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

        let formatInfo = (item.rtfDataPath != nil || item.rtfData != nil) ? " [RTF]" : ""
        print("📋 Added to clipboard history: \(item.plainTextPreview.prefix(30))...\(formatInfo)")
    }

    /// Clears all clipboard history (optionally keeping pinned items)
    func clearHistory(keepPinned: Bool = false) {
        // Delete files from disk for removed items
        let itemsToRemove: [ClipboardItem]
        if keepPinned {
            itemsToRemove = history.filter { !$0.isPinned }
            history.removeAll { !$0.isPinned }
            print("🗑️ Clipboard history cleared (kept pinned items)")
        } else {
            itemsToRemove = history
            history.removeAll()
            print("🗑️ Clipboard history cleared")
        }
        
        // Clean up files
        for item in itemsToRemove {
            if let rtfPath = item.rtfDataPath {
                try? FileManager.default.removeItem(atPath: rtfPath)
            }
            if let htmlPath = item.htmlDataPath {
                try? FileManager.default.removeItem(atPath: htmlPath)
            }
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
        // Delete files from disk
        if let rtfPath = item.rtfDataPath {
            try? FileManager.default.removeItem(atPath: rtfPath)
        }
        if let htmlPath = item.htmlDataPath {
            try? FileManager.default.removeItem(atPath: htmlPath)
        }
        
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
            // Try to load from disk first, then fall back to legacy data
            if let rtfPath = item.rtfDataPath, let rtfData = loadRichData(from: rtfPath) {
                pasteboard.setData(rtfData, forType: .rtf)
                writtenTypes.append(.rtf)
                print("📝 Restored RTF data to clipboard (\(rtfData.count) bytes)")
            } else if let legacyRtfData = item.rtfData {
                // Legacy support: Use old rtfData if path not available
                pasteboard.setData(legacyRtfData, forType: .rtf)
                writtenTypes.append(.rtf)
                print("📝 Restored RTF data to clipboard (legacy, \(legacyRtfData.count) bytes)")
            }

            // Write HTML data if available
            if let htmlPath = item.htmlDataPath, let htmlData = loadRichData(from: htmlPath) {
                pasteboard.setData(htmlData, forType: .html)
                writtenTypes.append(.html)
                print("🌐 Restored HTML data to clipboard")
            } else if let legacyHtmlData = item.htmlData {
                // Legacy support: Use old htmlData if path not available
                pasteboard.setData(legacyHtmlData, forType: .html)
                writtenTypes.append(.html)
                print("🌐 Restored HTML data to clipboard (legacy)")
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
    
    // MARK: - Migration
    
    /// Migrates old clipboard history from UserDefaults (with embedded Data) to disk-based storage
    private func migrateOldHistory() {
        print("🔄 Starting clipboard history migration...")
        
        var migratedCount = 0
        var migratedItems: [ClipboardItem] = []
        
        for item in history {
            var updatedItem = item
            
            // Migrate RTF data if present
            if let rtfData = item.rtfData, item.rtfDataPath == nil {
                if let rtfPath = saveRichData(rtfData, type: .rtf) {
                    // Create new item with path instead of data
                    updatedItem = ClipboardItem(
                        plainTextPreview: item.plainTextPreview,
                        rtfData: nil,
                        htmlData: item.htmlData,  // Keep for now, migrate below
                        timestamp: item.timestamp,
                        isPinned: item.isPinned,
                        rtfDataPath: rtfPath,
                        htmlDataPath: item.htmlDataPath
                    )
                    migratedCount += 1
                }
            }
            
            // Migrate HTML data if present
            if let htmlData = item.htmlData, item.htmlDataPath == nil {
                if let htmlPath = saveRichData(htmlData, type: .html) {
                    // Create new item with path instead of data
                    updatedItem = ClipboardItem(
                        plainTextPreview: updatedItem.plainTextPreview,
                        rtfData: nil,
                        htmlData: nil,  // Clear legacy data
                        timestamp: updatedItem.timestamp,
                        isPinned: updatedItem.isPinned,
                        rtfDataPath: updatedItem.rtfDataPath,
                        htmlDataPath: htmlPath
                    )
                    if updatedItem.rtfDataPath == nil {
                        migratedCount += 1
                    }
                }
            }
            
            migratedItems.append(updatedItem)
        }
        
        if migratedCount > 0 {
            history = migratedItems
            saveHistory()
            print("✓ Migration completed: \(migratedCount) items migrated to disk storage")
        } else {
            print("ℹ️ No items needed migration")
        }
    }
}

// MARK: - ClipboardItem Model

struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    let plainTextPreview: String  // Truncated text for display (max 200 chars)
    let fullText: String?         // Full text stored separately for large content
    let rtfDataPath: String?     // Path to RTF file on disk (replaces rtfData)
    let htmlDataPath: String?     // Path to HTML file on disk (replaces htmlData)
    let timestamp: Date
    var isPinned: Bool
    
    // Legacy support: For migration from old format
    let rtfData: Data?    // Only used during migration, not stored (internal for migration)
    let htmlData: Data?   // Only used during migration, not stored (internal for migration)

    // Constants for memory optimization
    private static let maxPreviewLength = 200
    private static let largeTextThreshold = 500 // Characters

    init(plainTextPreview: String, rtfData: Data? = nil, htmlData: Data? = nil, timestamp: Date, isPinned: Bool = false, rtfDataPath: String? = nil, htmlDataPath: String? = nil) {
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

        // Store paths (preferred) or legacy data (for migration)
        self.rtfDataPath = rtfDataPath
        self.htmlDataPath = htmlDataPath
        self.rtfData = rtfData  // Legacy - only for migration
        self.htmlData = htmlData  // Legacy - only for migration
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

        self.rtfDataPath = nil
        self.htmlDataPath = nil
        self.rtfData = nil
        self.htmlData = nil
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    // MARK: - Codable Support (Custom Encoding/Decoding)
    
    enum CodingKeys: String, CodingKey {
        case id, plainTextPreview, fullText, rtfDataPath, htmlDataPath, timestamp, isPinned
        // Legacy keys for migration
        case rtfData, htmlData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        plainTextPreview = try container.decode(String.self, forKey: .plainTextPreview)
        fullText = try container.decodeIfPresent(String.self, forKey: .fullText)
        rtfDataPath = try container.decodeIfPresent(String.self, forKey: .rtfDataPath)
        htmlDataPath = try container.decodeIfPresent(String.self, forKey: .htmlDataPath)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        
        // Legacy support: Decode old rtfData/htmlData if present (for migration)
        rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        htmlData = try container.decodeIfPresent(Data.self, forKey: .htmlData)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(plainTextPreview, forKey: .plainTextPreview)
        try container.encodeIfPresent(fullText, forKey: .fullText)
        try container.encodeIfPresent(rtfDataPath, forKey: .rtfDataPath)
        try container.encodeIfPresent(htmlDataPath, forKey: .htmlDataPath)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
        // Don't encode legacy rtfData/htmlData - they should be migrated to paths
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
        return rtfDataPath != nil || htmlDataPath != nil || rtfData != nil || htmlData != nil
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
