import Cocoa
import Foundation
import Carbon
import CryptoKit

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
    // CRITICAL FIX: Use timestamp-based approach for internal write detection
    // This avoids race conditions with the 0.5s poll interval
    private var lastInternalWriteTime: Date?
    private let internalWriteGracePeriod: TimeInterval = 0.5

    // Configuration
    private let settings = SettingsManager.shared
    // OPTIMIZATION: Poll at 0.5s with changeCount check to only process when clipboard actually changes
    private let pollInterval: TimeInterval = 0.5
    private let userDefaultsKey = JoyaFixConstants.UserDefaultsKeys.clipboardHistory
    private let dataDirectory: URL
    
    // OPTIMIZATION: Track last clipboard content to avoid unnecessary processing
    private var lastClipboardHash: String?
    
    // OPTIMIZATION: Cache directory modification time to avoid re-scanning if directory hasn't changed
    private var lastCleanupScan: Date?

    // CRITICAL FIX: Track if data directory is valid for file operations
    private var isDataDirectoryValid = false
    
    // Migration flags
    private let migrationKey = "ClipboardHistoryMigrationCompleted"
    private let databaseMigrationKey = "ClipboardHistoryDatabaseMigrationCompleted"
    
    // CRITICAL FIX: Migration lock to prevent concurrent migration
    private let migrationLock = NSLock()
    private var isMigrating = false
    
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
            isDataDirectoryValid = true
        } catch {
            Logger.clipboard("Failed to create clipboard data directory: \(error.localizedDescription)", level: .error)
            isDataDirectoryValid = false
            // Notify user of degraded functionality
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Clipboard file storage unavailable. Rich text and images may not be saved.",
                        style: .warning,
                        duration: 5.0
                    )
                )
            }
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
    
    /// CRITICAL FIX: Calculate SHA256 hash for reliable, deterministic deduplication
    /// Replaces String.hashValue which is not deterministic and can cause false positives
    private func calculateHash(for text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Calculate SHA256 hash for binary data (used for image deduplication)
    nonisolated private func calculateDataHash(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Checks if the clipboard has changed and processes new content
    private func checkForClipboardChanges() {
        let currentChangeCount = NSPasteboard.general.changeCount

        // Check if clipboard has changed
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // CRITICAL FIX: Use timestamp-based approach to detect internal writes
        // This avoids race conditions with the 0.5s poll interval
        if let lastWrite = lastInternalWriteTime,
           Date().timeIntervalSince(lastWrite) < internalWriteGracePeriod {
            lastInternalWriteTime = nil
            return
        }

        // CRITICAL FIX: Use SHA256 hash for reliable, deterministic deduplication
        // String.hashValue is not deterministic and can cause false positives
        if let currentText = NSPasteboard.general.string(forType: .string) {
            let currentHash = calculateHash(for: currentText)
            if currentHash == lastClipboardHash {
                return  // Same content, skip processing
            }
            lastClipboardHash = currentHash
        }

        // All subsequent code runs on the MainActor because the class is isolated.
        
        guard let item = captureClipboardContent() else { return }
        
        // CRITICAL FIX: Don't return early for image items - let processAndSaveImageItem handle deduplication
        // The async save will check for duplicates before adding to history
        
        // CRITICAL FIX: Enhanced validation - check for truly empty content and size limits
        let trimmedText = item.plainTextPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            Logger.clipboard("Skipping empty clipboard item", level: .debug)
            return
        }
        
        // Check for extremely long content that might cause memory issues
        guard trimmedText.count < 10_000_000 else { // 10MB limit
            Logger.clipboard("Skipping extremely large clipboard item (\(trimmedText.count) chars)", level: .warning)
            return
        }

        // Get full text for comparison.
        let itemFullText = item.textForPasting

        // Strict deduplication: Check against all items in history.
        let isDuplicate = history.contains { historyItem in
            historyItem.textForPasting == itemFullText
        }

        if isDuplicate {
            safeLogPreview(item, message: "Skipping duplicate")
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
    
    // CRITICAL FIX: Use Task with captured dataDirectory to avoid MainActor issues
    /// Processes and saves heavy data (RTF/HTML) to disk asynchronously, then adds item to history
    private func processAndSaveItem(_ tempItem: ClipboardItem) {
        // Capture dataDirectory before entering Task to avoid MainActor isolation issues
        let dataDir = dataDirectory
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            var rtfPath: String?
            var htmlPath: String?
            
            // שמירה כבדה לדיסק - רצה ברקע!
            // CRITICAL FIX: Use captured dataDir and nonisolated helper for file I/O
            if let rtf = tempItem.rtfData {
                rtfPath = self.saveRichDataSync(data: rtf, type: .rtf, dataDirectory: dataDir)
            }
            if let html = tempItem.htmlData {
                htmlPath = self.saveRichDataSync(data: html, type: .html, dataDirectory: dataDir)
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
            
            // CRITICAL FIX: Use MainActor.run for thread-safe UI updates
            await MainActor.run {
                self.addToHistory(finalItem)
            }
        }
    }
    
    /// CRITICAL FIX: Nonisolated helper for saving rich data (avoids MainActor isolation issues)
    nonisolated private func saveRichDataSync(data: Data, type: RichDataType, dataDirectory: URL) -> String? {
        let fileName = "\(UUID().uuidString).\(type.fileExtension)"
        let fileURL = dataDirectory.appendingPathComponent(fileName)
        
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
    
    /// Captures image content from clipboard (synchronous, must be called on main thread)
    private func captureImageContent(imageData: Data, pasteboard: NSPasteboard) -> ClipboardItem? {
        // Check for password/sensitive data indicators (on main thread)
        let pasteboardTypes = pasteboard.types ?? []
        let isSensitive = pasteboardTypes.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) ||
                         pasteboardTypes.contains(NSPasteboard.PasteboardType("com.agilebits.onepassword"))

        // CRITICAL FIX: Generate unique hash for image deduplication
        // This prevents all images from being treated as duplicates
        let imageHash = calculateDataHash(for: imageData)
        let hashPrefix = String(imageHash.prefix(8))

        // Get text representation if available (for image descriptions) - on main thread
        // Include hash in text preview for uniqueness
        let baseText = pasteboard.string(forType: .string) ?? "Image"
        let textPreview = baseText == "Image" ? "Image [\(hashPrefix)]" : baseText

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

        // Process image separately with the hash for deduplication
        processAndSaveImageItem(tempItem, imageData: imageData, imageHash: imageHash)
        return tempItem
    }
    
    /// Processes and saves image data to disk asynchronously, then adds item to history
    /// CRITICAL FIX: Added imageHash parameter for proper deduplication
    private func processAndSaveImageItem(_ tempItem: ClipboardItem, imageData: Data, imageHash: String) {
        // Capture dataDirectory before entering Task to avoid MainActor isolation issues
        let dataDir = dataDirectory
        // Capture current history hashes for deduplication check
        let existingImageHashes = Set(history.compactMap { item -> String? in
            // Extract hash from image items (stored in plainTextPreview as "Image [hash]")
            guard item.isImage else { return nil }
            let preview = item.plainTextPreview
            if let startIndex = preview.range(of: "[")?.upperBound,
               let endIndex = preview.range(of: "]")?.lowerBound {
                return String(preview[startIndex..<endIndex])
            }
            return nil
        })

        // Check for duplicate before saving
        let hashPrefix = String(imageHash.prefix(8))
        if existingImageHashes.contains(hashPrefix) {
            Logger.clipboard("Skipping duplicate image (hash: \(hashPrefix))", level: .debug)
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // CRITICAL FIX: Use nonisolated helper for saving image data
            let imagePath = self.saveImageDataSync(data: imageData, dataDirectory: dataDir)

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

            // CRITICAL FIX: Use MainActor.run instead of DispatchQueue.main.async for proper concurrency
            await MainActor.run { [weak self] in
                guard let self = self else { return }

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
        return saveImageDataSync(data: data, dataDirectory: dataDirectory)
    }
    
    /// CRITICAL FIX: Nonisolated helper for saving image data (avoids MainActor isolation issues)
    nonisolated private func saveImageDataSync(data: Data, dataDirectory: URL) -> String? {
        let fileName = "\(UUID().uuidString).png"
        let fileURL = dataDirectory.appendingPathComponent(fileName)
        
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

        // OPTIMIZATION: Separate pinned and unpinned items in a single pass
        var pinnedItems: [ClipboardItem] = []
        var unpinnedItems: [ClipboardItem] = []
        
        for item in history {
            if item.isPinned {
                pinnedItems.append(item)
            } else {
                unpinnedItems.append(item)
            }
        }

        // Add new item at the top of unpinned section
        var newUnpinnedItems = [itemToAdd] + unpinnedItems

        // Limit unpinned items (pinned items don't count toward the limit)
        if newUnpinnedItems.count > maxHistoryCount {
            // Get items that will be dropped (from index maxHistoryCount to the end)
            let itemsToRemove = Array(newUnpinnedItems.suffix(newUnpinnedItems.count - maxHistoryCount))
            
            // מחיקת קבצים של פריטים שנזרקים מהרשימה!
            for oldItem in itemsToRemove {
                if let path = oldItem.rtfDataPath {
                    safeDeleteFile(at: path)
                }
                if let path = oldItem.htmlDataPath {
                    safeDeleteFile(at: path)
                }
                if let path = oldItem.imagePath {
                    safeDeleteFile(at: path)
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
        safeLogPreview(item, message: "Added to clipboard history\(formatInfo)")
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
                safeDeleteFile(at: rtfPath)
            }
            if let htmlPath = item.htmlDataPath {
                safeDeleteFile(at: htmlPath)
            }
            if let imagePath = item.imagePath {
                safeDeleteFile(at: imagePath)
            }
        }
        
        lastCopiedText = nil
        saveHistory()
    }

    /// Toggles the pin status of a clipboard item
    /// MUST be called on MainActor to ensure thread safety for @Published history
    /// CRITICAL FIX: Use atomic remove-and-return to prevent index race condition
    @MainActor
    func togglePin(for item: ClipboardItem) {
        guard let index = history.firstIndex(where: { $0.id == item.id }) else { return }

        // CRITICAL FIX: Atomic remove-and-return to avoid index invalidation race
        var updatedItem = history.remove(at: index)
        updatedItem.isPinned.toggle()

        // Re-insert based on new pin status
        let pinnedCount = history.filter { $0.isPinned }.count
        // Safe insertion: min ensures we don't exceed array bounds
        let insertIndex = min(pinnedCount, history.count)
        history.insert(updatedItem, at: insertIndex)

        if updatedItem.isPinned {
            Logger.clipboard("Pinned: \(updatedItem.plainTextPreview.prefix(30))...", level: .debug)
        } else {
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
            safeDeleteFile(at: rtfPath)
        }
        if let htmlPath = item.htmlDataPath {
            safeDeleteFile(at: htmlPath)
        }
        if let imagePath = item.imagePath {
            safeDeleteFile(at: imagePath)
        }
        
        history.removeAll { $0.id == item.id }
        saveHistory()
        safeLogPreview(item, message: "Deleted from history")
    }

    // MARK: - Paste from History

    /// Writes the selected history item back to the clipboard and optionally pastes it
    func pasteItem(_ item: ClipboardItem, simulatePaste: Bool = true, formattingOption: PasteFormattingOption = .normal) {
        // Mark this as an internal write to prevent it from being re-recorded
        lastInternalWriteTime = Date()

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
        lastInternalWriteTime = Date()
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

            // CRITICAL FIX: Throttle fallback saves to prevent performance issues
            // Only save if we haven't saved recently (throttle to once per minute)
            let lastFallbackSave = UserDefaults.standard.double(forKey: "LastFallbackSave")
            let now = Date().timeIntervalSince1970
            guard now - lastFallbackSave > 60 else {
                Logger.clipboard("Skipping fallback save (throttled - last save was \(Int(now - lastFallbackSave))s ago)", level: .debug)
                return
            }

            // Fallback to UserDefaults if database fails (Insurance Policy)
            let encoder = JSONEncoder()
            do {
                let encoded = try encoder.encode(history)
                UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
                Logger.clipboard("Fallback: Saved \(history.count) items to UserDefaults (\(encoded.count) bytes)", level: .warning)

                // Log fallback status for monitoring
                UserDefaults.standard.set(true, forKey: "ClipboardHistoryFallbackActive")
                UserDefaults.standard.set(now, forKey: "ClipboardHistoryFallbackTimestamp")
                UserDefaults.standard.set(now, forKey: "LastFallbackSave")
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
                    // CRITICAL: After all retries failed, show user notification
                    Logger.clipboard("CRITICAL: Failed to load history after \(maxRetries) retries", level: .critical)
                    showToast("Failed to load clipboard history. Some data may be unavailable.", style: .error, duration: 5.0)
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
                        // Show user notification about data loss
                        showToast("Critical: Failed to load clipboard history. Data may be lost.", style: .error, duration: 5.0)
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
    /// CRITICAL FIX: Prevents concurrent migration with lock
    @MainActor
    private func migrateToDatabase() {
        migrationLock.lock()
        defer { migrationLock.unlock() }
        
        guard !isMigrating else {
            Logger.clipboard("Migration already in progress, skipping", level: .warning)
            return
        }
        
        guard !UserDefaults.standard.bool(forKey: databaseMigrationKey) else {
            Logger.clipboard("Migration already completed", level: .debug)
            return
        }
        
        isMigrating = true
        defer { isMigrating = false }
        
        Logger.clipboard("Migrating clipboard history from UserDefaults to database...", level: .info)
        
        let success = databaseManager.migrateClipboardHistoryFromUserDefaults()
        if success {
            UserDefaults.standard.set(true, forKey: databaseMigrationKey)
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
        // CRITICAL FIX: Use weak self in both Timer and Task to prevent retain cycle
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.cleanupOrphanedFiles()
            }
        }
        Logger.clipboard("Scheduled disk cleanup started (runs every 24 hours)", level: .info)
    }
    
    // MARK: - File Deletion Helpers
    
    /// CRITICAL FIX: Enhanced path validation to prevent path traversal attacks
    /// Validates that the file path is within the dataDirectory with symlink resolution
    /// Uses path component comparison (not string prefix) for security
    nonisolated private func validateFilePath(_ path: String, relativeTo baseDirectory: URL) -> Bool {
        let fileURL = URL(fileURLWithPath: path)

        // Resolve symlinks to prevent symlink attacks
        let resolvedPath = fileURL.resolvingSymlinksInPath()
        let resolvedBase = baseDirectory.resolvingSymlinksInPath()

        // CRITICAL FIX: Use path component comparison instead of string prefix
        // String prefix is vulnerable: "/base/path".hasPrefix("/base/path") matches "/base/pathEvil"
        let fileComponents = resolvedPath.pathComponents
        let baseComponents = resolvedBase.pathComponents

        // Base components must be a prefix of file components
        guard fileComponents.count > baseComponents.count else {
            return false  // File must be inside base, not equal to it
        }

        // Verify base path components are a prefix
        for (index, baseComponent) in baseComponents.enumerated() {
            guard index < fileComponents.count, fileComponents[index] == baseComponent else {
                return false
            }
        }

        // Check that remaining components don't contain ".."
        let remainingComponents = fileComponents[baseComponents.count...]
        guard !remainingComponents.contains("..") else {
            return false
        }

        return true
    }
    
    /// CRITICAL FIX: Safe file deletion with enhanced path validation to prevent path traversal attacks
    /// Validates that the file path is within the dataDirectory before deletion
    private func safeDeleteFile(at path: String) {
        guard validateFilePath(path, relativeTo: dataDirectory) else {
            Logger.clipboard("SECURITY: Invalid file path detected: \(path)", level: .error)
            return
        }
        
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        
        do {
            try FileManager.default.removeItem(atPath: resolvedPath)
        } catch {
            Logger.clipboard("Failed to delete file \(path): \(error.localizedDescription)", level: .error)
        }
    }
    
    /// CRITICAL FIX: Safe logging helper that prevents sensitive data from being logged
    /// Checks if item is sensitive and avoids logging preview text
    private func safeLogPreview(_ item: ClipboardItem, message: String) {
        if item.isSensitive {
            Logger.clipboard("\(message) [SENSITIVE]", level: .info)
        } else {
            Logger.clipboard("\(message): \(item.plainTextPreview.prefix(30))...", level: .info)
        }
    }
    
    // MARK: - Cleanup

    /// Snapshot structure for cleanup operations (defined at class level for nonisolated access)
    private struct CleanupSnapshot: Sendable {
        let validPaths: Set<String>
        let dataDirectory: URL
        let lastScan: Date?
    }

    /// Cleans up orphaned files in the data directory that are not referenced in history
    /// This should be called after history is loaded to remove files that are no longer needed
    /// Runs on background thread to avoid blocking Main Thread
    @MainActor
    func cleanupOrphanedFiles() {
        // CRITICAL FIX: Create atomic snapshot with all necessary data
        let snapshot = CleanupSnapshot(
            validPaths: Set(history.flatMap { item -> [String] in
                var paths: [String] = []
                if let rtfPath = item.rtfDataPath { paths.append(rtfPath) }
                if let htmlPath = item.htmlDataPath { paths.append(htmlPath) }
                if let imagePath = item.imagePath { paths.append(imagePath) }
                return paths
            }),
            dataDirectory: dataDirectory,
            lastScan: lastCleanupScan
        )
        
        // Check if rescan is needed (on MainActor)
        if let lastScan = snapshot.lastScan,
           let dirModTime = try? FileManager.default.attributesOfItem(
               atPath: snapshot.dataDirectory.path
           )[.modificationDate] as? Date,
           dirModTime <= lastScan {
            Logger.clipboard("Skipping cleanup - directory unchanged since last scan", level: .debug)
            return
        }
        
        // Run cleanup on background thread with captured snapshot
        Task.detached(priority: .utility) {
            await self.performCleanup(with: snapshot)
        }
    }
    
    /// Performs cleanup on background thread with captured snapshot
    nonisolated private func performCleanup(with snapshot: CleanupSnapshot) async {
        let fileManager = FileManager.default
        guard let directoryContents = try? fileManager.contentsOfDirectory(
            at: snapshot.dataDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else {
            Logger.clipboard("Could not read data directory for cleanup", level: .warning)
            return
        }
        
        var deletedCount = 0
        var totalSizeDeleted: Int64 = 0
        
        for fileURL in directoryContents {
            let filePath = fileURL.path
            
            // Use resolved path for security
            let resolvedPath = fileURL.resolvingSymlinksInPath().path
            let resolvedDataDir = snapshot.dataDirectory.resolvingSymlinksInPath().path
            
            guard resolvedPath.hasPrefix(resolvedDataDir) else {
                Logger.clipboard("SECURITY: Skipping file outside data directory: \(filePath)", level: .warning)
                continue
            }
            
            // Check both original and resolved paths
            if snapshot.validPaths.contains(filePath) || snapshot.validPaths.contains(resolvedPath) {
                continue
            }
            
            if let attributes = try? fileManager.attributesOfItem(atPath: filePath),
               let fileSize = attributes[FileAttributeKey.size] as? Int64 {
                totalSizeDeleted += fileSize
            }
            
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
        
        await MainActor.run {
            self.lastCleanupScan = Date()
        }
    }
    
    // MARK: - Migration
    
    /// Migrates old clipboard history from UserDefaults (with embedded Data) to disk-based storage
    /// MUST be called on MainActor to ensure thread safety for @Published history
    /// CRITICAL FIX: Uses async/await instead of blocking group.wait() to prevent main thread blocking
    @MainActor
    private func migrateOldHistory() {
        Logger.clipboard("Starting clipboard history migration...", level: .info)
        
        Task { @MainActor in
            var migratedCount = 0
            // CRITICAL FIX: Create snapshot to prevent race condition during migration
            let itemsToMigrate = history
            var migratedItems: [ClipboardItem] = []
            
            // Process items in parallel batches to avoid blocking
            let batchSize = 10
            
            for batchStart in stride(from: 0, to: itemsToMigrate.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, itemsToMigrate.count)
                let batch = Array(itemsToMigrate[batchStart..<batchEnd])
                
                await withTaskGroup(of: ClipboardItem.self) { group in
                    for item in batch {
                        let needsRTFMigration = item.rtfData != nil && item.rtfDataPath == nil
                        let needsHTMLMigration = item.htmlData != nil && item.htmlDataPath == nil
                        
                        if !needsRTFMigration && !needsHTMLMigration {
                            migratedItems.append(item)
                            continue
                        }
                        
                        group.addTask { [weak self] in
                            guard let self = self else { return item }
                            
                            var updatedItem = item
                            let dataDir = self.dataDirectory
                            
                            if needsRTFMigration, let rtfData = item.rtfData {
                                let rtfPath = await Task.detached(priority: .utility) {
                                    return self.saveRichDataSync(data: rtfData, type: .rtf, dataDirectory: dataDir)
                                }.value
                                
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
                                    await MainActor.run {
                                        migratedCount += 1
                                    }
                                }
                            }
                            
                            if needsHTMLMigration, let htmlData = updatedItem.htmlData {
                                let htmlPath = await Task.detached(priority: .utility) {
                                    return self.saveRichDataSync(data: htmlData, type: .html, dataDirectory: dataDir)
                                }.value
                                
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
                                        await MainActor.run {
                                            migratedCount += 1
                                        }
                                    }
                                }
                            }
                            
                            return updatedItem
                        }
                    }
                    
                    // Collect results
                    for await result in group {
                        migratedItems.append(result)
                    }
                }
            }
            
            if migratedCount > 0 {
                // CRITICAL FIX: Merge migrated items with current history to handle concurrent updates
                let currentHistory = self.history
                var mergedItems = migratedItems
                
                // Add any new items that were added during migration
                for currentItem in currentHistory {
                    if !mergedItems.contains(where: { $0.id == currentItem.id }) {
                        mergedItems.append(currentItem)
                    }
                }
                
                // Sort by timestamp
                mergedItems.sort { $0.timestamp > $1.timestamp }
                
                history = mergedItems
                saveHistory()
                Logger.clipboard("Migration completed: \(migratedCount) items migrated to disk storage", level: .info)
            } else {
                Logger.clipboard("No items needed migration", level: .info)
            }
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
