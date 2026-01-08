#if false
import Cocoa
import Foundation

@MainActor
class OCRHistoryManager: ObservableObject {
    static let shared = OCRHistoryManager()
    private init() {}
    
    func addScan(_ scan: OCRScan) {}
    func savePreviewImage(_ image: NSImage, for scan: OCRScan, completion: @escaping (String?) -> Void) {}
}
#endif
