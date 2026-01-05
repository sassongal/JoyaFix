import Cocoa
import Foundation

class OCRHistoryManager: ObservableObject {
    static let shared = OCRHistoryManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var history: [OCRScan] = []
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = JoyaFixConstants.UserDefaultsKeys.ocrHistory
    private let maxHistoryCount = JoyaFixConstants.maxOCRHistoryCount
    private let previewImageDirectory: URL
    
    // MARK: - Initialization
    
    private init() {
        // Create directory for preview images
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        previewImageDirectory = appSupport.appendingPathComponent(JoyaFixConstants.FilePaths.ocrPreviewsDirectory, isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: previewImageDirectory, withIntermediateDirectories: true, attributes: nil)
        
        loadHistory()
    }
    
    // MARK: - History Management
    
    /// Adds a new OCR scan to history
    func addScan(_ scan: OCRScan) {
        // FIX: Enhanced error handling
        guard !scan.extractedText.isEmpty else {
            print("⚠️ Skipping empty OCR scan")
            return
        }
        
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
            try? FileManager.default.removeItem(atPath: imagePath)
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
                try? FileManager.default.removeItem(atPath: imagePath)
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
    
    /// Saves OCR history to UserDefaults
    /// Returns true if save was successful, false otherwise
    @discardableResult
    private func saveHistory() -> Bool {
        let encoder = JSONEncoder()
        do {
            let encoded = try encoder.encode(history)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("✓ OCR history saved (\(history.count) scans, \(encoded.count) bytes)")
            return true
        } catch {
            print("❌ Failed to encode OCR history: \(error.localizedDescription)")
            print("   History count: \(history.count)")
            return false
        }
    }
    
    /// Loads OCR history from UserDefaults
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("ℹ️ No OCR history found in UserDefaults (first run)")
            return
        }
        
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode([OCRScan].self, from: data)
            history = decoded
            print("✓ Loaded \(history.count) OCR scans from history (\(data.count) bytes)")
        } catch {
            print("❌ Failed to decode OCR history: \(error.localizedDescription)")
            print("   Data size: \(data.count) bytes")
            // Reset to empty history on decode failure
            history = []
        }
    }
}

