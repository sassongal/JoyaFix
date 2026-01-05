import SwiftUI

struct HistoryView: View {
    @ObservedObject var clipboardManager = ClipboardHistoryManager.shared
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var onPasteItem: (ClipboardItem) -> Void
    var onClose: () -> Void

    var filteredHistory: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardManager.history
        }
        return clipboardManager.history.filter { item in
            item.plainTextPreview.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("Search clipboard...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // History List
            if filteredHistory.isEmpty {
                EmptyStateView(isSearching: !searchText.isEmpty)
                    .frame(height: 200)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, item in
                                HistoryItemRow(
                                    item: item,
                                    isSelected: index == selectedIndex,
                                    onPaste: {
                                        onPasteItem(item)
                                    },
                                    onTogglePin: {
                                        clipboardManager.togglePin(for: item)
                                    },
                                    onDelete: {
                                        clipboardManager.deleteItem(item)
                                        if selectedIndex >= filteredHistory.count - 1 {
                                            selectedIndex = max(0, filteredHistory.count - 2)
                                        }
                                    }
                                )
                                .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: min(CGFloat(filteredHistory.count * 70 + 16), 400))
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack(spacing: 16) {
                FooterHintView(icon: "return", text: "Paste")
                FooterHintView(icon: "arrow.up.arrow.down", text: "Navigate")
                FooterHintView(icon: "command", text: "⌫ Clear")

                Spacer()

                Text("\(filteredHistory.count) items")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 400)
        .background(Color.clear) // Transparent to show blur
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredHistory.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if !filteredHistory.isEmpty {
                onPasteItem(filteredHistory[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onCommand(#selector(NSResponder.deleteBackward(_:))) {
            clipboardManager.clearHistory(keepPinned: false)
        }
    }
}

// MARK: - History Item Row

struct HistoryItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var contentIcon: String {
        let text = item.plainTextPreview.trimmingCharacters(in: .whitespacesAndNewlines)

        // URL detection
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return "link"
        }

        // Hex color detection
        if text.hasPrefix("#") && text.count == 7 {
            return "paintpalette"
        }

        // Email detection
        if text.contains("@") && text.contains(".") && !text.contains(" ") {
            return "envelope"
        }

        // Multi-line text
        if text.contains("\n") {
            return "doc.text"
        }

        // Default
        return "doc.plaintext"
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: contentIcon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.singleLineText(maxLength: 60))
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    // Timestamp
                    Text(timeAgo(from: item.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    // Character count
                    Text("\(item.plainTextPreview.count) chars")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Pin indicator
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }

            // Action buttons (show on hover)
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    Button(action: onTogglePin) {
                        Image(systemName: item.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onPaste()
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

// MARK: - Empty State

struct EmptyStateView: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "clipboard")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(isSearching ? "No results found" : "No clipboard history")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)

            Text(isSearching ? "Try a different search term" : "Copy something to get started")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Footer Hint

struct FooterHintView: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
