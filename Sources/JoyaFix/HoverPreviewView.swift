import SwiftUI

/// Hover preview view that shows full content of clipboard item
struct HoverPreviewView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: item.isImage ? "photo" : "doc.text")
                    .foregroundColor(.accentColor)
                Text("Clipboard Content")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
            
            Divider()
            
            // Content
            if item.isImage {
                if let imagePath = item.imagePath, let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                } else {
                    Text("Image")
                        .foregroundColor(.secondary)
                }
            } else if item.isSensitive {
                Text("••••••")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    Text(item.textForPasting)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 250)
            }
            
            // Metadata
            Divider()
            HStack {
                Text(timeAgo(from: item.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                if !item.isImage {
                    Text("\(item.textForPasting.count) characters")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}
