import SwiftUI

/// Grid card view for clipboard items
struct HistoryItemGridCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let itemSize: PopoverLayoutSettings.ItemSize
    let theme: PopoverLayoutSettings.Theme
    let onPaste: (PasteFormattingOption) -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var showPreview = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail or Icon
            if let imagePath = item.imagePath, let nsImage = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: itemSize == .compact ? 60 : (itemSize == .large ? 120 : 80))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                HStack {
                    Image(systemName: contentIcon)
                        .font(.system(size: itemSize.iconSize))
                        .foregroundColor(isSelected ? theme.accentColor : .secondary)
                    Spacer()
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                .frame(height: itemSize == .compact ? 30 : (itemSize == .large ? 50 : 40))
            }
            
            // Content
            if !item.isImage {
                Text(item.plainTextPreview)
                    .font(.system(size: itemSize.fontSize - 1))
                    .lineLimit(itemSize == .compact ? 2 : 3)
                    .foregroundColor(.primary)
            }
            
            // Metadata
            HStack {
                Text(timeAgo(from: item.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                if item.isSensitive {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? theme.accentColor.opacity(0.15) : (isHovered ? theme.accentColor.opacity(0.08) : theme.backgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? theme.accentColor : (isHovered ? theme.accentColor.opacity(0.3) : Color.clear), lineWidth: isSelected ? 1.5 : 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            showPreview = true
        }
        .onTapGesture {
            let event = NSApp.currentEvent
            let modifiers = event?.modifierFlags ?? []
            let option: PasteFormattingOption = modifiers.contains(.shift) ? .plainText : .normal
            onPaste(option)
        }
        .popover(isPresented: $showPreview) {
            EnhancedClipboardPreview(item: item)
                .frame(width: 600, height: 400)
                .padding()
        }
        .contextMenu {
            Button(action: onTogglePin) {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var contentIcon: String {
        let text = item.plainTextPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return "link"
        }
        if text.hasPrefix("#") && text.count == 7 {
            return "paintpalette"
        }
        if text.contains("@") && text.contains(".") && !text.contains(" ") {
            return "envelope"
        }
        if text.contains("\n") {
            return "doc.text"
        }
        return "doc.plaintext"
    }
    
    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "now"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        } else {
            return "\(Int(seconds / 86400))d"
        }
    }
}
