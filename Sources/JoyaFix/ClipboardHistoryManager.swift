import Cocoa
import Foundation
import Carbon

@MainActor
class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    // MARK: - Published Properties

    @Published private(set) var history: [ClipboardItem] = []

    // MARK: - Private Properties

    private var pollTimer: Timer?
    private var cleanupTimer: Timer?
    private var lastChangeCount: Int = 0
    private var lastCopiedText: String?
    private var isInternalWrite: Bool = false // Flag to prevent internal writes from being recorded

    // Configuration
    private let settings = SettingsManager.shared
    // OPTIMIZATION: Poll at 0.5s with changeCount check to only process when clipboard actually changes
    private let pollInterval: TimeInterval = 0.5
    private let userDefaultsKey = JoyaFixConstants.UserDefaultsKeys.clipboardHistory
    private let dataDirectory: URL
    
    // OPTIMIZATION: Track last clipboard content to avoid unnecessary processing
    private var lastClipboardHash: String?
    
    // Migration flags
    private let migrationKey = "ClipboardHistoryMigrationCompleted"
    private let databaseMigrationKey = "ClipboardHistoryDatabaseMigrationCompleted"
    
    // Database manager for persistent storage (replaces UserDefaults)
    private let databaseManager = HistoryDatabaseManager.shared
    
    private var maxHistoryCount: Int {
        return settings.maxHistoryCount
    }

    // MARK: - Initialization

    private init() {
        // Create directory for clipboard data files (RTF/HTML)
        // Use safe unwrap with fallback to temporary directory
        let appSupport: URL
        if let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            appSupport = supportDir
        } else {
            // Fallback to temporary directory if Application Support is unavailable
            appSupport = FileManager.default.temporaryDirectory
            Logger.clipboard("Application Support directory unavailable, using temp directory", level: .warning)
        }
        dataDirectory = appSupport.appendingPathComponent(JoyaFixConstants.FilePaths.clipboardDataDirectory, isDirectory: true)

        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.clipboard("Failed to create clipboard data directory: \(error.localizedDescription)", level: .warning)
        }
        
        // Load history (before migration) - must be on main thread
        // Use DispatchQueue.main.sync to ensure synchronous loading during init
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                // CRITICAL FIX: Migrate to database first (one-time migration)
                if !UserDefaults.standard.bool(forKey: databaseMigrationKey) {
                    migrateToDatabase()
                    UserDefaults.standard.set(true, forKey: databaseMigrationKey)
                }
                
                loadHistory()
                // Migrate old data if needed (file-based migration)
                if !UserDefaults.standard.bool(forKey: migrationKey) {
                    migrateOldHistory()
                    UserDefaults.standard.set(true, forKey: migrationKey)
                }
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    // CRITICAL FIX: Migrate to database first (one-time migration)
                    if !UserDefaults.standard.bool(forKey: databaseMigrationKey) {
                        migrateToDatabase()
                        UserDefaults.standard.set(true, forKey: databaseMigrationKey)
                    }
                    
                    loadHistory()
                    // Migrate old data if needed (file-based migration)
                    if !UserDefaults.standard.bool(forKey: migrationKey) {
                        migrateOldHistory()
                        UserDefaults.standard.set(true, forKey: migrationKey)
                    }
                }
            }
        }
        
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Start/Stop Monitoring

    /// Starts monitoring the clipboard for changes
    func startMonitoring() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForClipboardChanges()
            }
        }
        Logger.clipboard("Clipboard monitoring started", level: .info)

        // Start scheduled disk cleanup (runs every 24 hours)
        startScheduledCleanup()
    }

    /// Stops monitoring the clipboard
    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        Logger.clipboard("Clipboard monitoring stopped", level: .info)
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

        // OPTIMIZATION: Quick hash check to avoid processing duplicate content
        if let currentText = NSPasteboard.general.string(forType: .string) {
            let currentHash = String(currentText.hashValue)
            if currentHash == lastClipboardHash {
                return  // Same content, skip processing
            }
            lastClipboardHash = currentHash
        }

        // All subsequent code runs on the MainActor because the class is isolated.
        
        guard let item = captureClipboardContent() else { return }
        
        // Check if this is an image item.
        // `captureImageContent` which is called inside `captureClipboardContent` already
        // triggers the async saving process for images.
        let isImageItem = item.rtfData == nil && item.htmlData == nil && item.imagePath == nil &&
                          item.plainTextPreview == "Image"
        if isImageItem {
            return
        }
        
        // Ignore empty strings
        guard !item.plainTextPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Get full text for comparison.
        let itemFullText = item.textForPasting

        // Strict deduplication: Check against all items in history.
        let isDuplicate = history.contains { historyItem in
            historyItem.textForPasting == itemFullText
        }

        if isDuplicate {
            Logger.clipboard("Skipping duplicate: \(item.plainTextPreview.prefix(30))...", level: .info)
            return
        }

        // Process and save heavy data asynchronously, then add to history.
        processAndSaveItem(item)
        lastCopiedText = itemFullText
    }

    // גרסה משופרת ל-captureClipboardContent (רצה ברקע)
    /// Captures the current clipboard content including RTF data and images (synchronous, must be called on main thread)
    private func captureClipboardContent() -> ClipboardItem? {
        // קריאה מהלוח חייבת להיות ב-Main Thread
        let pasteboard = NSPasteboard.general
        
        // Check for images first (TIFF or PNG) - handle separately with async save
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            return captureImageContent(imageData: imageData, pasteboard: pasteboard)
        }
        
        // Try to get plain text (required for text items)
        guard let plainText = pasteboard.string(forType: .string) else {
            return nil
        }
        
        // שליפת הנתונים הכבדים (Data) ב-Main Thread, אך השמירה תהיה אחר כך
        let rtfData = pasteboard.data(forType: .rtfd) ?? pasteboard.data(forType: .rtf)
        let htmlData = pasteboard.data(forType: .html)
        
        if let rtf = rtfData {
            Logger.clipboard("Captured RTF data (\(rtf.count) bytes)", level: .debug)
        }
        if let html = htmlData {
            Logger.clipboard("Captured HTML data (\(html.count) bytes)", level: .debug)
        }
        
        // Check for password/sensitive data indicators from various password managers
        let pasteboardTypes = pasteboard.types ?? []
        let sensitiveDataTypes: Set<NSPasteboard.PasteboardType> = [
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
            NSPasteboard.PasteboardType("com.agilebits.onepassword"),
            NSPasteboard.PasteboardType("com.lastpass.lastpass"),
            NSPasteboard.PasteboardType("com.dashlane.dashlane"),
            NSPasteboard.PasteboardType("com.bitwarden.desktop"),
            NSPasteboard.PasteboardType("org.keepassx.keepassxc")
        ]
        let isSensitive = pasteboardTypes.contains(where: { sensitiveDataTypes.contains($0) })
        
        // יצירת פריט זמני (ללא נתיבים עדיין)
        return ClipboardItem(
            plainTextPreview: plainText,
            rtfData: rtfData, // נשתמש בזה זמנית להעברה
            htmlData: htmlData, // נשתמש בזה זמנית להעברה
            timestamp: Date(),
            isPinned: false,
            rtfDataPath: nil,
            htmlDataPath: nil,
            imagePath: nil,
            isSensitive: isSensitive
        )
    }
    
    // פונקציה חדשה לטיפול אסינכרוני
    /// Processes and saves heavy data (RTF/HTML) to disk asynchronously, then adds item to history
    private func processAndSaveItem(_ tempItem: ClipboardItem) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var rtfPath: String?
            var htmlPath: String?
            
            // שמירה כבדה לדיסק - רצה ברקע!
            if let rtf = tempItem.rtfData {
                rtfPath = self.saveRichData(rtf, type: .rtf)
            }
            if let html = tempItem.htmlData {
                htmlPath = self.saveRichData(html, type: .html)
            }
            
            let finalItem = ClipboardItem(
                plainTextPreview: tempItem.plainTextPreview,
                rtfData: nil, htmlData: nil, // מנקים את המידע מהזיכרון
                timestamp: tempItem.timestamp,
                isPinned: false,
                rtfDataPath: rtfPath,
                htmlDataPath: htmlPath,
                imagePath: tempItem.imagePath,
                isSensitive: tempItem.isSensitive
            )
            
            // חזרה ל-Main Thread לעדכון ה-UI
            DispatchQueue.main.async {
                self.addToHistory(finalItem)
            }
        }
    }
    
    /// Captures image content from clipboard (synchronous, must be called on main thread)
    private func captureImageContent(imageData: Data, pasteboard: NSPasteboard) -> ClipboardItem? {
        // Check for password/sensitive data indicators (on main thread)
        let pasteboardTypes = pasteboard.types ?? []
        let isSensitive = pasteboardTypes.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) ||
                         pasteboardTypes.contains(NSPasteboard.PasteboardType("com.agilebits.onepassword"))
        
        // Get text representation if available (for image descriptions) - on main thread
        let textPreview = pasteboard.string(forType: .string) ?? "Image"
        
        // Create temporary item - image will be saved asynchronously
        // We'll use processAndSaveImageItem for images since they need special handling
        let tempItem = ClipboardItem(
            plainTextPreview: textPreview,
            rtfData: nil,
            htmlData: nil,
            timestamp: Date(),
            isPinned: false,
            rtfDataPath: nil,
            htmlDataPath: nil,
            imagePath: nil, // Will be set after async save
            isSensitive: isSensitive
        )
        
        // Process image separately
        processAndSaveImageItem(tempItem, imageData: imageData)
        return tempItem
    }
    
    /// Processes and saves image data to disk asynchronously, then adds item to history
    private func processAndSaveImageItem(_ tempItem: ClipboardItem, imageData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Save image to disk on background thread
            let imagePath = self.saveImageData(imageData)
            
            guard let savedImagePath = imagePath else {
                Logger.clipboard("Failed to save image to disk", level: .error)
                return
            }
            
            let finalItem = ClipboardItem(
                plainTextPreview: tempItem.plainTextPreview,
                rtfData: nil,
                htmlData: nil,
                timestamp: tempItem.timestamp,
                isPinned: false,
                rtfDataPath: nil,
                htmlDataPath: nil,
                imagePath: savedImagePath,
                isSensitive: tempItem.isSensitive
            )
            
            // חזרה ל-Main Thread לעדכון ה-UI ולבדיקת כפילויות
            DispatchQueue.main.async {
                // Check for duplicates (compare by image path for images)
                let isDuplicate = self.history.contains { historyItem in
                    historyItem.imagePath == savedImagePath
                }
                
                if isDuplicate {
                    Logger.clipboard("Skipping duplicate image: \(tempItem.plainTextPreview.prefix(30))...", level: .info)
                    // Delete the saved image file since it's a duplicate
                    try? FileManager.default.removeItem(atPath: savedImagePath)
                    return
                }
                
                self.addToHistory(finalItem)
                self.lastCopiedText = finalItem.textForPasting
            }
        }
    }
    
    // MARK: - File Storage
    
    /// Rich data type for file storage
    private enum RichDataType {
        case rtf
        case html
        case image
        
        var fileExtension: String {
            switch self {
            case .rtf: return "rtf"
            case .html: return "html"
            case .image: return "png"
            }
        }
    }
    
    /// Saves RTF/HTML data to disk asynchronously on background thread
    /// Completion handler is called on the same background queue (not MainActor)
    private func saveRichData(_ data: Data, type: RichDataType, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileName = "\(UUID().uuidString).\(type.fileExtension)"
            let fileURL = self.dataDirectory.appendingPathComponent(fileName)
            
            do {
                try data.write(to: fileURL)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                Logger.clipboard("Saved \(type.fileExtension.uppercased()) data to disk: \(fileURL.path) (\(fileSize) bytes)", level: .debug)
                completion(fileURL.path)
            } catch {
                Logger.clipboard("Failed to save \(type.fileExtension.uppercased()) data to disk: \(error.localizedDescription)", level: .error)
                completion(nil)
            }
        }
    }
    
    /// Saves RTF/HTML data to disk synchronously (for use in background thread)
    /// Returns the file path or nil on failure
    private func saveRichData(_ data: Data, type: RichDataType) -> String? {
        let fileName = "\(UUID().uuidString).\(type.fileExtension)"
        let fileURL = self.dataDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            Logger.clipboard("Saved \(type.fileExtension.uppercased()) data to disk: \(fileURL.path) (\(fileSize) bytes)", level: .debug)
            return fileURL.path
        } catch {
            Logger.clipboard("Failed to save \(type.fileExtension.uppercased()) data to disk: \(error.localizedDescription)", level: .error)
            return nil
        }
    }
    
    /// Loads RTF/HTML data from disk
    private func loadRichData(from path: String) -> Data? {
        guard FileManager.default.fileExists(atPath: path) else {
            Logger.clipboard("Rich data file not found: \(path)", level: .warning)
            return nil
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            Logger.clipboard("Loaded rich data from disk: \(path) (\(data.count) bytes)", level: .debug)
            return data
        } catch {
            Logger.clipboard("Failed to load rich data from disk: \(error.localizedDescription)", level: .error)
            return nil
        }
    }
    
    /// Saves image data to disk asynchronously on background thread
    /// Completion handler is called on the same background queue (not MainActor)
    private func saveImageData(_ data: Data, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileName = "\(UUID().uuidString).png"
            let fileURL = self.dataDirectory.appendingPathComponent(fileName)
            
            do {
                try data.write(to: fileURL)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                Logger.clipboard("Saved image data to disk: \(fileURL.path) (\(fileSize) bytes)", level: .debug)
                completion(fileURL.path)
            } catch {
                Logger.clipboard("Failed to save image data to disk: \(error.localizedDescription)", level: .error)
                completion(nil)
            }
        }
    }
    
    /// Saves image data to disk synchronously (for use in background thread)
    /// Returns the file path or nil on failure
    private func saveImageData(_ data: Data) -> String? {
        let fileName = "\(UUID().uuidString).png"
        let fileURL = self.dataDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            Logger.clipboard("Saved image data to disk: \(fileURL.path) (\(fileSize) bytes)", level: .debug)
            return fileURL.path
        } catch {
            Logger.clipboard("Failed to save image data to disk: \(error.localizedDescription)", level: .error)
            return nil
        }
    }

    // MARK: - History Management

    /// Adds a new item to the clipboard history
    /// MUST be called on MainActor to ensure thread safety for @Published history
    @MainActor
    func addToHistory(_ item: ClipboardItem) {
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
            // Get items that will be dropped (from index maxHistoryCount to the end)
            let itemsToRemove = Array(newUnpinnedItems.suffix(newUnpinnedItems.count - maxHistoryCount))
            
            // מחיקת קבצים של פריטים שנזרקים מהרשימה!
            for oldItem in itemsToRemove {
                if let path = oldItem.rtfDataPath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                if let path = oldItem.htmlDataPath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                if let path = oldItem.imagePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            
            // Truncate to maxHistoryCount
            newUnpinnedItems = Array(newUnpinnedItems.prefix(maxHistoryCount))
        }

        // Reconstruct history: pinned items first, then unpinned
        history = pinnedItems + newUnpinnedItems

        // PERFORMANCE IMPROVEMENT: Save only the new item incrementally
        do {
            try databaseManager.saveClipboardItem(itemToAdd)
            // Also cleanup old items from database
            try databaseManager.deleteOldItems(keeping: maxHistoryCount)
            Logger.clipboard("Saved item to database (incremental)", level: .debug)
        } catch {
            Logger.database("Failed to save clipboard item: \(error.localizedDescription)", level: .error)
            showToast("Failed to save to database. Using fallback storage.", style: .warning, duration: 2.0)
            // Fallback to full save
            saveHistory()
        }

        let formatInfo = (item.rtfDataPath != nil || item.rtfData != nil) ? " [RTF]" : ""
        Logger.clipboard("Added to clipboard history: \(item.plainTextPreview.prefix(30))...\(formatInfo)", level: .debug)
    }

    /// Clears all clipboard history (optionally keeping pinned items)
    /// MUST be called on MainActor to ensure thread safety for @Published history
    @MainActor
    func clearHistory(keepPinned: Bool = false) {
        // Delete files from disk for removed items
        let itemsToRemove: [ClipboardItem]
        if keepPinned {
            itemsToRemove = history.filter { !$0.isPinned }
            history.removeAll { !$0.isPinned }
            Logger.clipboard("Clipboard history cleared (kept pinned items)", level: .info)
        } else {
            itemsToRemove = history
            history.removeAll()
            Logger.clipboard("Clipboard history cleared", level: .info)
        }
        
        // Clean up files
        for item in itemsToRemove {
            if let rtfPath = item.rtfDataPath {
                try? FileManager.default.removeItem(atPath: rtfPath)
            }
            if let htmlPath = item.htmlDataPath {
                try? FileManager.default.removeItem(atPath: htmlPath)
            }
            if let imagePath = item.imagePath {
                try? FileManager.default.removeItem(atPath: imagePath)
            }
        }
        
        lastCopiedText = nil
        saveHistory()
    }

    /// Toggles the pin status of a clipboard item
    /// MUST be called on MainActor to ensure thread safety for @Published history
    @MainActor
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
            Logger.clipboard("Pinned: \(updatedItem.plainTextPreview.prefix(30))...", level: .debug)
        } else {
            // Insert at the start of unpinned section (right after pinned items)
            let pinnedCount = history.filter { $0.isPinned }.count
            history.insert(updatedItem, at: pinnedCount)
            Logger.clipboard("Unpinned: \(updatedItem.plainTextPreview.prefix(30))...", level: .debug)
        }

        // Persist changes
        saveHistory()
    }

    /// Deletes a specific clipboard item from history
    /// MUST be called on MainActor to ensure thread safety for @Published history
    @MainActor
    func deleteItem(_ item: ClipboardItem) {
        // Delete files from disk
        if let rtfPath = item.rtfDataPath {
            try? FileManager.default.removeItem(atPath: rtfPath)
        }
        if let htmlPath = item.htmlDataPath {
            try? FileManager.default.removeItem(atPath: htmlPath)
        }
        if let imagePath = item.imagePath {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        
        history.removeAll { $0.id == item.id }
        saveHistory()
        Logger.clipboard("Deleted from history: \(item.plainTextPreview.prefix(30))...", level: .debug)
    }

    // MARK: - Paste from History

    /// Writes the selected history item back to the clipboard and optionally pastes it
    func pasteItem(_ item: ClipboardItem, simulatePaste: Bool = true, formattingOption: PasteFormattingOption = .normal) {
        // Mark this as an internal write to prevent it from being re-recorded
        isInternalWrite = true

        // Write to clipboard with proper formatting
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var writtenTypes: [NSPasteboard.PasteboardType] = []

        // Get HTML data if available for markdown conversion
        var htmlData: Data? = nil
        if let htmlPath = item.htmlDataPath {
            htmlData = loadRichData(from: htmlPath)
        } else if let legacyHtmlData = item.htmlData {
            htmlData = legacyHtmlData
        }

        // Apply formatting based on option
        let formattedText = PasteFormattingOption.format(
            item.textForPasting,
            option: formattingOption,
            htmlData: htmlData
        )

        if formattingOption != .normal {
            // Apply formatting - write as plain text only
            pasteboard.setString(formattedText, forType: .string)
            writtenTypes.append(.string)
            Logger.clipboard("Restored formatted text to clipboard (\(formattingOption)): \(formattedText.prefix(30))...", level: .debug)
        } else {
            // Write image if available
            if let imagePath = item.imagePath, let imageData = loadRichData(from: imagePath) {
                pasteboard.setData(imageData, forType: .tiff)
                writtenTypes.append(.tiff)
                Logger.clipboard("Restored image to clipboard (\(imageData.count) bytes)", level: .debug)
            }
            
            // Write RTF data if available (preserves formatting)
            // Try to load from disk first, then fall back to legacy data
            if let rtfPath = item.rtfDataPath, let rtfData = loadRichData(from: rtfPath) {
                pasteboard.setData(rtfData, forType: .rtf)
                writtenTypes.append(.rtf)
                Logger.clipboard("Restored RTF data to clipboard (\(rtfData.count) bytes)", level: .debug)
            } else if let legacyRtfData = item.rtfData {
                // Legacy support: Use old rtfData if path not available
                pasteboard.setData(legacyRtfData, forType: .rtf)
                writtenTypes.append(.rtf)
                Logger.clipboard("Restored RTF data to clipboard (legacy, \(legacyRtfData.count) bytes)", level: .debug)
            }

            // Write HTML data if available
            if let htmlPath = item.htmlDataPath, let htmlData = loadRichData(from: htmlPath) {
                pasteboard.setData(htmlData, forType: .html)
                writtenTypes.append(.html)
                Logger.clipboard("Restored HTML data to clipboard", level: .debug)
            } else if let legacyHtmlData = item.htmlData {
                // Legacy support: Use old htmlData if path not available
                pasteboard.setData(legacyHtmlData, forType: .html)
                writtenTypes.append(.html)
                Logger.clipboard("Restored HTML data to clipboard (legacy)", level: .debug)
            }

            // Always write plain text as fallback (use full text if available)
            pasteboard.setString(item.textForPasting, forType: .string)
            writtenTypes.append(.string)

            let typesInfo = writtenTypes.map { $0.rawValue }.joined(separator: ", ")
            Logger.clipboard("Restored to clipboard: \(item.plainTextPreview.prefix(30))... [Types: \(typesInfo)]", level: .debug)
        }

        // Optionally simulate Cmd+V to paste immediately
        if simulatePaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.simulatePaste()
            }
        }
    }
    
    /// Legacy support: maintain backward compatibility with plainTextOnly parameter
    func pasteItem(_ item: ClipboardItem, simulatePaste: Bool = true, plainTextOnly: Bool = false) {
        let option: PasteFormattingOption = plainTextOnly ? .plainText : .normal
        pasteItem(item, simulatePaste: simulatePaste, formattingOption: option)
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

    /// Saves clipboard history to database (replaces UserDefaults)
    /// MUST be called on MainActor to ensure thread safety for @Published history
    /// Includes robust error handling with fallback to UserDefaults
    @MainActor
    private func saveHistory() {
        // CRITICAL FIX: Save to database instead of UserDefaults
        do {
            try databaseManager.saveClipboardHistory(history)
            Logger.clipboard("Saved \(history.count) items to database", level: .debug)
            
            // Clear fallback data if database save succeeded
            if UserDefaults.standard.data(forKey: userDefaultsKey) != nil {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        } catch {
            // Detailed error logging
            let errorDescription = error.localizedDescription
            let isLocked = DatabaseError.isDatabaseLocked(error)
            let isIOError = DatabaseError.isIOError(error)
            
            if isLocked {
                Logger.clipboard("Database is locked - using fallback to UserDefaults. Error: \(errorDescription)", level: .warning)
            } else if isIOError {
                Logger.clipboard("Database I/O error - using fallback to UserDefaults. Error: \(errorDescription)", level: .warning)
            } else {
                Logger.clipboard("Failed to save clipboard history to database: \(errorDescription)", level: .error)
            }

            // Fallback to UserDefaults if database fails (Insurance Policy)
            let encoder = JSONEncoder()
            do {
                let encoded = try encoder.encode(history)
                UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
                Logger.clipboard("Fallback: Saved \(history.count) items to UserDefaults (\(encoded.count) bytes)", level: .warning)

                // Log fallback status for monitoring
                UserDefaults.standard.set(true, forKey: "ClipboardHistoryFallbackActive")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ClipboardHistoryFallbackTimestamp")
            } catch {
                Logger.clipboard("CRITICAL: Failed to save to both database and UserDefaults! Encoding error: \(error.localizedDescription)", level: .critical)
            }
        }
    }

    /// Loads clipboard history from database (replaces UserDefaults)
    /// MUST be called on MainActor to ensure thread safety for @Published history
    /// Includes robust error handling with fallback to UserDefaults
    @MainActor
    private func loadHistory() {
        // CRITICAL FIX: Load from database instead of UserDefaults
        // Add retry logic for better reliability
        var retryCount = 0
        let maxRetries = 3
        
        func attemptLoad() {
            do {
                let items = try databaseManager.loadClipboardHistory()
                history = items
                Logger.clipboard("Loaded \(history.count) items from database", level: .info)
                
                // Check if we have fallback data that needs to be migrated back
                if UserDefaults.standard.bool(forKey: "ClipboardHistoryFallbackActive") {
                    Logger.clipboard("Detected fallback data - attempting to migrate back to database...", level: .info)
                    // Try to save current database state, then merge with fallback if needed
                    if let fallbackData = UserDefaults.standard.data(forKey: userDefaultsKey) {
                        let decoder = JSONDecoder()
                        if let fallbackItems = try? decoder.decode([ClipboardItem].self, from: fallbackData) {
                            // Merge fallback items with database items (avoid duplicates)
                            var mergedItems = items
                            for fallbackItem in fallbackItems {
                                if !mergedItems.contains(where: { $0.id == fallbackItem.id }) {
                                    mergedItems.append(fallbackItem)
                                }
                            }
                            // Sort by timestamp
                            mergedItems.sort { $0.timestamp > $1.timestamp }
                            history = mergedItems
                            
                            // Try to save merged data back to database
                            do {
                                try databaseManager.saveClipboardHistory(mergedItems)
                                // Clear fallback data after successful migration
                                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                                UserDefaults.standard.removeObject(forKey: "ClipboardHistoryFallbackActive")
                                UserDefaults.standard.removeObject(forKey: "ClipboardHistoryFallbackTimestamp")
                                Logger.clipboard("Successfully migrated fallback data back to database", level: .info)
                            } catch {
                                Logger.clipboard("Could not migrate fallback data back to database: \(error.localizedDescription)", level: .warning)
                            }
                        }
                    }
                }
            } catch {
                // Retry logic for transient errors
                if retryCount < maxRetries {
                    retryCount += 1
                    Logger.clipboard("Retry \(retryCount)/\(maxRetries) loading history", level: .warning)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        attemptLoad()
                    }
                    return
                }
                
                // Detailed error logging
                let errorDescription = error.localizedDescription
                let isLocked = DatabaseError.isDatabaseLocked(error)
                let isIOError = DatabaseError.isIOError(error)
                
                if isLocked {
                    Logger.clipboard("Database is locked - using fallback from UserDefaults", level: .warning)
                    showToast("Database temporarily locked. Using fallback storage.", style: .warning, duration: 2.0)
                } else if isIOError {
                    Logger.clipboard("Database I/O error - using fallback from UserDefaults", level: .warning)
                    showToast("Database I/O error. Using fallback storage.", style: .warning, duration: 2.0)
                } else {
                    Logger.clipboard("Failed to load clipboard history from database: \(errorDescription)", level: .error)
                    showToast("Failed to load clipboard history. Using fallback.", style: .error, duration: 3.0)
                }
                
                // Fallback to UserDefaults if database fails
                if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
                    let decoder = JSONDecoder()
                    do {
                        let decoded = try decoder.decode([ClipboardItem].self, from: data)
                        history = decoded
                        Logger.clipboard("Fallback: Loaded \(history.count) items from UserDefaults", level: .info)
                        
                        // Mark fallback as active
                        UserDefaults.standard.set(true, forKey: "ClipboardHistoryFallbackActive")
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ClipboardHistoryFallbackTimestamp")
                    } catch {
                        Logger.clipboard("CRITICAL: Failed to decode fallback data: \(error.localizedDescription)", level: .error)
                        history = []
                    }
                } else {
                    Logger.clipboard("No clipboard history found (first run)", level: .info)
                    history = []
                }
            }
        }
        
        attemptLoad()
    }
    
    /// Migrates clipboard history from UserDefaults to database (one-time migration)
    /// Includes corruption detection and safe error handling
    @MainActor
    private func migrateToDatabase() {
        Logger.clipboard("Migrating clipboard history from UserDefaults to database...", level: .info)
        
        let success = databaseManager.migrateClipboardHistoryFromUserDefaults()
        if success {
            // Reload from database after migration
            loadHistory()
        } else {
            Logger.clipboard("Migration returned false - keeping data in UserDefaults as fallback", level: .warning)
        }
    }
    
    // MARK: - Scheduled Cleanup
    
    /// Starts scheduled disk cleanup (runs every 24 hours)
    private func startScheduledCleanup() {
        // Run cleanup immediately on first start (after a short delay to ensure history is loaded)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds delay
            cleanupOrphanedFiles()
        }
        
        // Schedule periodic cleanup (every 24 hours)
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOrphanedFiles()
            }
        }
        Logger.clipboard("Scheduled disk cleanup started (runs every 24 hours)", level: .info)
    }
    
    // MARK: - Cleanup
    
    /// Cleans up orphaned files in the data directory that are not referenced in history
    /// This should be called after history is loaded to remove files that are no longer needed
    /// Runs on background thread to avoid blocking Main Thread
    @MainActor
    func cleanupOrphanedFiles() {
        // Collect all valid file paths from history (on MainActor)
        var validPaths = Set<String>()
        for item in history {
            if let rtfPath = item.rtfDataPath {
                validPaths.insert(rtfPath)
            }
            if let htmlPath = item.htmlDataPath {
                validPaths.insert(htmlPath)
            }
            if let imagePath = item.imagePath {
                validPaths.insert(imagePath)
            }
        }
        
        // Run cleanup on background thread to avoid blocking Main Thread
        let dataDir = dataDirectory
        Task.detached(priority: .utility) {
            // Get all files in the data directory (on background thread)
            let fileManager = FileManager.default
            guard let directoryContents = try? fileManager.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil, options: []) else {
                Logger.clipboard("Could not read data directory for cleanup", level: .warning)
                return
            }
            
            var deletedCount = 0
            var totalSizeDeleted: Int64 = 0
            
            // Check each file and delete if not in valid paths
            for fileURL in directoryContents {
                let filePath = fileURL.path
                
                // Skip if this file is referenced in history
                if validPaths.contains(filePath) {
                    continue
                }
                
                // Get file size before deletion for reporting
                if let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                   let fileSize = attributes[.size] as? Int64 {
                    totalSizeDeleted += fileSize
                }
                
                // Delete orphaned file
                do {
                    try fileManager.removeItem(at: fileURL)
                    deletedCount += 1
                    Logger.clipboard("Deleted orphaned file: \(fileURL.lastPathComponent)", level: .debug)
                } catch {
                    Logger.clipboard("Failed to delete orphaned file \(fileURL.lastPathComponent): \(error.localizedDescription)", level: .error)
                }
            }
            
            if deletedCount > 0 {
                let sizeInMB = Double(totalSizeDeleted) / (1024 * 1024)
                Logger.clipboard("Cleanup completed: Deleted \(deletedCount) orphaned file(s), freed \(String(format: "%.2f", sizeInMB)) MB", level: .info)
            } else {
                Logger.clipboard("Cleanup completed: No orphaned files found", level: .info)
            }
        }
    }
    
    // MARK: - Migration
    
    /// Migrates old clipboard history from UserDefaults (with embedded Data) to disk-based storage
    /// MUST be called on MainActor to ensure thread safety for @Published history
    @MainActor
    private func migrateOldHistory() {
        Logger.clipboard("Starting clipboard history migration...", level: .info)
        
        let group = DispatchGroup()
        var migratedCount = 0
        var migratedItems: [ClipboardItem] = []
        let itemsToMigrate = history
        
        for item in itemsToMigrate {
            var updatedItem = item
            var needsRTFMigration = false
            var needsHTMLMigration = false
            
            // Check what needs migration
            if let _ = item.rtfData, item.rtfDataPath == nil {
                needsRTFMigration = true
            }
            if let _ = item.htmlData, item.htmlDataPath == nil {
                needsHTMLMigration = true
            }
            
            // If no migration needed, just add the item
            if !needsRTFMigration && !needsHTMLMigration {
                migratedItems.append(updatedItem)
                continue
            }
            
            // Migrate RTF data if present (synchronous for migration)
            if needsRTFMigration, let rtfData = item.rtfData {
                group.enter()
                saveRichData(rtfData, type: .rtf) { rtfPath in
                    if let rtfPath = rtfPath {
                        updatedItem = ClipboardItem(
                            plainTextPreview: item.plainTextPreview,
                            rtfData: nil,
                            htmlData: item.htmlData,
                            timestamp: item.timestamp,
                            isPinned: item.isPinned,
                            rtfDataPath: rtfPath,
                            htmlDataPath: item.htmlDataPath,
                            imagePath: item.imagePath,
                            isSensitive: item.isSensitive
                        )
                        migratedCount += 1
                    }
                    group.leave()
                }
            }
            
            // Migrate HTML data if present
            if needsHTMLMigration, let htmlData = item.htmlData {
                group.enter()
                saveRichData(htmlData, type: .html) { htmlPath in
                    if let htmlPath = htmlPath {
                        updatedItem = ClipboardItem(
                            plainTextPreview: updatedItem.plainTextPreview,
                            rtfData: nil,
                            htmlData: nil,
                            timestamp: updatedItem.timestamp,
                            isPinned: updatedItem.isPinned,
                            rtfDataPath: updatedItem.rtfDataPath,
                            htmlDataPath: htmlPath,
                            imagePath: updatedItem.imagePath,
                            isSensitive: updatedItem.isSensitive
                        )
                        if updatedItem.rtfDataPath == nil {
                            migratedCount += 1
                        }
                    }
                    group.leave()
                }
            }
            
            // Wait for migrations to complete before adding item
            group.wait()
            migratedItems.append(updatedItem)
        }
        
        if migratedCount > 0 {
            history = migratedItems
            saveHistory()
            Logger.clipboard("Migration completed: \(migratedCount) items migrated to disk storage", level: .info)
        } else {
            Logger.clipboard("No items needed migration", level: .info)
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
    let imagePath: String?        // Path to image file on disk (for image clipboard items)
    let timestamp: Date
    var isPinned: Bool
    let isSensitive: Bool         // Indicates if item contains password/sensitive data
    
    // Legacy support: For migration from old format
    let rtfData: Data?    // Only used during migration, not stored (internal for migration)
    let htmlData: Data?   // Only used during migration, not stored (internal for migration)

    // Constants for memory optimization
    private static let maxPreviewLength = 200
    private static let largeTextThreshold = 500 // Characters

    init(plainTextPreview: String, rtfData: Data? = nil, htmlData: Data? = nil, timestamp: Date, isPinned: Bool = false, rtfDataPath: String? = nil, htmlDataPath: String? = nil, imagePath: String? = nil, isSensitive: Bool = false) {
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
                Logger.clipboard("Extremely large text truncated (\(plainTextPreview.count) chars)", level: .warning)
            }
        } else {
            self.plainTextPreview = plainTextPreview
            self.fullText = nil // No need to duplicate small text
        }

        // Store paths (preferred) or legacy data (for migration)
        self.rtfDataPath = rtfDataPath
        self.htmlDataPath = htmlDataPath
        self.imagePath = imagePath
        self.rtfData = rtfData  // Legacy - only for migration
        self.htmlData = htmlData  // Legacy - only for migration
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.isSensitive = isSensitive
    }
    
    /// Initializer for database loading (preserves existing ID)
    /// Used when loading from database to maintain item identity
    init(id: UUID, plainTextPreview: String, fullText: String?, rtfDataPath: String?, htmlDataPath: String?, imagePath: String?, timestamp: Date, isPinned: Bool, isSensitive: Bool) {
        self.id = id
        self.plainTextPreview = plainTextPreview
        self.fullText = fullText
        self.rtfDataPath = rtfDataPath
        self.htmlDataPath = htmlDataPath
        self.imagePath = imagePath
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.rtfData = nil
        self.htmlData = nil
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
        self.imagePath = nil
        self.rtfData = nil
        self.htmlData = nil
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.isSensitive = false  // Legacy items default to non-sensitive
    }

    // MARK: - Codable Support (Custom Encoding/Decoding)
    
    enum CodingKeys: String, CodingKey {
        case id, plainTextPreview, fullText, rtfDataPath, htmlDataPath, imagePath, timestamp, isPinned, isSensitive
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
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false  // Default to false for legacy items
        
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
        try container.encodeIfPresent(imagePath, forKey: .imagePath)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isSensitive, forKey: .isSensitive)
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
    
    /// Indicates if this item is an image
    var isImage: Bool {
        return imagePath != nil
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
