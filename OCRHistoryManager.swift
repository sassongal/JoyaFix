import Cocoa
import Foundation

class OCRHistoryManager: ObservableObject {
    static let shared = OCRHistoryManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var history: [OCRScan] = []
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = "OCRHistory"
    private let maxHistoryCount = 50 // Maximum number of OCR scans to keep
    private let previewImageDirectory: URL
    
    // MARK: - Initialization
    
    private init() {
        // Create directory for preview images
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        previewImageDirectory = appSupport.appendingPathComponent("JoyaFix/OCRPreviews", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: previewImageDirectory, withIntermediateDirectories: true, attributes: nil)
        
        loadHistory()
    }
    
    // MARK: - History Management
    
    /// Adds a new OCR scan to history
    func addScan(_ scan: OCRScan) {
        // Remove duplicate if exists (based on text content)
        history.removeAll { $0.extractedText == scan.extractedText }
        
        // Add to beginning
        history.insert(scan, at: 0)
        
        // Limit history size
        if history.count > maxHistoryCount {
            // Remove oldest scans and their preview images
            let scansToRemove = history.suffix(from: maxHistoryCount)
            for scan in scansToRemove {
                if let imagePath = scan.previewImagePath {
                    try? FileManager.default.removeItem(atPath: imagePath)
                }
            }
            history = Array(history.prefix(maxHistoryCount))
        }
        
        saveHistory()
        print("📸 Added OCR scan to history: \(scan.extractedText.prefix(30))...")
    }
    
    /// Saves a preview image and returns the path
    func savePreviewImage(_ image: NSImage, for scan: OCRScan) -> String? {
        guard let imageData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: imageData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let fileName = "\(scan.id.uuidString).png"
        let fileURL = previewImageDirectory.appendingPathComponent(fileName)
        
        do {
            try pngData.write(to: fileURL)
            return fileURL.path
        } catch {
            print("❌ Failed to save preview image: \(error)")
            return nil
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
    private func saveHistory() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(history) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    /// Loads OCR history from UserDefaults
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([OCRScan].self, from: data) {
                history = decoded
                print("✓ Loaded \(history.count) OCR scans from history")
            }
        }
    }
}

