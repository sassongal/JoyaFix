import Foundation
import GRDB

/// Database manager for storing clipboard and OCR history
/// CRITICAL FIX: Replaces UserDefaults to prevent memory issues and improve performance
/// Uses SQLite with GRDB for efficient, thread-safe storage
class HistoryDatabaseManager {
    static let shared = HistoryDatabaseManager()
    
    private var dbQueue: DatabaseQueue?
    private let databaseURL: URL
    
    // Serial queue for database operations
    private let dbQueueSerial = DispatchQueue(label: "com.joyafix.database", qos: .utility)
    
    private init() {
        // Create database in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDirectory = appSupport.appendingPathComponent("JoyaFix", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true, attributes: nil)
        
        databaseURL = dbDirectory.appendingPathComponent("history.db")
        
        // Initialize database
        initializeDatabase()
    }
    
    /// Initializes the database and creates tables if needed
    private func initializeDatabase() {
        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
            
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
                
                print("✓ Database initialized successfully")
            }
            
            // Ensure indexes exist (migration support for existing databases)
            ensureIndexesExist()
        } catch {
            print("❌ Failed to initialize database: \(error.localizedDescription)")
            // Fallback: continue with UserDefaults if database fails
        }
    }
    
    // MARK: - Clipboard History Operations
    
    /// Saves clipboard history items to database
    func saveClipboardHistory(_ items: [ClipboardItem]) throws {
        guard let queue = dbQueue else {
            throw DatabaseError.notInitialized
        }
        
        try queue.write { db in
            // Clear existing items
            try db.execute(sql: "DELETE FROM clipboard_history")
            
            // Insert all items
            for item in items {
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
    
    // MARK: - Migration from UserDefaults
    
    /// Migrates clipboard history from UserDefaults to database
    func migrateClipboardHistoryFromUserDefaults() -> Bool {
        let key = JoyaFixConstants.UserDefaultsKeys.clipboardHistory
        
        guard let data = UserDefaults.standard.data(forKey: key) else {
            print("ℹ️ No clipboard history in UserDefaults to migrate")
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            let items = try decoder.decode([ClipboardItem].self, from: data)
            
            try saveClipboardHistory(items)
            
            // Remove from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: key)
            print("✓ Migrated \(items.count) clipboard items from UserDefaults to database")
            return true
        } catch {
            print("❌ Failed to migrate clipboard history: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Migrates OCR history from UserDefaults to database
    func migrateOCRHistoryFromUserDefaults() -> Bool {
        let key = JoyaFixConstants.UserDefaultsKeys.ocrHistory
        
        guard let data = UserDefaults.standard.data(forKey: key) else {
            print("ℹ️ No OCR history in UserDefaults to migrate")
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            let items = try decoder.decode([OCRScan].self, from: data)
            
            try saveOCRHistory(items)
            
            // Remove from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: key)
            print("✓ Migrated \(items.count) OCR scans from UserDefaults to database")
            return true
        } catch {
            print("❌ Failed to migrate OCR history: \(error.localizedDescription)")
            return false
        }
    }
}

    // MARK: - Database Health Check
    
    /// Checks if database indexes exist and creates them if missing (migration support)
    func ensureIndexesExist() {
        guard let queue = dbQueue else {
            print("⚠️ Cannot check indexes: Database not initialized")
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
                    print("✓ Created missing index: idx_clipboard_timestamp")
                }
                if !hasPinnedIndex {
                    try db.execute(sql: "CREATE INDEX idx_clipboard_pinned ON clipboard_history(is_pinned)")
                    print("✓ Created missing index: idx_clipboard_pinned")
                }
                
                // Check and create ocr_history indexes if missing
                let ocrIndexes = try db.indexes(on: "ocr_history")
                let hasDateIndex = ocrIndexes.contains { $0.name == "idx_ocr_date" }
                
                if !hasDateIndex {
                    try db.execute(sql: "CREATE INDEX idx_ocr_date ON ocr_history(date DESC)")
                    print("✓ Created missing index: idx_ocr_date")
                }
            }
        } catch {
            print("⚠️ Failed to ensure indexes exist: \(error.localizedDescription)")
        }
    }
}

// MARK: - Database Errors

enum DatabaseError: Error {
    case notInitialized
    case migrationFailed
    case databaseLocked
    case ioError(String)
    
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
}

