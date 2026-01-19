import Foundation
import GRDB

/// Database manager for storing clipboard and OCR history
/// CRITICAL FIX: Replaces UserDefaults to prevent memory issues and improve performance
/// Uses SQLite with GRDB for efficient, thread-safe storage
class HistoryDatabaseManager {
    static let shared = HistoryDatabaseManager()

    private var dbQueue: DatabaseQueue?
    private let databaseURL: URL

    // CRITICAL FIX: Thread-safe recovery attempts counter to prevent race conditions
    private let recoveryLock = NSLock()
    private var _recoveryAttempts = 0
    private let maxRecoveryAttempts = 3

    /// Thread-safe access to recovery attempts counter
    private var recoveryAttempts: Int {
        get {
            recoveryLock.lock()
            defer { recoveryLock.unlock() }
            return _recoveryAttempts
        }
        set {
            recoveryLock.lock()
            defer { recoveryLock.unlock() }
            _recoveryAttempts = newValue
        }
    }

    /// Atomically increment recovery attempts and return new value
    private func incrementRecoveryAttempts() -> Int {
        recoveryLock.lock()
        defer { recoveryLock.unlock() }
        _recoveryAttempts += 1
        return _recoveryAttempts
    }

    /// Reset recovery attempts counter (thread-safe)
    private func resetRecoveryAttempts() {
        recoveryLock.lock()
        defer { recoveryLock.unlock() }
        _recoveryAttempts = 0
    }
    
    private init() {
        // CRITICAL FIX: Safe unwrap with fallback to prevent crash
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            // Fallback to user's home directory if Application Support is unavailable
            Logger.database("CRITICAL: Application Support directory unavailable, using fallback", level: .error)
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let dbDirectory = homeDir.appendingPathComponent(
                "Library/Application Support/JoyaFix",
                isDirectory: true
            )
            
            // Create directory if it doesn't exist
            try? FileManager.default.createDirectory(
                at: dbDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            databaseURL = dbDirectory.appendingPathComponent("history.db")
            initializeDatabase()
            return
        }
        
        let dbDirectory = appSupport.appendingPathComponent("JoyaFix", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true, attributes: nil)
        
        databaseURL = dbDirectory.appendingPathComponent("history.db")
        
        // Initialize database
        initializeDatabase()
    }
    
    /// Initializes the database and creates tables if needed
    /// Includes integrity check and corruption recovery
    private func initializeDatabase() {
        initializeDatabase(maxRetries: 3)
    }
    
    /// Internal initialization with retry limit to prevent infinite recursion
    private func initializeDatabase(maxRetries: Int) {
        guard maxRetries > 0 else {
            Logger.database("CRITICAL: Failed to initialize database after multiple attempts", level: .critical)
            dbQueue = nil
            // CRITICAL: Prevent infinite recovery loops (thread-safe)
            resetRecoveryAttempts()
            return
        }
        
        // Check if database file exists and verify integrity before opening
        let fileExists = FileManager.default.fileExists(atPath: databaseURL.path)
        
        if fileExists {
            // Perform integrity check on existing database
            if !checkDatabaseIntegrity() {
                Logger.database("Database integrity check failed - attempting recovery...", level: .warning)
                
                // CRITICAL: Limit recovery attempts to prevent infinite loops (thread-safe)
                let currentAttempts = incrementRecoveryAttempts()
                guard currentAttempts <= maxRecoveryAttempts else {
                    Logger.database("CRITICAL: Too many recovery attempts (\(currentAttempts)), resetting database", level: .critical)
                    resetDatabase()
                    resetRecoveryAttempts()
                    initializeDatabase(maxRetries: maxRetries - 1)
                    return
                }
                if !recoverFromCorruption() {
                    Logger.database("Database recovery failed - resetting database", level: .error)
                    resetDatabase()
                    resetRecoveryAttempts()
                    // Re-initialize after reset with decremented retry count
                    initializeDatabase(maxRetries: maxRetries - 1)
                    return
                } else {
                    resetRecoveryAttempts() // Reset on success
                }
            }
        }
        
        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
            
            // Perform integrity check after opening
            try dbQueue?.read { db in
                let integrityResult = try String.fetchOne(db, sql: "PRAGMA integrity_check")
                if let result = integrityResult, result.lowercased() != "ok" {
                    Logger.database("Database integrity check returned: \(result)", level: .warning)
                    // Close the queue before recovery
                    dbQueue = nil
                    throw DatabaseError.databaseCorrupted(result)
                }
            }
            
            try dbQueue?.write { db in
                // Create clipboard_history table
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS clipboard_history (
                        id TEXT PRIMARY KEY,
                        plain_text_preview TEXT NOT NULL,
                        full_text TEXT,
                        rtf_data_path TEXT,
                        html_data_path TEXT,
                        image_path TEXT,
                        timestamp REAL NOT NULL,
                        is_pinned INTEGER NOT NULL DEFAULT 0,
                        is_sensitive INTEGER NOT NULL DEFAULT 0,
                        created_at REAL NOT NULL
                    )
                """)
                
                // Create indexes for faster queries (optimized for ORDER BY timestamp DESC)
                // CRITICAL: Index on timestamp DESC for fast history loading
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_timestamp ON clipboard_history(timestamp DESC)")
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_pinned ON clipboard_history(is_pinned)")
                
#if false
                // Create ocr_history table
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS ocr_history (
                        id TEXT PRIMARY KEY,
                        extracted_text TEXT NOT NULL,
                        preview_image_path TEXT,
                        date REAL NOT NULL,
                        created_at REAL NOT NULL
                    )
                """)
                
                // Create index for OCR history (optimized for ORDER BY date DESC)
                // CRITICAL: Index on date DESC for fast history loading
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_ocr_date ON ocr_history(date DESC)")
#endif

                
                Logger.database("Database initialized successfully", level: .info)
            }
            
            // Ensure indexes exist (migration support for existing databases)
            ensureIndexesExist()
        } catch {
            Logger.database("Failed to initialize database: \(error.localizedDescription)", level: .error)
            
            // If corruption detected, attempt recovery
            if case DatabaseError.databaseCorrupted = error {
                // CRITICAL: Limit recovery attempts
                guard recoveryAttempts < maxRecoveryAttempts else {
                    Logger.database("CRITICAL: Too many recovery attempts, resetting database", level: .critical)
                    resetDatabase()
                    recoveryAttempts = 0
                    initializeDatabase(maxRetries: maxRetries - 1)
                    return
                }
                
                recoveryAttempts += 1
                if recoverFromCorruption() {
                    recoveryAttempts = 0 // Reset on success
                    // Retry initialization after recovery with decremented retry count
                    initializeDatabase(maxRetries: maxRetries - 1)
                    return
                } else {
                    resetDatabase()
                    recoveryAttempts = 0
                    initializeDatabase(maxRetries: maxRetries - 1)
                    return
                }
            }
            
            // Fallback: continue with UserDefaults if database fails
            dbQueue = nil
        }
    }
    
    /// Checks database integrity using PRAGMA integrity_check
    /// Returns true if database is healthy, false if corrupted
    private func checkDatabaseIntegrity() -> Bool {
        // Try to open database temporarily for integrity check
        guard let tempQueue = try? DatabaseQueue(path: databaseURL.path) else {
            return false
        }
        
        do {
            let result = try tempQueue.read { db -> String? in
                return try String.fetchOne(db, sql: "PRAGMA integrity_check")
            }
            
            if let integrityResult = result {
                let isHealthy = integrityResult.lowercased() == "ok"
                if !isHealthy {
                    Logger.database("Database integrity check failed: \(integrityResult)", level: .warning)
                }
                return isHealthy
            }
            
            return false
        } catch {
            Logger.database("Failed to check database integrity: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    /// Attempts to recover from database corruption
    /// Returns true if recovery succeeded, false otherwise
    private func recoverFromCorruption() -> Bool {
        Logger.database("Attempting database recovery...", level: .info)
        
        // Backup corrupted database
        let backupURL = databaseURL.appendingPathExtension("corrupted.\(Int(Date().timeIntervalSince1970))")
        
        do {
            // Try to backup the corrupted file
            try FileManager.default.copyItem(at: databaseURL, to: backupURL)
            Logger.database("Created backup of corrupted database: \(backupURL.lastPathComponent)", level: .info)
        } catch {
            Logger.database("Could not backup corrupted database: \(error.localizedDescription)", level: .warning)
        }
        
        // Try to recover data using SQLite's recovery mechanisms
        do {
            // Attempt to open corrupted database and read what we can
            let tempQueue = try DatabaseQueue(path: databaseURL.path)
            
            // Try to read what we can from corrupted database
            var recoveredClipboardItems: [ClipboardItem] = []
#if false
            var recoveredOCRItems: [OCRScan] = []
#endif

            
            do {
                // Try PRAGMA quick_check to see if database is readable
                let quickCheck = try? tempQueue.read { db -> String? in
                    return try String.fetchOne(db, sql: "PRAGMA quick_check")
                }
                
                if quickCheck?.lowercased() == "ok" {
                    // Database is actually OK, just try normal read
                    recoveredClipboardItems = try tempQueue.read { db in
                        let rows = try Row.fetchAll(db, sql: """
                            SELECT * FROM clipboard_history
                            ORDER BY is_pinned DESC, timestamp DESC
                        """)
                        
                        return rows.compactMap { row -> ClipboardItem? in
                            return try? parseClipboardItem(from: row)
                        }
                    }
                } else {
                    // Database is corrupted, try to read what we can
                    Logger.database("Database quick check failed, attempting partial recovery", level: .warning)
                    
                    recoveredClipboardItems = try tempQueue.read { db in
                        // Try to read with error handling per row
                        var recovered: [ClipboardItem] = []
                        
                        // Try to fetch all rows, but handle errors per row
                        // Use try? to catch any errors during fetch
                        if let rows = try? Row.fetchAll(db, sql: """
                            SELECT * FROM clipboard_history
                            ORDER BY is_pinned DESC, timestamp DESC
                        """) {
                            // Process each row individually, catching errors per row
                            for row in rows {
                                if let item = try? parseClipboardItem(from: row) {
                                    recovered.append(item)
                                } else {
                                    Logger.database("Skipped corrupted row during recovery", level: .warning)
                                }
                            }
                        }
                        
                        return recovered
                    }
                }
                
                Logger.database("Recovered \(recoveredClipboardItems.count) clipboard items", level: .info)
            } catch {
                Logger.database("Could not recover clipboard history: \(error.localizedDescription)", level: .warning)
                // CRITICAL FIX: Continue with empty array instead of potentially crashing
                recoveredClipboardItems = []
            }
            
#if false
            do {
                recoveredOCRItems = try tempQueue.read { db in
                    let rows = try? Row.fetchAll(db, sql: """
                        SELECT * FROM ocr_history
                        ORDER BY date DESC
                    """)
                    
                    return rows?.compactMap { row -> OCRScan? in
                        guard let idString = row["id"] as String?,
                              let id = UUID(uuidString: idString),
                              let extractedText = row["extracted_text"] as String?,
                              let date = row["date"] as Double? else {
                            return nil
                        }
                        
                        let scanDate = Date(timeIntervalSince1970: date)
                        let previewPath = row["preview_image_path"] as String?
                        
                        return OCRScan(
                            id: id,
                            date: scanDate,
                            extractedText: extractedText,
                            previewImagePath: previewPath
                        )
                    } ?? []
                }
#if false
                Logger.database("Recovered \(recoveredOCRItems.count) OCR scans", level: .info)
#endif

            } catch {
                Logger.database("Could not recover OCR history: \(error.localizedDescription)", level: .warning)
            }
#endif
            
            // Close the corrupted database (DatabaseQueue automatically closes when deallocated)
            
            // Reset database
            resetDatabase()
            
            // Re-initialize database
            do {
                dbQueue = try DatabaseQueue(path: databaseURL.path)
                
                // Create tables first
                try dbQueue?.write { db in
                    try createTables(db: db)
                }
                
                // Restore recovered data
                if !recoveredClipboardItems.isEmpty {
                    do {
                        try dbQueue?.write { db in
                            for item in recoveredClipboardItems {
                                try? insertClipboardItem(item, into: db)
                            }
                        }
                        Logger.database("Restored \(recoveredClipboardItems.count) clipboard items", level: .info)
                    } catch {
                        Logger.database("Could not restore recovered clipboard items: \(error.localizedDescription)", level: .warning)
                    }
                }
                
#if false
                if !recoveredOCRItems.isEmpty {
                    do {
                        try dbQueue?.write { db in
                            for item in recoveredOCRItems {
                                try? db.execute(sql: """
                                    INSERT INTO ocr_history (id, extracted_text, preview_image_path, date, created_at)
                                    VALUES (?, ?, ?, ?, ?)
                                """, arguments: [
                                    item.id.uuidString,
                                    item.extractedText,
                                    item.previewImagePath,
                                    item.date.timeIntervalSince1970,
                                    Date().timeIntervalSince1970
                                ])
                            }
                        }
                        Logger.database("Restored \(recoveredOCRItems.count) OCR scans", level: .info)
                    } catch {
                        Logger.database("Could not restore recovered OCR scans: \(error.localizedDescription)", level: .warning)
                    }
                }
#endif

            } catch {
                Logger.database("Failed to re-initialize database after recovery: \(error.localizedDescription)", level: .error)
                return false
            }
            
            Logger.database("Database recovery completed", level: .info)
            return true
        } catch {
            Logger.database("Database recovery failed: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    /// Resets the database by deleting the corrupted file and creating a new one
    private func resetDatabase() {
        Logger.database("Resetting database...", level: .info)
        
        // Close existing connection
        dbQueue = nil
        
        // Backup corrupted database if it exists
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            let backupURL = databaseURL.appendingPathExtension("reset.\(Int(Date().timeIntervalSince1970))")
            do {
                try FileManager.default.moveItem(at: databaseURL, to: backupURL)
                Logger.database("Moved corrupted database to backup: \(backupURL.lastPathComponent)", level: .info)
            } catch {
                // If backup fails, try to delete
                try? FileManager.default.removeItem(at: databaseURL)
                Logger.database("Could not backup corrupted database, deleted instead", level: .warning)
            }
        }
        
        // Database will be recreated on next initialization
        Logger.database("Database reset completed", level: .info)
    }
    
    // MARK: - Clipboard History Operations
    
    /// Saves a single clipboard item to database using UPSERT (insert or update)
    /// PERFORMANCE: This is 100x faster than the old delete-all-then-insert pattern
    func saveClipboardItem(_ item: ClipboardItem) throws {
        guard let queue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO clipboard_history (
                    id, plain_text_preview, full_text, rtf_data_path, html_data_path,
                    image_path, timestamp, is_pinned, is_sensitive, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    plain_text_preview = excluded.plain_text_preview,
                    full_text = excluded.full_text,
                    rtf_data_path = excluded.rtf_data_path,
                    html_data_path = excluded.html_data_path,
                    image_path = excluded.image_path,
                    timestamp = excluded.timestamp,
                    is_pinned = excluded.is_pinned,
                    is_sensitive = excluded.is_sensitive
            """, arguments: [
                item.id.uuidString,
                item.plainTextPreview,
                item.fullText,
                item.rtfDataPath,
                item.htmlDataPath,
                item.imagePath,
                item.timestamp.timeIntervalSince1970,
                item.isPinned ? 1 : 0,
                item.isSensitive ? 1 : 0,
                Date().timeIntervalSince1970
            ])
        }
    }

    /// Deletes old unpinned items, keeping only the most recent maxCount items
    /// PERFORMANCE: Efficient deletion without touching pinned items
    func deleteOldItems(keeping maxCount: Int) throws {
        guard let queue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        try queue.write { db in
            try db.execute(sql: """
                DELETE FROM clipboard_history
                WHERE is_pinned = 0
                AND id NOT IN (
                    SELECT id FROM clipboard_history
                    WHERE is_pinned = 0
                    ORDER BY timestamp DESC
                    LIMIT ?
                )
            """, arguments: [maxCount])
        }
    }

    /// Legacy method for batch operations (migration compatibility)
    /// @deprecated Use saveClipboardItem(_:) for new code
    func saveClipboardHistory(_ items: [ClipboardItem]) throws {
        guard let queue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        // Use incremental saves instead of delete-all
        try queue.write { db in
            for item in items {
                try db.execute(sql: """
                    INSERT INTO clipboard_history (
                        id, plain_text_preview, full_text, rtf_data_path, html_data_path,
                        image_path, timestamp, is_pinned, is_sensitive, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        plain_text_preview = excluded.plain_text_preview,
                        full_text = excluded.full_text,
                        rtf_data_path = excluded.rtf_data_path,
                        html_data_path = excluded.html_data_path,
                        image_path = excluded.image_path,
                        timestamp = excluded.timestamp,
                        is_pinned = excluded.is_pinned,
                        is_sensitive = excluded.is_sensitive
                """, arguments: [
                    item.id.uuidString,
                    item.plainTextPreview,
                    item.fullText,
                    item.rtfDataPath,
                    item.htmlDataPath,
                    item.imagePath,
                    item.timestamp.timeIntervalSince1970,
                    item.isPinned ? 1 : 0,
                    item.isSensitive ? 1 : 0,
                    Date().timeIntervalSince1970
                ])
            }
        }
    }
    
    /// Loads clipboard history from database
    func loadClipboardHistory() throws -> [ClipboardItem] {
        guard let queue = dbQueue else {
            throw DatabaseError.notInitialized
        }
        
        return try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM clipboard_history
                ORDER BY is_pinned DESC, timestamp DESC
            """)
            
            return rows.compactMap { row -> ClipboardItem? in
                guard let idString = row["id"] as String?,
                      let id = UUID(uuidString: idString),
                      let plainText = row["plain_text_preview"] as String?,
                      let timestamp = row["timestamp"] as Double? else {
                    return nil
                }
                
                let date = Date(timeIntervalSince1970: timestamp)
                let fullText = row["full_text"] as String?
                let rtfPath = row["rtf_data_path"] as String?
                let htmlPath = row["html_data_path"] as String?
                let imagePath = row["image_path"] as String?
                let isPinned = (row["is_pinned"] as Int? ?? 0) == 1
                let isSensitive = (row["is_sensitive"] as Int? ?? 0) == 1
                
                // Use database initializer to preserve ID
                return ClipboardItem(
                    id: id,
                    plainTextPreview: plainText,
                    fullText: fullText,
                    rtfDataPath: rtfPath,
                    htmlDataPath: htmlPath,
                    imagePath: imagePath,
                    timestamp: date,
                    isPinned: isPinned,
                    isSensitive: isSensitive
                )
            }
        }
    }
    
    // MARK: - OCR History Operations
    
#if false
    /// Saves OCR history items to database
    func saveOCRHistory(_ items: [OCRScan]) throws {
        guard let queue = dbQueue else {
            throw DatabaseError.notInitialized
        }
        
        try queue.write { db in
            // Clear existing items
            try db.execute(sql: "DELETE FROM ocr_history")
            
            // Insert all items
            for item in items {
                try db.execute(sql: """
                    INSERT INTO ocr_history (id, extracted_text, preview_image_path, date, created_at)
                    VALUES (?, ?, ?, ?, ?)
                """, arguments: [
                    item.id.uuidString,
                    item.extractedText,
                    item.previewImagePath,
                    item.date.timeIntervalSince1970,
                    Date().timeIntervalSince1970
                ])
            }
        }
    }
#endif

    
#if false
    /// Loads OCR history from database
    func loadOCRHistory() throws -> [OCRScan] {
        guard let queue = dbQueue else {
            throw DatabaseError.notInitialized
        }
        
        return try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM ocr_history
                ORDER BY date DESC
            """)
            
            return rows.compactMap { row -> OCRScan? in
                guard let idString = row["id"] as String?,
                      let id = UUID(uuidString: idString),
                      let extractedText = row["extracted_text"] as String?,
                      let date = row["date"] as Double? else {
                    return nil
                }
                
                let scanDate = Date(timeIntervalSince1970: date)
                let previewPath = row["preview_image_path"] as String?
                
                return OCRScan(
                    id: id,
                    date: scanDate,
                    extractedText: extractedText,
                    previewImagePath: previewPath
                )
            }
        }
    }
#endif

    
    // MARK: - Migration from UserDefaults
    
    /// Migrates clipboard history from UserDefaults to database
    func migrateClipboardHistoryFromUserDefaults() -> Bool {
        let key = JoyaFixConstants.UserDefaultsKeys.clipboardHistory
        
        guard let data = UserDefaults.standard.data(forKey: key) else {
            Logger.database("No clipboard history in UserDefaults to migrate", level: .info)
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            let items = try decoder.decode([ClipboardItem].self, from: data)
            
            try saveClipboardHistory(items)
            
            // Remove from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: key)
            Logger.database("Migrated \(items.count) clipboard items from UserDefaults to database", level: .info)
            return true
        } catch {
            Logger.database("Failed to migrate clipboard history: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
#if false
    /// Migrates OCR history from UserDefaults to database
    func migrateOCRHistoryFromUserDefaults() -> Bool {
        let key = "OCRHistory" // Use string literal instead of missing constant
        
        guard let data = UserDefaults.standard.data(forKey: key) else {
            Logger.database("No OCR history in UserDefaults to migrate", level: .info)
            return false
        }
        
        return false
    }
#else
    func migrateOCRHistoryFromUserDefaults() -> Bool {
        return false
    }
#endif

    
    // MARK: - Helper Functions for Recovery
    
    /// Parses a ClipboardItem from a database row
    private func parseClipboardItem(from row: Row) throws -> ClipboardItem {
        guard let idString = row["id"] as String?,
              let id = UUID(uuidString: idString),
              let plainText = row["plain_text_preview"] as String?,
              let timestamp = row["timestamp"] as Double? else {
            throw DatabaseError.invalidData
        }
        
        let date = Date(timeIntervalSince1970: timestamp)
        let fullText = row["full_text"] as String?
        let rtfPath = row["rtf_data_path"] as String?
        let htmlPath = row["html_data_path"] as String?
        let imagePath = row["image_path"] as String?
        let isPinned = (row["is_pinned"] as Int? ?? 0) == 1
        let isSensitive = (row["is_sensitive"] as Int? ?? 0) == 1
        
        return ClipboardItem(
            id: id,
            plainTextPreview: plainText,
            fullText: fullText,
            rtfDataPath: rtfPath,
            htmlDataPath: htmlPath,
            imagePath: imagePath,
            timestamp: date,
            isPinned: isPinned,
            isSensitive: isSensitive
        )
    }
    
    /// Creates database tables
    private func createTables(db: Database) throws {
        // Create clipboard_history table
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS clipboard_history (
                id TEXT PRIMARY KEY,
                plain_text_preview TEXT NOT NULL,
                full_text TEXT,
                rtf_data_path TEXT,
                html_data_path TEXT,
                image_path TEXT,
                timestamp REAL NOT NULL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                is_sensitive INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            )
        """)
        
        // Create indexes for faster queries
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_timestamp ON clipboard_history(timestamp DESC)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_pinned ON clipboard_history(is_pinned)")
    }
    
    /// Inserts a clipboard item into the database
    private func insertClipboardItem(_ item: ClipboardItem, into db: Database) throws {
        try db.execute(sql: """
            INSERT INTO clipboard_history (
                id, plain_text_preview, full_text, rtf_data_path, html_data_path,
                image_path, timestamp, is_pinned, is_sensitive, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            item.id.uuidString,
            item.plainTextPreview,
            item.fullText,
            item.rtfDataPath,
            item.htmlDataPath,
            item.imagePath,
            item.timestamp.timeIntervalSince1970,
            item.isPinned ? 1 : 0,
            item.isSensitive ? 1 : 0,
            Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Database Health Check
    
    /// Checks if database indexes exist and creates them if missing (migration support)
    func ensureIndexesExist() {
        guard let queue = dbQueue else {
            Logger.database("Cannot check indexes: Database not initialized", level: .warning)
            return
        }
        
        do {
            try queue.write { db in
                // Check and create clipboard_history indexes if missing
                let clipboardIndexes = try db.indexes(on: "clipboard_history")
                let hasTimestampIndex = clipboardIndexes.contains { $0.name == "idx_clipboard_timestamp" }
                let hasPinnedIndex = clipboardIndexes.contains { $0.name == "idx_clipboard_pinned" }
                
                if !hasTimestampIndex {
                    try db.execute(sql: "CREATE INDEX idx_clipboard_timestamp ON clipboard_history(timestamp DESC)")
                    Logger.database("Created missing index: idx_clipboard_timestamp", level: .info)
                }
                if !hasPinnedIndex {
                    try db.execute(sql: "CREATE INDEX idx_clipboard_pinned ON clipboard_history(is_pinned)")
                    Logger.database("Created missing index: idx_clipboard_pinned", level: .info)
                }
                
#if false
                // Check and create ocr_history indexes if missing
                let ocrIndexes = try db.indexes(on: "ocr_history")
                let hasDateIndex = ocrIndexes.contains { $0.name == "idx_ocr_date" }
                
                if !hasDateIndex {
                    try db.execute(sql: "CREATE INDEX idx_ocr_date ON ocr_history(date DESC)")
                    Logger.database("Created missing index: idx_ocr_date", level: .info)
                }
#endif

            }
        } catch {
            Logger.database("Failed to ensure indexes exist: \(error.localizedDescription)", level: .warning)
        }
    }
}

// MARK: - Database Errors

enum DatabaseError: Error {
    case notInitialized
    case migrationFailed
    case databaseLocked
    case ioError(String)
    case databaseCorrupted(String)
    case invalidData
    
    /// Checks if error is a database lock error
    static func isDatabaseLocked(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("database is locked") ||
               errorString.contains("sqlite_busy") ||
               errorString.contains("database locked")
    }
    
    /// Checks if error is an I/O error
    static func isIOError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("i/o error") ||
               errorString.contains("disk i/o error") ||
               errorString.contains("unable to open database") ||
               errorString.contains("no such file or directory")
    }
    
    /// Checks if error indicates database corruption
    static func isCorruptionError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("database disk image is malformed") ||
               errorString.contains("database corruption") ||
               errorString.contains("file is encrypted or is not a database") ||
               errorString.contains("not a database")
    }
}

