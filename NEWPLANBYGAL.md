# JoyaFix Production Readiness Plan

Based on comprehensive code analysis of 66 Swift files (~20,000 lines), here's the production readiness plan:

---

## PHASE 1: Critical Bug Fixes (Week 1)

### 1.1 Race Condition in ClipboardHistoryManager
**Location:** `ClipboardHistoryManager.swift` lines 384-400, 952-990
**Issue:** Snapshot captured on MainActor but used in `Task.detached` without atomic capture
```swift
// CURRENT (UNSAFE):
Task.detached(priority: .utility) {
    // snapshot can change between capture and use!
    if snapshot.contains(filePath) { ... }
}
```
**Fix Required:**
```swift
struct CleanupSnapshot {
    let validPaths: Set<String>
    let dataDirectory: URL
    let lastScan: Date?
}

// Capture atomically on MainActor
let snapshot = CleanupSnapshot(...)

Task.detached(priority: .utility) { [snapshot] in
    // Use captured snapshot - immutable
}
```

### 1.2 Path Traversal Vulnerability in File Operations
**Location:** `ClipboardHistoryManager.swift` lines 883-898
**Issue:** `hasPrefix()` check insufficient against symlinks
```swift
// CURRENT (VULNERABLE):
guard fileURL.path.hasPrefix(dataDirectory.path) else {
    return
}
```
**Fix Required:**
```swift
nonisolated private func validateFilePath(_ path: String, relativeTo baseDirectory: URL) -> Bool {
    let fileURL = URL(fileURLWithPath: path)
    let resolvedPath = fileURL.resolvingSymlinksInPath().path
    let resolvedBase = baseDirectory.resolvingSymlinksInPath().path

    guard resolvedPath.hasPrefix(resolvedBase) else { return false }

    let relativePath = String(resolvedPath.dropFirst(resolvedBase.count))
    guard !relativePath.contains("..") else { return false }
    guard !relativePath.hasPrefix("/") || relativePath == "/" else { return false }

    let pathComponents = relativePath.components(separatedBy: "/").filter { !$0.isEmpty }
    guard !pathComponents.contains("..") else { return false }

    return true
}
```

### 1.3 Database Recovery Infinite Loop Risk
**Location:** `HistoryDatabaseManager.swift` lines 86-98, 252-430
**Issue:** No hard limit on recovery attempts
```swift
// CURRENT (POTENTIAL INFINITE LOOP):
private func initializeDatabase(maxRetries: Int) {
    if !checkDatabaseIntegrity() {
        // Can loop forever if recoverFromCorruption() keeps failing
        if !recoverFromCorruption() {
            resetDatabase()
            initializeDatabase(maxRetries: maxRetries - 1) // Just decrements!
        }
    }
}
```
**Fix Required:**
```swift
// Already has maxRecoveryAttempts = 3 with thread-safe counter
// BUT needs additional safeguard:
private var recoveryRetryCount = 0
private let maxRecoveryRetryCount = 3

private func initializeDatabase(maxRetries: Int) {
    recoveryRetryCount = 0

    func attemptWithRetry() -> Bool {
        guard maxRetries > 0 else {
            Logger.database("CRITICAL: Max recovery retries exceeded", level: .critical)
            return false
        }

        // ... existing logic ...

        if !checkDatabaseIntegrity() {
            guard recoveryRetryCount < maxRecoveryRetryCount else {
                Logger.database("CRITICAL: Max recovery attempts reached", level: .critical)
                // Emergency fallback: create fresh database without recovery
                return createFreshDatabase()
            }
            recoveryRetryCount += 1
            return attemptWithRetry()
        }
    }

    return attemptWithRetry()
}
```

### 1.4 KeyboardBlocker Weak Reference Race
**Location:** `KeyboardBlocker.swift` lines 6-27, 143-223
**Issue:** Global weak reference accessed without proper synchronization
```swift
// CURRENT (UNSAFE):
private weak var globalKeyboardBlockerInstance: KeyboardBlocker?

private func globalKeyboardBlockerCallback(...) -> Unmanaged<CGEvent>? {
    guard let blocker = globalKeyboardBlockerInstance else {
        // Instance might be deallocating!
        return Unmanaged.passUnretained(event)
    }
    return blocker.handleEvent(...)
}
```
**Fix Required:**
```swift
// Already has NSLock but needs stronger protection:
private let instanceLock = NSLock()
private var globalKeyboardBlockerInstance: KeyboardBlocker? // Make non-weak with explicit cleanup

private func globalKeyboardBlockerCallback(...) -> Unmanaged<CGEvent>? {
    instanceLock.lock()
    defer { instanceLock.unlock() }

    guard let blocker = globalKeyboardBlockerInstance else {
        // Disable tap if instance is nil
        if let tap = refcon?.assumingMemoryBound(to: CFMachPort.self).pointee {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        return Unmanaged.passUnretained(event)
    }
    return blocker.handleEvent(...)
}

// Add explicit cleanup in deinit:
deinit {
    instanceLock.lock()
    globalKeyboardBlockerInstance = nil
    instanceLock.unlock()
    removeEventTap()
    hideOverlay()
}
```

### 1.5 SettingsManager Key Validation Too Lenient
**Location:** `SettingsManager.swift` lines 67-132, 143-200
**Issue:** Only checks length, not actual key format
```swift
// CURRENT (WEAK):
guard newValue.count >= 20 else {
    Logger.error("Invalid Gemini key format: key too short")
    return
}
```
**Fix Required:**
```swift
private func validateAPIKey(_ key: String, type: APIKeyType) -> (valid: Bool, error: String?) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == key.count else {
        return (false, "Key contains leading/trailing whitespace")
    }

    guard trimmed.count >= 20 && trimmed.count <= 500 else {
        return (false, "Key must be 20-500 characters")
    }

    guard !trimmed.contains("\n") && !trimmed.contains("\r") else {
        return (false, "Key contains newline characters")
    }

    switch type {
    case .gemini:
        // Gemini keys typically: AIza[0-9A-Za-z_-]{33}
        let geminiPattern = #"^AIza[0-9A-Za-z_-]{33}$"#
        guard trimmed.range(of: geminiPattern, options: .regularExpression) != nil else {
            return (false, "Invalid Gemini key format (should start with 'AIza')")
        }
    case .openRouter:
        // OpenRouter: sk-[a-zA-Z0-9]{48}
        let openRouterPattern = #"^sk-[a-zA-Z0-9]{48}$"#
        guard trimmed.range(of: openRouterPattern, options: .regularExpression) != nil else {
            return (false, "Invalid OpenRouter key format (should start with 'sk-')")
        }
    }

    return (true, nil)
}

// Apply validation in setters:
var geminiKey: String {
    get { _geminiKey }
    set {
        if !newValue.isEmpty {
            let validation = validateAPIKey(newValue, type: .gemini)
            guard validation.valid else {
                Logger.error("Invalid Gemini key: \(validation.error ?? "Unknown")")
                showToast(validation.error ?? "Invalid API key", style: .error, duration: 3.0)
                return
            }
        }
        // ... rest of setter
    }
}
```

### 1.6 InputMonitor Event Tap Memory Leak
**Location:** `InputMonitor.swift` lines 115-171
**Issue:** Event tap not properly invalidated on errors
```swift
// CURRENT (POTENTIAL LEAK):
guard let newEventTap = newEventTap else {
    _isMonitoring = false
    Logger.snippet("Failed to create event tap")
    // No cleanup of existing tap!
    return
}
```
**Fix Required:**
```swift
guard let newEventTap = newEventTap else {
    _isMonitoring = false

    // CRITICAL: Cleanup existing tap before returning
    removeEventTap()

    Logger.snippet("Failed to create event tap", level: .error)
    // ... notification code ...
    return
}
```

---

## PHASE 2: Performance Optimizations (Week 2)

### 2.1 Inefficient Directory Scanning
**Location:** `ClipboardHistoryManager.swift` lines 1016-1026
**Issue:** Polls entire directory every 24 hours regardless of changes
**Fix: Implement File System Events**
```swift
private var directoryWatcher: DispatchSourceFileSystemObject?

private func startScheduledCleanup() {
    let fileDescriptor = open(dataDirectory.path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
        Logger.clipboard("Could not watch data directory, falling back to timer", level: .warning)
        setupCleanupTimer()
        return
    }

    directoryWatcher = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fileDescriptor,
        eventMask: .write,
        queue: DispatchQueue.global(qos: .utility)
    )

    directoryWatcher?.setEventHandler { [weak self] in
        Task { @MainActor in
            self?.cleanupOrphanedFiles()
        }
    }

    directoryWatcher?.resume()
    Logger.clipboard("File system watcher started for clipboard data directory", level: .info)
}

private func setupCleanupTimer() {
    // Fallback to timer if file watching fails
    cleanupTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
        Task { @MainActor in
            self?.cleanupOrphanedFiles()
        }
    }
}
```

### 2.2 Database Loading Pagination
**Location:** `HistoryDatabaseManager.swift` lines 557-598
**Issue:** Loads all items into memory at once
**Fix: Implement Lazy Loading**
```swift
func loadClipboardHistory(limit: Int? = nil, offset: Int = 0) throws -> [ClipboardItem] {
    guard let queue = dbQueue else { throw DatabaseError.notInitialized }

    return try queue.read { db in
        var sql = """
            SELECT * FROM clipboard_history
            ORDER BY is_pinned DESC, timestamp DESC
        """

        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let rows = try Row.fetchAll(db, sql: sql)

        return rows.compactMap { parseClipboardItem(from: $0) }
    }
}

// In ClipboardHistoryManager, implement incremental loading:
@MainActor
private func loadHistoryIncrementally() {
    let chunkSize = 50
    var offset = 0
    var allItems: [ClipboardItem] = []

    repeat {
        do {
            let chunk = try databaseManager.loadClipboardHistory(limit: chunkSize, offset: offset)
            if chunk.isEmpty { break }
            allItems.append(contentsOf: chunk)
            offset += chunkSize
        } catch {
            Logger.clipboard("Failed to load history chunk at offset \(offset)", level: .error)
            break
        }
    } while true

    history = allItems
}
```

### 2.3 Redundant History Filtering
**Location:** `ClipboardHistoryManager.swift` lines 564-573
**Issue:** Filters pinned/unpinned on every operation
**Fix: Cache Separated Lists**
```swift
private var historySeparatedCache: (pinned: [ClipboardItem], unpinned: [ClipboardItem])?

@MainActor
func addToHistory(_ item: ClipboardItem) {
    // ... existing logic ...

    if let cache = historySeparatedCache {
        // Use cached separation
        pinnedItems = cache.pinned
        unpinnedItems = cache.unpinned
    } else {
        // Recalculate only if cache invalid
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

    // ... rest of logic ...

    // Invalidate cache after modification
    historySeparatedCache = nil
}
```

### 2.4 Image Deduplication Hash Collision
**Location:** `ClipboardHistoryManager.swift` lines 349-400
**Issue:** Uses first 8 chars of SHA256 for deduplication - potential collisions
**Fix: Use Full Hash**
```swift
// CURRENT (POTENTIAL COLLISION):
let hashPrefix = String(imageHash.prefix(8))
if existingImageHashes.contains(hashPrefix) {
    return // False positive possible!
}

// FIX: Store and compare full hash
private var imageHashesCache: Set<String> = []

func processAndSaveImageItem(_ tempItem: ClipboardItem, imageData: Data, imageHash: String) {
    let dataDir = dataDirectory
    let existingImageHashes = Set(history.compactMap { item in
        guard item.isImage else { return nil }
        // Store full hash in a separate cache structure
        return imageHashesCache[item.id.uuidString]
    })

    // Check full hash, not prefix
    if existingImageHashes.contains(imageHash) {
        Logger.clipboard("Skipping duplicate image (hash: \(imageHash))", level: .debug)
        return
    }

    // Cache new hash
    // ... rest of logic ...
}
```

---

## PHASE 3: Architecture Improvements (Week 3)

### 3.1 Database Transaction Safety
**Location:** `HistoryDatabaseManager.swift` lines 465-493
**Issue:** Multiple writes without explicit transactions
**Fix: Wrap Operations in Transactions**
```swift
func saveClipboardHistory(_ items: [ClipboardItem]) throws {
    guard let queue = dbQueue else { throw DatabaseError.notInitialized }

    try queue.write { db in
        // Begin explicit transaction for multiple writes
        try db.beginTransaction()
        defer {
            try? db.commit()
        }

        for item in items {
            try db.execute(sql: """
                INSERT OR REPLACE INTO clipboard_history (...)
            """, arguments: [...])
        }
    }
}

func deleteOldItems(keeping maxCount: Int) throws {
    guard let queue = dbQueue else { throw DatabaseError.notInitialized }

    try queue.write { db in
        try db.beginTransaction()
        defer { try? db.commit() }

        // Delete in single transaction
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

        // Vacuum after large delete to reclaim space
        try db.execute(sql: "VACUUM")
    }
}
```

### 3.2 Error Handling Consistency
**Issue:** Silent failures throughout codebase
**Fix: Create Centralized Error Handler**
```swift
// New file: ErrorHandler.swift
enum JoyaFixError: Error, LocalizedError {
    case clipboardAccessFailed(reason: String)
    case databaseCorrupted(attemptedRecovery: Bool)
    case fileOperationFailed(path: String, operation: String)
    case networkRequestFailed(url: String, statusCode: Int?)
    case permissionDenied(feature: String)
    case invalidConfiguration(key: String, reason: String)

    var recoverySuggestion: String {
        switch self {
        case .clipboardAccessFailed:
            return "Try restarting the application"
        case .databaseCorrupted(let attemptedRecovery):
            return attemptedRecovery
                ? "Contact support - recovery failed"
                : "Clear history in Settings"
        case .permissionDenied(let feature):
            return "Grant \(feature) permission in System Settings"
        default:
            return "Try the operation again"
        }
    }
}

// Centralized error reporting:
struct ErrorReporter {
    static func report(_ error: JoyaFixError, context: String = "") {
        Logger.error("\(context): \(error.localizedDescription)", level: .error)

        // Show user-facing notification
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: error.localizedDescription,
                    style: .error,
                    duration: 5.0
                )
            )
        }

        // Send to crash reporting service
        CrashReporter.reportError(error, context: context)
    }
}
```

### 3.3 Task Cancellation Support
**Location:** Multiple files using `Task.detached`
**Issue:** Tasks cannot be cancelled properly
**Fix: Implement Cancellation Tokens**
```swift
// New file: TaskManager.swift
actor TaskManager {
    static let shared = TaskManager()

    private var activeTasks: [String: Task<Void, Never>] = [:]

    func registerTask(_ id: String, task: Task<Void, Never>) {
        activeTasks[id] = task
    }

    func cancelTask(_ id: String) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }

    func cancelAllTasks() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
    }

    func cancelTasks(prefix: String) {
        activeTasks.filter { $0.key.hasPrefix(prefix) }
            .values
            .forEach { $0.cancel() }
    }
}

// Usage in PromptEnhancerManager:
func enhanceSelectedText() {
    let taskId = "enhance-\(UUID().uuidString)"
    let task = Task {
        // ... enhancement logic ...
    }

    TaskManager.shared.registerTask(taskId, task: task)

    enhancementTask = task {
        didSet {
            if let oldTask = oldValue {
                TaskManager.shared.cancelTask(taskId)
            }
        }
    }
}
```

### 3.4 Memory Management for Large Files
**Location:** `ClipboardHistoryManager.swift` lines 209-214
**Issue:** 10MB limit can still cause memory pressure
**Fix: Implement Streaming for Large Data**
```swift
private func checkForClipboardChanges() {
    // ... existing checks ...

    // Check for extremely large content with memory-safe streaming
    if let data = NSPasteboard.general.data(forType: .string) {
        let dataLength = data.count

        if dataLength > 1_000_000 { // 1MB threshold
            Logger.clipboard("Very large clipboard content detected (\(dataLength) bytes)", level: .warning)

            // Write to file directly without loading into memory
            let tempPath = dataDirectory.appendingPathComponent("temp_large_clipboard_\(UUID().uuidString).txt")
            try? data.write(to: tempPath)

            let item = ClipboardItem(
                plainTextPreview: String(data: data, encoding: .utf8)?.prefix(200) ?? "Large text",
                rtfData: nil,
                htmlData: nil,
                timestamp: Date(),
                isPinned: false,
                rtfDataPath: nil,
                htmlDataPath: nil,
                imagePath: nil,
                isSensitive: isSensitive,
                largeTextFilePath: tempPath // New field
            )

            processAndSaveItem(item)
            return
        }
    }

    // ... rest of logic ...
}
```

---

## PHASE 4: Security Enhancements (Week 4)

### 4.1 Content Sanitization
**Issue:** No input sanitization for snippet content
**Fix: Implement Sanitization**
```swift
// Add to SnippetManager.swift:
enum ContentSanitizer {
    static func sanitize(_ text: String) -> String {
        // Remove potentially dangerous content
        var sanitized = text

        // Remove null bytes and control characters except newline/tab
        sanitized = sanitized.unicodeScalars.filter { scalar in
            scalar == 0x0A || scalar == 0x0D || (scalar >= 0x20 && scalar <= 0x7E)
        }.map { Character($0) }.reduce(into: "")

        // Limit excessive whitespace
        sanitized = sanitized.replacingOccurrences(of: " {3,}", with: " ")
        sanitized = sanitized.replacingOccurrences(of: "\n{3,}", with: "\n")

        // Remove embedded scripts
        let scriptPattern = #"<\s*script[^>]*>.*?<\s*/\s*script\s*>"#i
        sanitized = sanitized.replacingOccurrences(of: scriptPattern, with: "", options: .regularExpression)

        return sanitized
    }
}

func addSnippet(_ snippet: Snippet) {
    // ... existing validation ...

    let sanitizedContent = ContentSanitizer.sanitize(snippet.content)
    var sanitizedSnippet = snippet
    sanitizedSnippet.content = sanitizedContent

    // ... rest of logic ...
}
```

### 4.2 Clipboard Content Validation
**Issue:** No validation of clipboard content before storage
**Fix: Add Content Validator**
```swift
// New file: ClipboardValidator.swift
enum ClipboardValidator {
    static func validate(_ content: String) -> (valid: Bool, reason: String?) {
        // Check for suspicious patterns
        let suspiciousPatterns = [
            "<script",
            "javascript:",
            "eval(",
            "document.cookie",
            "FROM.*SELECT",
            "DROP TABLE",
            "DELETE FROM"
        ]

        for pattern in suspiciousPatterns {
            if content.range(of: pattern, options: .caseInsensitive) != nil {
                return (false, "Contains potentially malicious pattern: \(pattern)")
            }
        }

        // Check for path traversal attempts
        if content.contains("../") || content.contains("..\\" ) {
            return (false, "Contains path traversal sequences")
        }

        return (true, nil)
    }
}

// Use in ClipboardHistoryManager:
private func checkForClipboardChanges() {
    // ... existing checks ...

    let validation = ClipboardValidator.validate(item.plainTextPreview)
    guard validation.valid else {
        Logger.clipboard("Skipping suspicious clipboard content: \(validation.reason ?? "Unknown")", level: .warning)
        return
    }

    // ... rest of logic ...
}
```

### 4.3 Secure Clipboard Clearing
**Issue:** No verification of clipboard clear
**Fix: Verify Clear Operation**
```swift
@MainActor
func clearHistory(keepPinned: Bool = false) {
    // ... existing logic ...

    // Verify clipboard was actually cleared
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    // Wait for clear to propagate
    Thread.sleep(forTimeInterval: 0.1)

    // Verify no content remains
    guard pasteboard.string(forType: .string) == nil else {
        Logger.clipboard("Clipboard clear verification failed", level: .warning)
        // Retry clear
        pasteboard.clearContents()
    }

    Logger.clipboard("Clipboard history cleared", level: .info)
}
```

---

## PHASE 5: Missing Production Features (Week 5-6)

### 5.1 Comprehensive Logging System
**Current:** `Logger.swift` uses `os.log` but lacks structured output
**Fix: Add Log Aggregation**
```swift
// Enhance Logger.swift:
enum Logger {
    // ... existing categories ...

    private static var logBuffer: [LogEntry] = []
    private static let bufferSize = 1000

    struct LogEntry {
        let timestamp: Date
        let level: LogLevel
        let category: OSLog
        let message: String
        let file: String
        let function: String
        let line: Int
    }

    // New methods for log aggregation:
    static func exportLogs() -> String {
        let sortedLogs = logBuffer.sorted { $0.timestamp < $1.timestamp }

        var output = "=== JoyaFix Log Export ===\n"
        output += "Generated: \(Date())\n\n"

        for entry in sortedLogs {
            output += "[\(entry.timestamp)] [\(entry.level.rawValue)] \(entry.category): \(entry.message)\n"
            output += "  at \(entry.file):\(entry.function):\(entry.line)\n\n"
        }

        return output
    }

    static func getLogsForSupport() -> String {
        return exportLogs()
    }

    // Add to existing log methods:
    static func info(_ message: String, category: OSLog = general, ...) {
        let entry = LogEntry(
            timestamp: Date(),
            level: .info,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line
        )

        logBuffer.append(entry)
        if logBuffer.count > bufferSize {
            logBuffer.removeFirst()
        }

        // ... existing os_log call ...
    }
}
```

### 5.2 Analytics Integration
**Current:** `CrashReporter.swift` has placeholder for production
**Fix: Implement Analytics**
```swift
// New file: AnalyticsManager.swift
import Foundation

enum AnalyticsEvent {
    case featureUsed(name: String)
    case errorOccurred(error: String, context: String)
    case performanceMetric(name: String, value: Double)
    case clipboardAction(action: String, contentType: String)
}

class AnalyticsManager {
    static let shared = AnalyticsManager()

    private var isEnabled = true

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }

        // In production, send to analytics service
        #if !DEBUG
        sendToAnalyticsService(event)
        #else
        print("Analytics [\(Date())]: \(event)")
        #endif
    }

    private func sendToAnalyticsService(_ event: AnalyticsEvent) {
        // Implementation depends on chosen service (Firebase, Mixpanel, etc.)
        // For now, log locally
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "analyticsEnabled")
    }
}

// Usage throughout codebase:
func addToHistory(_ item: ClipboardItem) {
    // ... existing logic ...

    AnalyticsManager.shared.track(.clipboardAction(
        action: "add",
        contentType: item.isImage ? "image" : "text"
    ))
}
```

### 5.3 Update System Robustness
**Current:** `UpdateManager.swift` exists but needs enhancement
**Fix: Add Version Verification and Rollback**
```swift
// Enhance UpdateManager.swift:
class UpdateManager {
    // ... existing properties ...

    private let updateServerURL = "https://github.com/sassongal/JoyaFix/releases/latest"
    private let appBundle = Bundle.main

    func checkForUpdates(completion: @escaping (UpdateResult) -> Void) {
        // Get current version
        guard let currentVersion = appBundle.infoDictionary?["CFBundleShortVersionString"] as? String else {
            completion(.error("Cannot determine current version"))
            return
        }

        // Fetch latest version
        guard let url = URL(string: updateServerURL) else {
            completion(.error("Invalid update server URL"))
            return
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    completion(.error("Invalid response from update server"))
                    return
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let latestVersion = json["tag_name"] as? String,
                      let downloadURL = json["html_url"] as? String else {
                    completion(.error("Invalid update server response"))
                    return
                }

                // Compare versions
                if compareVersions(current: currentVersion, latest: latestVersion) < 0 {
                    completion(.updateAvailable(
                        version: latestVersion,
                        downloadURL: downloadURL
                    ))
                } else {
                    completion(.upToDate)
                }
            } catch {
                completion(.error("Network error: \(error.localizedDescription)"))
            }
        }
    }

    private func compareVersions(current: String, latest: String) -> Int {
        // Simple semver comparison
        let currentParts = current.components(separatedBy: ".").compactMap { Int($0) }
        let latestParts = latest.components(separatedBy: ".").compactMap { Int($0) }

        for (current, latest) in zip(currentParts, latestParts) {
            if current < latest { return -1 }
            if current > latest { return 1 }
        }

        return 0
    }

    enum UpdateResult {
        case updateAvailable(version: String, downloadURL: String)
        case upToDate
        case error(String)
    }
}
```

### 5.4 Data Export/Import
**Current:** `SettingsExporter.swift` exists but no full data export
**Fix: Add Comprehensive Export**
```swift
// Enhance SettingsExporter.swift:
enum DataExporter {
    static func exportFullBackup() throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "JoyaFix_Backup_\(timestamp).json"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        // Gather all data
        var backup: [String: Any] = [:]

        // Clipboard history
        backup["clipboardHistory"] = try exportClipboardHistory()

        // Snippets
        backup["snippets"] = try exportSnippets()

        // Settings
        backup["settings"] = exportSettings()

        // Metadata
        backup["exportDate"] = timestamp
        backup["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        // Write to file
        let data = try JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted])
        try data.write(to: destination)

        return destination
    }

    static func importBackup(from url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        guard let backup = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }

        // Import clipboard history
        if let clipboardData = backup["clipboardHistory"] as? [[String: Any]] {
            try importClipboardHistory(clipboardData)
        }

        // Import snippets
        if let snippetsData = backup["snippets"] as? [[String: Any]] {
            try importSnippets(snippetsData)
        }

        // Import settings (with user confirmation)
        if let settingsData = backup["settings"] as? [String: Any] {
            try importSettings(settingsData)
        }

        return .success
    }

    enum ImportError: Error {
        case invalidFormat
        case versionMismatch(String)
        case corruptedData
    }

    enum ImportResult {
        case success
        case partialSuccess(warnings: [String])
        case failed(error: ImportError)
    }
}
```

---

## PHASE 6: Testing Infrastructure (Week 7)

### 6.1 Unit Test Suite
**Current:** `Tests/JoyaFixTests/` exists but minimal
**Fix: Add Comprehensive Tests**
```swift
// Tests/ClipboardHistoryManagerTests.swift
import XCTest
@testable import JoyaFix

class ClipboardHistoryManagerTests: XCTestCase {
    var manager: ClipboardHistoryManager!

    override func setUp() {
        super.setUp()
        manager = ClipboardHistoryManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testAddToHistory_DeduplicatesSameContent() {
        let item1 = ClipboardItem(
            plainTextPreview: "Test",
            timestamp: Date(),
            isPinned: false
        )

        manager.addToHistory(item1)
        manager.addToHistory(item1)

        XCTAssertEqual(manager.history.count, 1)
    }

    func testAddToHistory_RespectsMaxLimit() {
        let limit = 5
        // Set max limit via settings
        // ... setup code ...

        for i in 0..<10 {
            let item = ClipboardItem(
                plainTextPreview: "Item \(i)",
                timestamp: Date(),
                isPinned: false
            )
            manager.addToHistory(item)
        }

        XCTAssertEqual(manager.history.count, limit)
    }

    func testPinToggle_MaintainsOrder() {
        // Test that pinned items stay at top
        // ... implementation ...
    }
}

// Tests/SnippetManagerTests.swift
class SnippetManagerTests: XCTestCase {
    var manager: SnippetManager!

    func testSnippetExpansion_WorksCorrectly() {
        let snippet = Snippet(trigger: "!test", content: "Expanded content")
        manager.addSnippet(snippet)

        let buffer = "!test "
        let match = manager.findSnippetMatch(in: buffer)

        XCTAssertNotNil(match)
        XCTAssertEqual(match?.content, "Expanded content")
    }

    func testSnippetValidation_RejectsInvalidTriggers() {
        let invalidSnippet = Snippet(trigger: "", content: "Content")
        manager.addSnippet(invalidSnippet)

        XCTAssertEqual(manager.snippets.count, 0)
    }
}
```

### 6.2 Integration Tests
**Fix: Add End-to-End Tests**
```swift
// Tests/IntegrationTests.swift
class IntegrationTests: XCTestCase {
    func testFullClipboardFlow() {
        // Simulate copy -> add to history -> paste
        // ... implementation ...
    }

    func testSnippetExpansionIntegration() {
        // Test actual CGEvent simulation
        // ... implementation ...
    }

    func testAIEnhancementFlow() {
        // Test full AI enhancement pipeline
        // ... implementation ...
    }
}
```

### 6.3 Performance Tests
**Fix: Add Performance Benchmarks**
```swift
// Tests/PerformanceTests.swift
class PerformanceTests: XCTestCase {
    func measureClipboardAddPerformance() {
        let manager = ClipboardHistoryManager()

        measure {
            for i in 0..<1000 {
                let item = ClipboardItem(
                    plainTextPreview: "Test item \(i)",
                    timestamp: Date(),
                    isPinned: false
                )
                manager.addToHistory(item)
            }
        }

        // Assert: Should complete in reasonable time (< 1 second for 1000 items)
    }

    func measureSnippetMatchingPerformance() {
        let manager = SnippetManager()
        // Add 1000 snippets
        // ... setup ...

        measure {
            for _ in 0..<1000 {
                manager.findSnippetMatch(in: "test string")
            }
        }

        // Assert: O(k) complexity where k is trigger length
    }
}
```

---

## PHASE 7: Deployment & Distribution (Week 8)

### 7.1 Code Signing
**Fix: Add Proper Code Signing**
```bash
# build.sh enhancements:
#!/bin/bash

# Enable hardened runtime
enable_hardened_runtime() {
    codesign --force --sign - --timestamp --options runtime \
        --entitlements JoyaFix.entitlements \
        "$1"
}

# Verify signature
verify_signature() {
    if ! codesign -dv "$1" 2>&1 | grep -q "valid on disk"; then
        echo "✓ Code signature valid"
    else
        echo "✗ Code signature invalid"
        exit 1
    fi
}

# Build and sign
swift build -c release
enable_hardened_runtime "build/release/JoyaFix.app"
verify_signature "build/release/JoyaFix.app"
```

### 7.2 Notarization
**Fix: Add App Store Notarization**
```bash
# Add to build.sh:
notarize_app() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)

    echo "Notarizing $app_name..."

    # Upload to Apple
    xcrun notarytool submit "$app_path" \
        --apple-id "com.joyafix.app" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    # Staple notarization ticket
    xcrun stapler staple "$app_path"

    echo "✓ Notarization complete"
}

# Build flow:
swift build -c release
notarize_app "build/release/JoyaFix.app"
create_dmg "build/release/JoyaFix.app"
```

### 7.3 DMG Creation
**Fix: Professional DMG**
```bash
# New script: create_dmg.sh
#!/bin/bash

APP_PATH="build/release/JoyaFix.app"
DMG_PATH="build/release/JoyaFix-$(git describe --tags --abbrev=0).dmg"
VOLUME_NAME="JoyaFix"

# Create temporary DMG
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

# Customize DMG appearance
hdiutil attach "$DMG_PATH"
echo '
   tell application "Finder"
       tell disk "'$VOLUME_NAME'" to open
           set current view of container window
           set the bounds to bounds of container window
           set theProps to properties of the bounds
           set position of item "'JoyaFix.app'" to {150, 120}
           close
       end tell
   end tell
' | osascript

hdiutil detach /Volumes/"$VOLUME_NAME"

# Compress DMG
hdiutil convert "$DMG_PATH" -format UDZO -imagekey zlib-level 9 -o "$DMG_PATH"

echo "✓ DMG created: $DMG_PATH"
```

### 7.4 Sparkle Configuration
**Fix: Complete Auto-Update Setup**
```xml
<!-- JoyaFix.app/Contents/Resources/appcast.xml -->
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.com/xml-namespaces/sparkle">
  <channel>
    <title>JoyaFix Updates</title>
    <item>
      <title>Version 1.1.0</title>
      <sparkle:version>1.1.0</sparkle:version>
      <sparkle:releaseNotesLink>https://github.com/sassongal/JoyaFix/releases/latest</sparkle:releaseNotesLink>
      <pubDate>2026-01-19T00:00:00Z</pubDate>
      <enclosure
        url="https://github.com/sassongal/JoyaFix/releases/download/v1.1.0/JoyaFix.dmg"
        sparkle:edSignature="SHA256_HASH_HERE"
        sparkle:shortVersionString="1.1.0"
        length="12345678"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
```

---

## PHASE 8: Documentation (Week 9)

### 8.1 API Documentation
**Fix: Generate Swift Docs**
```bash
# Add to Package.swift:
// Add docc documentation target
targets: [
    .target(
        name: "JoyaFix",
        // ... existing ...
        plugins: [.swiftDocumentationPlugin]
    )
]

# Build docs:
swift package generate-documentation --target JoyaFix --output-path docs/
```

### 8.2 User Documentation
**Fix: Create User Guide**
```markdown
# Documentation/UserGuide.md

## Getting Started

### Installation
1. Download JoyaFix.dmg
2. Drag JoyaFix.app to Applications folder
3. Launch from Launchpad or Applications folder

### First Run

1. Grant Accessibility permissions when prompted
2. Grant Microphone permissions for voice input
3. Complete onboarding tutorial

### Features

#### Clipboard History
- Automatic clipboard capture
- Rich text and image support
- Pin important items
- Search and filter

#### Text Snippets
- Type trigger + space to expand
- Manage snippets in Library tab
- iCloud sync (future)

#### AI Enhancement
- Press Cmd+Option+P to enhance selected text
- Configure AI provider in Settings
- Supports Gemini and OpenRouter

#### Keyboard Cleaner
- Press Cmd+Option+L to lock keyboard
- Prevent accidental input
- ESC to unlock

## Troubleshooting

### Clipboard not capturing
1. Check Accessibility permissions in System Settings
2. Restart JoyaFix

### Snippets not expanding
1. Verify Accessibility permissions
2. Check trigger doesn't conflict with other shortcuts

### AI features not working
1. Verify API key in Settings
2. Check internet connection
3. Check API service status
```

---

## PHASE 9: Release Checklist (Week 10)

### 9.1 Pre-Release Checklist
```markdown
# RELEASE_CHECKLIST.md

## Code Quality
- [ ] All critical bugs fixed (Phase 1)
- [ ] Performance optimizations implemented (Phase 2)
- [ ] Architecture improvements complete (Phase 3)
- [ ] Security enhancements in place (Phase 4)

## Testing
- [ ] Unit tests passing (>80% coverage)
- [ ] Integration tests passing
- [ ] Performance benchmarks met
- [ ] Manual testing on macOS 14, 15

## Documentation
- [ ] API documentation generated
- [ ] User guide complete
- [ ] Release notes prepared

## Distribution
- [ ] Code signing configured
- [ ] Notarization tested
- [ ] DMG creation automated
- [ ] Sparkle appcast configured

## Compliance
- [ ] Privacy policy in place
- [ ] Terms of service
- [ ] Accessibility audit
- [ ] Data export feature tested
```

### 9.2 Monitoring Setup
```swift
// New file: ProductionMonitor.swift
class ProductionMonitor {
    static let shared = ProductionMonitor()

    func startMonitoring() {
        // Track app lifecycle
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            AnalyticsManager.shared.track(.featureUsed(name: "app_launched"))
        }

        // Track crashes
        CrashReporter.setup()

        // Track performance metrics
        startPerformanceTracking()
    }

    private func startPerformanceTracking() {
        // Monitor memory usage
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            let memoryInfo = mach_task_basic_info()
            AnalyticsManager.shared.track(.performanceMetric(
                name: "memory_usage_mb",
                value: Double(memoryInfo.resident_size) / 1024 / 1024
            ))
        }
    }
}

// Add to JoyaFixApp.swift:
func applicationDidFinishLaunching(_ notification: Notification) {
    // ... existing code ...

    #if !DEBUG
    ProductionMonitor.shared.startMonitoring()
    #endif
}
```

---

## SUMMARY: 10-Week Production Plan

### Week 1: Critical Bug Fixes (High Priority)
- Fix race conditions in file operations
- Implement path traversal protection
- Fix database recovery loops
- Secure weak reference access
- Strengthen API key validation

### Week 2: Performance Optimizations
- File system events instead of polling
- Database pagination for large datasets
- Cache frequently filtered lists
- Full hash for image deduplication

### Week 3: Architecture Improvements
- Database transaction safety
- Centralized error handling
- Task cancellation support
- Memory-efficient large file handling

### Week 4: Security Enhancements
- Content sanitization
- Clipboard validation
- Secure clipboard clearing
- Permission verification

### Week 5-6: Missing Production Features
- Comprehensive logging
- Analytics integration
- Robust update system
- Data export/import

### Week 7: Testing Infrastructure
- Unit test suite (>80% coverage)
- Integration tests
- Performance benchmarks
- Manual testing matrix

### Week 8: Deployment & Distribution
- Code signing
- Notarization
- DMG creation
- Sparkle auto-updates

### Week 9: Documentation
- API documentation
- User guide
- Troubleshooting guide

### Week 10: Release
- Pre-release checklist
- Monitoring setup
- Release notes
- Marketing materials

---

## SUCCESS METRICS

### Quality Metrics
- Zero critical bugs in production
- < 5% crash rate
- 99.9% uptime for AI services

### Performance Metrics
- Clipboard capture latency < 100ms
- Database queries < 50ms
- Snippet expansion < 10ms

### Security Metrics
- Zero security vulnerabilities
- All clipboard content validated
- Secure API key storage verified

### User Experience Metrics
- 4.5+ star rating
- < 5% uninstall rate
- 90% feature adoption rate

---

This plan addresses all issues found in the codebase and prepares JoyaFix for production deployment with robustness, security, and maintainability as core priorities.
