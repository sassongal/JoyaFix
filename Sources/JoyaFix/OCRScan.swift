#if false
import Foundation
import AppKit

struct OCRScan: Codable, Identifiable {
    let id: UUID
    let date: Date
    let extractedText: String
    let previewImagePath: String?
    
    init(extractedText: String, id: UUID = UUID(), date: Date = Date(), previewImagePath: String? = nil) {
        self.id = id
        self.date = date
        self.extractedText = extractedText
        self.previewImagePath = previewImagePath
    }
    
    func withPreviewImagePath(_ path: String) -> OCRScan {
        return OCRScan(extractedText: extractedText, id: id, date: date, previewImagePath: path)
    }
}
#endif
