# Code Review - JoyaFix

## Critical Issues (באגים קריטיים)

### 1. Race Condition ב-`cleanupOrphanedFiles()` - ClipboardHistoryManager.swift

**בעיה:** Snapshot של ה-history נלקח על MainActor, אבל נעשה שימוש בו ב-`Task.detached` שרץ ברקע. זה יכול לגרום ל-race condition אם ה-history משתנה בזמן שהניקוי רץ.

**מיקום:** שורות 1003-1081

```swift
@MainActor
func cleanupOrphanedFiles() {
    // Snapshot נלקח על MainActor
    let snapshot = Set(history.flatMap { ... })
    
    // אבל נעשה שימוש בו ב-Task.detached שרץ ברקע
    Task.detached(priority: .utility) {
        // snapshot יכול להיות לא מעודכן כאן!
        if snapshot.contains(filePath) { ... }
    }
}
```

**פתרון מוצע:**
```swift
@MainActor
func cleanupOrphanedFiles() {
    // Capture snapshot as immutable data structure
    let snapshot = Set(history.flatMap { item -> [String] in
        var paths: [String] = []
        if let rtfPath = item.rtfDataPath { paths.append(rtfPath) }
        if let htmlPath = item.htmlDataPath { paths.append(htmlPath) }
        if let imagePath = item.imagePath { paths.append(imagePath) }
        return paths
    })
    
    let dataDir = dataDirectory
    
    // Use MainActor.run to ensure snapshot is captured atomically
    Task.detached(priority: .utility) { [snapshot, dataDir] in
        // snapshot is now a captured immutable value, safe to use
        // ... rest of cleanup code
    }
}
```

### 2. Path Traversal Vulnerability - ClipboardHistoryManager.swift

**בעיה:** השימוש ב-`hasPrefix()` לא מספיק להגנה מפני path traversal attacks. ניתן לעקוף זאת עם symlinks או relative paths.

**מיקום:** שורות 971-978, 1043-1047

```swift
guard fileURL.path.hasPrefix(dataDirectory.path) else {
    Logger.clipboard("SECURITY: Attempted to delete file outside data directory: \(path)", level: .error)
    return
}
```

**פתרון מוצע:**
```swift
private func safeDeleteFile(at path: String) {
    let fileURL = URL(fileURLWithPath: path)
    
    // CRITICAL: Use resolvingSymlinksInPath() to prevent symlink attacks
    let resolvedPath = fileURL.resolvingSymlinksInPath().path
    let resolvedDataDir = dataDirectory.resolvingSymlinksInPath().path
    
    // CRITICAL: Use canonical path comparison
    guard resolvedPath.hasPrefix(resolvedDataDir) else {
        Logger.clipboard("SECURITY: Attempted to delete file outside data directory: \(path)", level: .error)
        return
    }
    
    // Additional check: ensure path is not a directory traversal attempt
    let relativePath = String(resolvedPath.dropFirst(resolvedDataDir.count))
    guard !relativePath.contains("..") && !relativePath.hasPrefix("/") else {
        Logger.clipboard("SECURITY: Invalid path detected: \(path)", level: .error)
        return
    }
    
    do {
        try FileManager.default.removeItem(atPath: resolvedPath)
    } catch {
        Logger.clipboard("Failed to delete file \(path): \(error.localizedDescription)", level: .error)
    }
}
```

### 3. Database Recovery Race Condition - HistoryDatabaseManager.swift

**בעיה:** ב-`recoverFromCorruption()`, הקוד מנסה לקרוא מבסיס נתונים פגום ללא הגנה מספקת מפני קריסה. אם הקריאה נכשלת, הקוד ממשיך עם מערך ריק, מה שעלול לגרום לאובדן נתונים.

**מיקום:** שורות 206-258

```swift
do {
    recoveredClipboardItems = try tempQueue.read { db in
        // קריאה מבסיס נתונים פגום
        let rows = try? Row.fetchAll(db, sql: "...")
        return rows?.compactMap { ... } ?? []
    }
} catch {
    // CRITICAL FIX: Continue with empty array instead of potentially crashing
    recoveredClipboardItems = []
}
```

**פתרון מוצע:**
```swift
do {
    recoveredClipboardItems = try tempQueue.read { db in
        // Use PRAGMA quick_check first to see if we can read anything
        let quickCheck = try? String.fetchOne(db, sql: "PRAGMA quick_check")
        if quickCheck?.lowercased() != "ok" {
            Logger.database("Database quick check failed, attempting partial recovery", level: .warning)
        }
        
        // Try to read with error handling for each row
        let rows = try? Row.fetchAll(db, sql: """
            SELECT * FROM clipboard_history
            ORDER BY is_pinned DESC, timestamp DESC
        """)
        
        var recovered: [ClipboardItem] = []
        for row in rows ?? [] {
            if let item = try? parseClipboardItem(from: row) {
                recovered.append(item)
            } else {
                Logger.database("Skipped corrupted row during recovery", level: .warning)
            }
        }
        return recovered
    }
    Logger.database("Recovered \(recoveredClipboardItems.count) clipboard items", level: .info)
} catch {
    Logger.database("Could not recover clipboard history: \(error.localizedDescription)", level: .warning)
    // Try to recover at least some data using backup if available
    recoveredClipboardItems = attemptBackupRecovery() ?? []
}
```

### 4. Weak Reference Pattern ב-KeyboardBlocker - בעיית Thread Safety

**בעיה:** השימוש ב-`globalKeyboardBlockerInstance` כ-weak reference יכול להיכשל אם ה-instance משתחרר בזמן שה-event tap עדיין פעיל. אין הגנה מפני race condition.

**מיקום:** שורות 5-16, 99-100

```swift
private weak var globalKeyboardBlockerInstance: KeyboardBlocker?

private func globalKeyboardBlockerCallback(...) -> Unmanaged<CGEvent>? {
    guard let blocker = globalKeyboardBlockerInstance else {
        return Unmanaged.passUnretained(event)
    }
    return blocker.handleEvent(...)
}
```

**פתרון מוצע:**
```swift
// Use thread-safe access with a lock
private let instanceLock = NSLock()
private weak var globalKeyboardBlockerInstance: KeyboardBlocker?

private func globalKeyboardBlockerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    instanceLock.lock()
    defer { instanceLock.unlock() }
    
    guard let blocker = globalKeyboardBlockerInstance else {
        // If instance is nil, disable the event tap to prevent further callbacks
        if let tap = refcon?.assumingMemoryBound(to: CFMachPort.self).pointee {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        return Unmanaged.passUnretained(event)
    }
    return blocker.handleEvent(proxy: proxy, type: type, event: event)
}
```

### 5. Key Validation חלש מדי - SettingsManager.swift

**בעיה:** האימות של מפתחות API בודק רק את האורך (>= 20 תווים), אבל לא את הפורמט האמיתי. זה מאפשר מפתחות לא תקינים להישמר.

**מיקום:** שורות 71-75, 117-120

```swift
if !newValue.isEmpty {
    guard newValue.count >= 20 else {
        Logger.error("Invalid Gemini key format: key too short (minimum 20 characters)")
        return
    }
}
```

**פתרון מוצע:**
```swift
if !newValue.isEmpty {
    // Validate minimum length
    guard newValue.count >= 20 else {
        Logger.error("Invalid Gemini key format: key too short (minimum 20 characters)")
        return
    }
    
    // Validate format: Gemini keys typically start with "AIza" or similar patterns
    // OpenRouter keys are typically longer and may have specific prefixes
    let trimmedKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedKey.count == newValue.count else {
        Logger.error("Invalid key format: key contains leading/trailing whitespace")
        return
    }
    
    // Additional validation: check for common invalid patterns
    guard !trimmedKey.contains("\n") && !trimmedKey.contains("\r") else {
        Logger.error("Invalid key format: key contains newline characters")
        return
    }
    
    // For Gemini: validate it looks like a valid API key (starts with "AIza" typically)
    if keyType == .gemini && !trimmedKey.hasPrefix("AIza") {
        Logger.warning("Gemini key doesn't match expected format (typically starts with 'AIza')")
        // Don't reject, but warn - user might have a different key format
    }
}
```

---

## Logic & Edge Cases (לוגיקה ומקרי קצה)

### 1. Double Migration Risk - ClipboardHistoryManager.swift

**בעיה:** אם `migrateToDatabase()` נקרא פעמיים (למשל בגלל race condition), זה יכול לגרום לבעיות. אין הגנה מפני concurrent migration.

**מיקום:** שורות 72-76, 88-92

**פתרון מוצע:**
```swift
private let migrationLock = NSLock()
private var isMigrating = false

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
        loadHistory()
    } else {
        Logger.clipboard("Migration returned false - keeping data in UserDefaults as fallback", level: .warning)
    }
}
```

### 2. Silent Failure ב-`loadHistory()` - ClipboardHistoryManager.swift

**בעיה:** אם כל הניסיונות נכשלים, הקוד מחזיר מערך ריק ללא התראה למשתמש. זה יכול לגרום לאובדן נתונים שקט.

**מיקום:** שורות 838-929

**פתרון מוצע:**
```swift
@MainActor
private func loadHistory() {
    var retryCount = 0
    let maxRetries = 3
    
    func attemptLoad() {
        do {
            let items = try databaseManager.loadClipboardHistory()
            history = items
            Logger.clipboard("Loaded \(history.count) items from database", level: .info)
            // ... existing fallback logic ...
        } catch {
            if retryCount < maxRetries {
                retryCount += 1
                Logger.clipboard("Retry \(retryCount)/\(maxRetries) loading history", level: .warning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    attemptLoad()
                }
                return
            }
            
            // CRITICAL: After all retries failed, show user notification
            Logger.clipboard("CRITICAL: Failed to load history after \(maxRetries) retries", level: .critical)
            
            // Show user-visible error
            DispatchQueue.main.async {
                showToast("Failed to load clipboard history. Some data may be unavailable.", style: .error, duration: 5.0)
            }
            
            // ... existing fallback logic ...
        }
    }
    
    attemptLoad()
}
```

### 3. Event Tap Failure Handling - KeyboardBlocker.swift

**בעיה:** אם `CGEvent.tapCreate()` נכשל, הקוד רק מדפיס הודעה אבל לא מטפל בזה. המשתמש לא יודע שהמקלדת לא נחסמה.

**מיקום:** שורות 116-119

**פתרון מוצע:**
```swift
guard let eventTap = eventTap else {
    Logger.error("Failed to create event tap - keyboard blocking unavailable")
    isLocked = false // Reset state since we couldn't lock
    
    // Notify user that keyboard blocking failed
    DispatchQueue.main.async {
        NotificationCenter.default.post(
            name: .showToast,
            object: ToastMessage(
                text: "Failed to enable keyboard lock. Please check accessibility permissions.",
                style: .error,
                duration: 3.0
            )
        )
    }
    return
}
```

### 4. Database Initialization Infinite Loop Risk - HistoryDatabaseManager.swift

**בעיה:** אם `recoverFromCorruption()` נכשל באופן עקבי, הקוד יכול להיכנס ללולאה אינסופית של ניסיונות התאוששות.

**מיקום:** שורות 52-159

**פתרון מוצע:**
```swift
private var recoveryAttempts = 0
private let maxRecoveryAttempts = 3

private func initializeDatabase(maxRetries: Int) {
    guard maxRetries > 0 else {
        Logger.database("CRITICAL: Failed to initialize database after multiple attempts", level: .critical)
        dbQueue = nil
        // CRITICAL: Prevent infinite recovery loops
        recoveryAttempts = 0
        return
    }
    
    // ... existing code ...
    
    if fileExists {
        if !checkDatabaseIntegrity() {
            Logger.database("Database integrity check failed - attempting recovery...", level: .warning)
            
            // CRITICAL: Limit recovery attempts to prevent infinite loops
            guard recoveryAttempts < maxRecoveryAttempts else {
                Logger.database("CRITICAL: Too many recovery attempts, resetting database", level: .critical)
                resetDatabase()
                recoveryAttempts = 0
                initializeDatabase(maxRetries: maxRetries - 1)
                return
            }
            
            recoveryAttempts += 1
            if !recoverFromCorruption() {
                Logger.database("Database recovery failed - resetting database", level: .error)
                resetDatabase()
                recoveryAttempts = 0
                initializeDatabase(maxRetries: maxRetries - 1)
                return
            } else {
                recoveryAttempts = 0 // Reset on success
            }
        }
    }
    
    // ... rest of initialization ...
}
```

---

## Optimization (אופטימיזציה)

### 1. Inefficient Directory Scanning - ClipboardHistoryManager.swift

**בעיה:** `cleanupOrphanedFiles()` סורק את כל התיקייה בכל פעם, גם אם לא השתנה דבר. זה יכול להיות איטי לתיקיות גדולות.

**מיקום:** שורות 1016-1026

**פתרון מוצע:**
```swift
// OPTIMIZATION: Use file system events or inotify instead of polling
private var directoryWatcher: DispatchSourceFileSystemObject?

private func startScheduledCleanup() {
    // ... existing immediate cleanup ...
    
    // OPTIMIZATION: Watch directory for changes instead of polling
    let fileDescriptor = open(dataDirectory.path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
        Logger.clipboard("Could not watch data directory, falling back to timer", level: .warning)
        // Fallback to timer
        setupCleanupTimer()
        return
    }
    
    directoryWatcher = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fileDescriptor,
        eventMask: .write,
        queue: DispatchQueue.global(qos: .utility)
    )
    
    directoryWatcher?.setEventHandler { [weak self] in
        // Directory changed, trigger cleanup
        Task { @MainActor in
            self?.cleanupOrphanedFiles()
        }
    }
    
    directoryWatcher?.resume()
}

// Or at minimum, improve the existing check:
private func shouldRescanDirectory() -> Bool {
    guard let lastScan = lastCleanupScan else { return true }
    
    // Check directory modification time
    guard let dirModTime = try? FileManager.default.attributesOfItem(
        atPath: dataDirectory.path
    )[.modificationDate] as? Date else {
        return true // If we can't check, rescan to be safe
    }
    
    // Also check if history count changed (faster check)
    let currentHistoryCount = history.count
    if let lastHistoryCount = lastCleanupHistoryCount,
       currentHistoryCount == lastHistoryCount,
       dirModTime <= lastScan {
        return false
    }
    
    lastCleanupHistoryCount = currentHistoryCount
    return true
}
```

### 2. Database Query Optimization - HistoryDatabaseManager.swift

**בעיה:** השאילתה `loadClipboardHistory()` טוענת את כל הפריטים לזיכרון בבת אחת. עבור היסטוריה גדולה, זה יכול לגרום לבעיות זיכרון.

**מיקום:** שורות 497-538

**פתרון מוצע:**
```swift
/// Loads clipboard history from database with pagination support
func loadClipboardHistory(limit: Int? = nil, offset: Int = 0) throws -> [ClipboardItem] {
    guard let queue = dbQueue else {
        throw DatabaseError.notInitialized
    }
    
    return try queue.read { db in
        var sql = """
            SELECT * FROM clipboard_history
            ORDER BY is_pinned DESC, timestamp DESC
        """
        
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }
        
        let rows = try Row.fetchAll(db, sql: sql)
        
        return rows.compactMap { row -> ClipboardItem? in
            // ... existing parsing logic ...
        }
    }
}

// In ClipboardHistoryManager:
@MainActor
private func loadHistory() {
    // Load in chunks to avoid memory issues
    let chunkSize = 1000
    var allItems: [ClipboardItem] = []
    var offset = 0
    
    repeat {
        do {
            let chunk = try databaseManager.loadClipboardHistory(limit: chunkSize, offset: offset)
            if chunk.isEmpty { break }
            allItems.append(contentsOf: chunk)
            offset += chunkSize
        } catch {
            Logger.clipboard("Failed to load history chunk at offset \(offset): \(error.localizedDescription)", level: .error)
            break
        }
    } while true
    
    history = allItems
    Logger.clipboard("Loaded \(history.count) items from database", level: .info)
}
```

### 3. Redundant History Filtering - ClipboardHistoryManager.swift

**בעיה:** ב-`addToHistory()`, הקוד מפריד פריטים מוצמדים ולא מוצמדים בכל פעם מחדש. זה יכול להיות איטי עבור רשימות גדולות.

**מיקום:** שורות 522-560

**פתרון מוצע:**
```swift
@MainActor
func addToHistory(_ item: ClipboardItem) {
    // ... existing duplicate removal ...
    
    // OPTIMIZATION: Maintain separate arrays for pinned/unpinned to avoid filtering
    // This requires changing the history storage structure, but provides O(1) access
    
    // Alternative: Cache the separation
    if historySeparatedCache == nil {
        updateHistoryCache()
    }
    
    // Use cached separation
    let pinnedItems = historySeparatedCache?.pinned ?? []
    let unpinnedItems = historySeparatedCache?.unpinned ?? []
    
    // ... rest of logic using cached arrays ...
    
    // Invalidate cache after modification
    historySeparatedCache = nil
}

private var historySeparatedCache: (pinned: [ClipboardItem], unpinned: [ClipboardItem])?

private func updateHistoryCache() {
    var pinned: [ClipboardItem] = []
    var unpinned: [ClipboardItem] = []
    
    for item in history {
        if item.isPinned {
            pinned.append(item)
        } else {
            unpinned.append(item)
        }
    }
    
    historySeparatedCache = (pinned: pinned, unpinned: unpinned)
}
```

---

## Suggested Fix (תיקונים מוצעים)

### Fix 1: Thread-Safe Snapshot Capture

```swift
@MainActor
func cleanupOrphanedFiles() {
    // Create atomic snapshot with all necessary data
    struct CleanupSnapshot {
        let validPaths: Set<String>
        let dataDirectory: URL
        let lastScan: Date?
    }
    
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
        
        if snapshot.validPaths.contains(filePath) || snapshot.validPaths.contains(resolvedPath) {
            continue
        }
        
        if let attributes = try? fileManager.attributesOfItem(atPath: filePath),
           let fileSize = attributes[.size] as? Int64 {
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
    }
    
    await MainActor.run {
        self.lastCleanupScan = Date()
    }
}
```

### Fix 2: Enhanced Path Validation

```swift
nonisolated private func validateFilePath(_ path: String, relativeTo baseDirectory: URL) -> Bool {
    let fileURL = URL(fileURLWithPath: path)
    
    // Resolve symlinks to prevent symlink attacks
    let resolvedPath = fileURL.resolvingSymlinksInPath()
    let resolvedBase = baseDirectory.resolvingSymlinksInPath()
    
    // Check if path is within base directory
    guard resolvedPath.path.hasPrefix(resolvedBase.path) else {
        return false
    }
    
    // Get relative path
    let relativePath = String(resolvedPath.path.dropFirst(resolvedBase.path.count))
    
    // Check for directory traversal attempts
    guard !relativePath.contains("..") else {
        return false
    }
    
    // Ensure path doesn't start with / (should be relative)
    guard !relativePath.hasPrefix("/") || relativePath == "/" else {
        return false
    }
    
    // Additional check: ensure it's a file, not trying to access parent directories
    let pathComponents = relativePath.components(separatedBy: "/").filter { !$0.isEmpty }
    guard !pathComponents.contains("..") else {
        return false
    }
    
    return true
}

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
```

### Fix 3: Improved Database Recovery

```swift
private func recoverFromCorruption() -> Bool {
    Logger.database("Attempting database recovery...", level: .info)
    
    // Backup corrupted database
    let backupURL = databaseURL.appendingPathExtension("corrupted.\(Int(Date().timeIntervalSince1970))")
    
    do {
        try FileManager.default.copyItem(at: databaseURL, to: backupURL)
        Logger.database("Created backup of corrupted database: \(backupURL.lastPathComponent)", level: .info)
    } catch {
        Logger.database("Could not backup corrupted database: \(error.localizedDescription)", level: .warning)
    }
    
    // Try to recover data using SQLite's built-in recovery
    var recoveredClipboardItems: [ClipboardItem] = []
    
    do {
        // First, try to open with read-only mode
        let tempQueue = try DatabaseQueue(path: databaseURL.path)
        
        // Try PRAGMA quick_check to see if database is readable
        let quickCheck = try? tempQueue.read { db -> String? in
            return try String.fetchOne(db, sql: "PRAGMA quick_check")
        }
        
        if quickCheck?.lowercased() == "ok" {
            // Database is actually OK, just try normal read
            recoveredClipboardItems = try tempQueue.read { db in
                try self.loadClipboardItemsFromDatabase(db: db)
            }
        } else {
            // Database is corrupted, try to read what we can
            Logger.database("Database quick check failed, attempting partial recovery", level: .warning)
            
            recoveredClipboardItems = try tempQueue.read { db in
                // Try to read with error handling per row
                var recovered: [ClipboardItem] = []
                
                // Use a cursor to read row by row, catching errors per row
                let rows = try? Row.fetchCursor(db, sql: """
                    SELECT * FROM clipboard_history
                    ORDER BY is_pinned DESC, timestamp DESC
                """)
                
                while let row = try? rows?.next() {
                    if let item = try? self.parseClipboardItem(from: row) {
                        recovered.append(item)
                    }
                }
                
                return recovered
            }
        }
        
        Logger.database("Recovered \(recoveredClipboardItems.count) clipboard items", level: .info)
    } catch {
        Logger.database("Could not recover clipboard history: \(error.localizedDescription)", level: .warning)
        recoveredClipboardItems = []
    }
    
    // Reset database
    resetDatabase()
    
    // Re-initialize and restore recovered data
    do {
        dbQueue = try DatabaseQueue(path: databaseURL.path)
        
        try dbQueue?.write { db in
            // Create tables
            try self.createTables(db: db)
            
            // Restore recovered data
            if !recoveredClipboardItems.isEmpty {
                for item in recoveredClipboardItems {
                    try? self.insertClipboardItem(item, into: db)
                }
                Logger.database("Restored \(recoveredClipboardItems.count) clipboard items", level: .info)
            }
        }
        
        Logger.database("Database recovery completed", level: .info)
        return true
    } catch {
        Logger.database("Failed to re-initialize database after recovery: \(error.localizedDescription)", level: .error)
        return false
    }
}

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
```

---

## סיכום

הקוד באופן כללי כתוב היטב עם תשומת לב לנושאים חשובים כמו memory management ו-thread safety. עם זאת, יש כמה נקודות שדורשות שיפור:

1. **אבטחה:** Path validation צריך להיות חזק יותר עם symlink resolution
2. **Race Conditions:** יש כמה מקומות שצריכים הגנה נוספת מפני concurrent access
3. **Error Handling:** חלק מהכשלים נשארים שקטים - צריך ליידע את המשתמש
4. **ביצועים:** יש מקום לאופטימיזציה בסקירת תיקיות וטעינת נתונים

התיקונים המוצעים למעלה מטפלים בכל הבעיות הללו תוך שמירה על הקוד הקיים ועל backward compatibility.
