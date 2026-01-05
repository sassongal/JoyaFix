import Cocoa
import Foundation

@MainActor
class OCRHistoryManager: ObservableObject {
    static let shared = OCRHistoryManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var history: [OCRScan] = []
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = JoyaFixConstants.UserDefaultsKeys.ocrHistory
    private let maxHistoryCount = JoyaFixConstants.maxOCRHistoryCount
    private let previewImageDirectory: URL
    
    // Migration flag
    private let databaseMigrationKey = "OCRHistoryDatabaseMigrationCompleted"
    
    // Database manager for persistent storage (replaces UserDefaults)
    private let databaseManager = HistoryDatabaseManager.shared
    
    // MARK: - Initialization
    
    private init() {
        // Create directory for preview images
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        previewImageDirectory = appSupport.appendingPathComponent(JoyaFixConstants.FilePaths.ocrPreviewsDirectory, isDirectory: true)
        
        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: previewImageDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // This is a critical error, as the app cannot function without this directory.
            print("🔥🔥🔥 CRITICAL: Failed to create OCR previews directory at \(previewImageDirectory.path): \(error.localizedDescription)")
        }
        
        // CRITICAL FIX: Migrate to database first (one-time migration)
        if !UserDefaults.standard.bool(forKey: databaseMigrationKey) {
            migrateToDatabase()
            UserDefaults.standard.set(true, forKey: databaseMigrationKey)
        }
        
        loadHistory()
    }
    
    // MARK: - History Management
    
    /// Adds a new OCR scan to history, ensuring thread safety via @MainActor.
    func addScan(_ scan: OCRScan) {
        // Guard against empty scans
        guard !scan.extractedText.isEmpty else {
            print("⚠️ Skipping empty OCR scan")
            return
        }
        
        // All mutations now happen safely on the MainActor
        
        // Remove duplicate if exists (based on text content)
        let removedCount = history.count
        history.removeAll { $0.extractedText == scan.extractedText }
        if removedCount != history.count {
            print("📝 Removed duplicate OCR scan: \(scan.extractedText.prefix(30))...")
        }
        
        // Add to beginning
        history.insert(scan, at: 0)
        
        // Limit history size
        if history.count > maxHistoryCount {
            // Remove oldest scans and their preview images
            let scansToRemove = history.suffix(from: maxHistoryCount)
            var removedImages = 0
            for scanToRemove in scansToRemove {
                if let imagePath = scanToRemove.previewImagePath {
                    do {
                        try FileManager.default.removeItem(atPath: imagePath)
                        removedImages += 1
                    } catch {
                        print("⚠️ Failed to remove old preview image: \(imagePath) - \(error.localizedDescription)")
                    }
                }
            }
            history = Array(history.prefix(maxHistoryCount))
            print("🗑️ Removed \(scansToRemove.count) old OCR scans (\(removedImages) preview images deleted)")
        }
        
        // Save with error handling
        if saveHistory() {
            print("📸 Added OCR scan to history: \(scan.extractedText.prefix(30))...")
        } else {
            print("⚠️ OCR scan added but failed to save to UserDefaults")
        }
    }
    
    /// Saves a preview image asynchronously (resized and compressed) and returns the path via completion
    func savePreviewImage(_ image: NSImage, for scan: OCRScan, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            // Step 1: Validate image
            guard image.size.width > 0 && image.size.height > 0 else {
                print("❌ Invalid image size: \(image.size)")
                Task { @MainActor in
                    completion(nil)
                }
                return
            }
            
            // Step 2: Resize to thumbnail (max 300px, maintain aspect ratio)
            let maxDimension: CGFloat = 300
            let aspectRatio = image.size.width / image.size.height
            let newSize: NSSize
            if image.size.width > image.size.height {
                newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
            } else {
                newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
            }
            
            let resizedImage = NSImage(size: newSize)
            resizedImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
            resizedImage.unlockFocus()
            
            // Step 3: Convert to TIFF representation
            guard let tiffData = resizedImage.tiffRepresentation else {
                print("❌ Failed to convert resized image to TIFF representation")
                Task { @MainActor in
                    completion(nil)
                }
                return
            }
            
            // Step 4: Create bitmap representation
            guard let bitmapRep = NSBitmapImageRep(data: tiffData) else {
                print("❌ Failed to create bitmap representation from TIFF data (\(tiffData.count) bytes)")
                Task { @MainActor in
                    completion(nil)
                }
                return
            }
            
            // Step 5: Convert to JPEG with compression (0.7 quality)
            guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                print("❌ Failed to convert bitmap to JPEG representation")
                Task { @MainActor in
                    completion(nil)
                }
                return
            }
            
            // Step 6: Ensure directory exists
            do {
                try FileManager.default.createDirectory(at: self.previewImageDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("❌ Failed to create preview image directory: \(error.localizedDescription)")
                print("   Directory path: \(self.previewImageDirectory.path)")
                Task { @MainActor in
                    completion(nil)
                }
                return
            }
            
            // Step 7: Write JPEG data to file
            let fileName = "\(scan.id.uuidString).jpg"
            let fileURL = self.previewImageDirectory.appendingPathComponent(fileName)
            
            do {
                try jpegData.write(to: fileURL)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                print("✓ Preview image saved successfully (resized & compressed): \(fileURL.path) (\(fileSize) bytes)")
                Task { @MainActor in
                    completion(fileURL.path)
                }
            } catch {
                print("❌ Failed to write preview image to file: \(error.localizedDescription)")
                print("   File path: \(fileURL.path)")
                print("   JPEG data size: \(jpegData.count) bytes")
                print("   Error details: \(error)")
                Task { @MainActor in
                    completion(nil)
                }
            }
        }
    }
    
    /// Deletes a specific scan from history
    func deleteScan(_ scan: OCRScan) {
        // Remove preview image if exists
        if let imagePath = scan.previewImagePath {
            do {
                try FileManager.default.removeItem(atPath: imagePath)
            } catch {
                print("🔥 Failed to remove preview image for deleted scan at \(imagePath): \(error.localizedDescription)")
            }
        }
        
        history.removeAll { $0.id == scan.id }
        saveHistory()
        print("🗑️ Deleted OCR scan: \(scan.extractedText.prefix(30))...")
    }
    
    /// Clears all OCR history
    func clearHistory() {
        // Remove all preview images
        for scan in history {
            if let imagePath = scan.previewImagePath {
                do {
                    try FileManager.default.removeItem(atPath: imagePath)
                } catch {
                    print("🔥 Failed to remove preview image while clearing history at \(imagePath): \(error.localizedDescription)")
                }
            }
        }
        
        history.removeAll()
        saveHistory()
        print("🗑️ OCR history cleared")
    }
    
    /// Copies scan text to clipboard
    func copyScanToClipboard(_ scan: OCRScan) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(scan.extractedText, forType: .string)
        print("📋 Copied OCR scan text to clipboard")
    }
    
    // MARK: - Persistence
    
    /// Saves OCR history to database (replaces UserDefaults)
    /// Returns true if save was successful, false otherwise
    /// Includes robust error handling with fallback to UserDefaults
    @discardableResult
    private func saveHistory() -> Bool {
        // CRITICAL FIX: Save to database instead of UserDefaults
        do {
            try databaseManager.saveOCRHistory(history)
            print("✓ OCR history saved to database (\(history.count) scans)")
            
            // Clear fallback data if database save succeeded
            if UserDefaults.standard.data(forKey: userDefaultsKey) != nil {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
            UserDefaults.standard.removeObject(forKey: "OCRHistoryFallbackActive")
            UserDefaults.standard.removeObject(forKey: "OCRHistoryFallbackTimestamp")
            
            return true
        } catch {
            // Detailed error logging
            let errorDescription = error.localizedDescription
            let isLocked = DatabaseError.isDatabaseLocked(error)
            let isIOError = DatabaseError.isIOError(error)
            
            if isLocked {
                print("🔒 Database is locked - using fallback to UserDefaults")
                print("   Error details: \(errorDescription)")
            } else if isIOError {
                print("💾 Database I/O error - using fallback to UserDefaults")
                print("   Error details: \(errorDescription)")
            } else {
                print("❌ Failed to save OCR history to database: \(errorDescription)")
            }
            
            // Fallback to UserDefaults if database fails (Insurance Policy)
            let encoder = JSONEncoder()
            do {
                let encoded = try encoder.encode(history)
                UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
                print("⚠️ Fallback: Saved \(history.count) OCR scans to UserDefaults (\(encoded.count) bytes)")
                
                // Log fallback status for monitoring
                UserDefaults.standard.set(true, forKey: "OCRHistoryFallbackActive")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "OCRHistoryFallbackTimestamp")
                
                return true
            } catch {
                print("🔥 CRITICAL: Failed to save to both database and UserDefaults!")
                print("   Encoding error: \(error.localizedDescription)")
                return false
            }
        }
    }
    
    /// Loads OCR history from database (replaces UserDefaults)
    /// Includes robust error handling with fallback to UserDefaults
    private func loadHistory() {
        // CRITICAL FIX: Load from database instead of UserDefaults
        do {
            let items = try databaseManager.loadOCRHistory()
            history = items
            print("✓ Loaded \(history.count) OCR scans from database")
            
            // Check if we have fallback data that needs to be migrated back
            if UserDefaults.standard.bool(forKey: "OCRHistoryFallbackActive") {
                print("🔄 Detected fallback data - attempting to migrate back to database...")
                // Try to save current database state, then merge with fallback if needed
                if let fallbackData = UserDefaults.standard.data(forKey: userDefaultsKey) {
                    let decoder = JSONDecoder()
                    if let fallbackItems = try? decoder.decode([OCRScan].self, from: fallbackData) {
                        // Merge fallback items with database items (avoid duplicates)
                        var mergedItems = items
                        for fallbackItem in fallbackItems {
                            if !mergedItems.contains(where: { $0.id == fallbackItem.id }) {
                                mergedItems.append(fallbackItem)
                            }
                        }
                        // Sort by date
                        mergedItems.sort { $0.date > $1.date }
                        history = mergedItems
                        
                        // Try to save merged data back to database
                        do {
                            try databaseManager.saveOCRHistory(mergedItems)
                            // Clear fallback data after successful migration
                            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                            UserDefaults.standard.removeObject(forKey: "OCRHistoryFallbackActive")
                            UserDefaults.standard.removeObject(forKey: "OCRHistoryFallbackTimestamp")
                            print("✓ Successfully migrated fallback data back to database")
                        } catch {
                            print("⚠️ Could not migrate fallback data back to database: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            // Detailed error logging
            let errorDescription = error.localizedDescription
            let isLocked = DatabaseError.isDatabaseLocked(error)
            let isIOError = DatabaseError.isIOError(error)
            
            if isLocked {
                print("🔒 Database is locked - using fallback from UserDefaults")
                print("   Error details: \(errorDescription)")
            } else if isIOError {
                print("💾 Database I/O error - using fallback from UserDefaults")
                print("   Error details: \(errorDescription)")
            } else {
                print("❌ Failed to load OCR history from database: \(errorDescription)")
            }
            
            // Fallback to UserDefaults if database fails
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
                print("ℹ️ No OCR history found (first run)")
                history = []
                return
            }
            
            let decoder = JSONDecoder()
            do {
                let decoded = try decoder.decode([OCRScan].self, from: data)
                history = decoded
                print("⚠️ Fallback: Loaded \(history.count) OCR scans from UserDefaults (\(data.count) bytes)")
                
                // Mark fallback as active
                UserDefaults.standard.set(true, forKey: "OCRHistoryFallbackActive")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "OCRHistoryFallbackTimestamp")
            } catch {
                print("🔥 CRITICAL: Failed to decode fallback data: \(error.localizedDescription)")
                history = []
            }
        }
    }
    
    /// Migrates OCR history from UserDefaults to database (one-time migration)
    /// Includes corruption detection and safe error handling
    private func migrateToDatabase() {
        print("🔄 Migrating OCR history from UserDefaults to database...")
        
        do {
            let success = databaseManager.migrateOCRHistoryFromUserDefaults()
            if success {
                // Reload from database after migration
                loadHistory()
            } else {
                print("⚠️ Migration returned false - keeping data in UserDefaults as fallback")
            }
        } catch {
            // Handle corruption errors gracefully
            if DatabaseError.isCorruptionError(error) {
                print("⚠️ Database corruption detected during migration - keeping data in UserDefaults")
                // Don't crash - keep using UserDefaults
            } else {
                print("❌ Migration failed: \(error.localizedDescription)")
                // Keep using UserDefaults as fallback
            }
        }
    }
}

