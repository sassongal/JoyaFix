import Foundation
import AppKit

/// Model representing an OCR scan result
struct OCRScan: Codable, Identifiable {
    let id: UUID
    let date: Date
    let extractedText: String
    let previewImagePath: String? // Path to saved preview image (optional)
    
    init(id: UUID = UUID(), date: Date = Date(), extractedText: String, previewImagePath: String? = nil) {
        self.id = id
        self.date = date
        self.extractedText = extractedText
        self.previewImagePath = previewImagePath
    }
    
    /// Creates a new OCRScan with updated preview image path
    func withPreviewImagePath(_ path: String?) -> OCRScan {
        return OCRScan(id: self.id, date: self.date, extractedText: self.extractedText, previewImagePath: path)
    }
    
    /// Returns a preview image if available
    var previewImage: NSImage? {
        guard let path = previewImagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }
    
    /// Returns a single-line preview of the text
    func singleLinePreview(maxLength: Int = 60) -> String {
        let singleLine = extractedText.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if singleLine.count > maxLength {
            return String(singleLine.prefix(maxLength)) + "..."
        }
        return singleLine
    }
}

