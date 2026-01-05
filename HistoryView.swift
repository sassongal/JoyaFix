import SwiftUI
import CoreGraphics
import ApplicationServices
import Carbon

struct HistoryView: View {
    @ObservedObject var clipboardManager = ClipboardHistoryManager.shared
    @ObservedObject var ocrManager = OCRHistoryManager.shared
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var selectedTab = 0 // 0 = Clipboard, 1 = OCR Scans
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
    
    var filteredOCRScans: [OCRScan] {
        if searchText.isEmpty {
            return ocrManager.history
        }
        return ocrManager.history.filter { scan in
            scan.extractedText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Clipboard Tab
            ClipboardHistoryTabView(
                filteredHistory: filteredHistory,
                searchText: $searchText,
                selectedIndex: $selectedIndex,
                isSearchFocused: $isSearchFocused,
                onPasteItem: onPasteItem,
                onClose: onClose
            )
            .tabItem {
                Label("Clipboard", systemImage: "clipboard")
            }
            .tag(0)
            
            // OCR Scans Tab
            OCRScansTabView(
                filteredScans: filteredOCRScans,
                searchText: $searchText,
                selectedIndex: $selectedIndex,
                isSearchFocused: $isSearchFocused,
                onClose: onClose
            )
            .tabItem {
                Label("OCR Scans", systemImage: "viewfinder")
            }
            .tag(1)
        }
        .frame(width: 400)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
    }
}

// MARK: - Clipboard History Tab

struct ClipboardHistoryTabView: View {
    let filteredHistory: [ClipboardItem]
    @Binding var searchText: String
    @Binding var selectedIndex: Int
    @FocusState.Binding var isSearchFocused: Bool
    var onPasteItem: (ClipboardItem) -> Void
    var onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Quick Actions Section (Pinned at top)
            QuickActionsSection()
            
            Divider()
            
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
                                        ClipboardHistoryManager.shared.togglePin(for: item)
                                    },
                                    onDelete: {
                                        ClipboardHistoryManager.shared.deleteItem(item)
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
            ClipboardHistoryManager.shared.clearHistory(keepPinned: false)
        }
    }
}

// MARK: - OCR Scans Tab

struct OCRScansTabView: View {
    let filteredScans: [OCRScan]
    @Binding var searchText: String
    @Binding var selectedIndex: Int
    @FocusState.Binding var isSearchFocused: Bool
    var onClose: () -> Void
    @ObservedObject var ocrManager = OCRHistoryManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("Search OCR scans...", text: $searchText)
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

            // OCR Scans List
            if filteredScans.isEmpty {
                EmptyStateView(isSearching: !searchText.isEmpty, isOCR: true)
                    .frame(height: 200)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(filteredScans.enumerated()), id: \.element.id) { index, scan in
                                OCRScanRow(
                                    scan: scan,
                                    isSelected: index == selectedIndex,
                                    onCopy: {
                                        ocrManager.copyScanToClipboard(scan)
                                    },
                                    onDelete: {
                                        ocrManager.deleteScan(scan)
                                        if selectedIndex >= filteredScans.count - 1 {
                                            selectedIndex = max(0, filteredScans.count - 2)
                                        }
                                    }
                                )
                                .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: min(CGFloat(filteredScans.count * 70 + 16), 400))
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
                FooterHintView(icon: "return", text: "Copy")
                FooterHintView(icon: "arrow.up.arrow.down", text: "Navigate")
                FooterHintView(icon: "command", text: "⌫ Clear")

                Spacer()

                Text("\(filteredScans.count) scans")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 400)
        .background(Color.clear)
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredScans.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if !filteredScans.isEmpty {
                ocrManager.copyScanToClipboard(filteredScans[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onCommand(#selector(NSResponder.deleteBackward(_:))) {
            ocrManager.clearHistory()
        }
    }
}

// MARK: - OCR Scan Row

struct OCRScanRow: View {
    let scan: OCRScan
    let isSelected: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: "viewfinder")
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.singleLinePreview(maxLength: 60))
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // Timestamp
                    Text(timeAgo(from: scan.date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    // Character count
                    Text("\(scan.extractedText.count) chars")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action buttons (show on hover)
            if isHovered || isSelected {
                HStack(spacing: 4) {
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
            onCopy()
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
    let isOCR: Bool
    
    init(isSearching: Bool, isOCR: Bool = false) {
        self.isSearching = isSearching
        self.isOCR = isOCR
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : (isOCR ? "viewfinder" : "clipboard"))
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(isSearching ? "No results found" : (isOCR ? "No OCR scans" : "No clipboard history"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)

            Text(isSearching ? "Try a different search term" : (isOCR ? "Capture text from screen to get started" : "Copy something to get started"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Quick Actions Section

struct QuickActionsSection: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            convertClipboardText()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Convert Text Layout")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(settings.hotkeyDisplayString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
    
    private func convertClipboardText() {
        // Read from clipboard
        let pasteboard = NSPasteboard.general
        guard let copiedText = pasteboard.string(forType: .string), !copiedText.isEmpty else {
            print("❌ No text in clipboard")
            return
        }
        
        print("📋 Original: '\(copiedText)'")
        
        // Convert the text
        let convertedText = TextConverter.convert(copiedText)
        print("✅ Converted: '\(convertedText)'")
        
        // Notify clipboard manager to ignore this write
        ClipboardHistoryManager.shared.notifyInternalWrite()
        
        // Write back to clipboard
        pasteboard.clearContents()
        pasteboard.setString(convertedText, forType: .string)
        print("📋 Converted text written to clipboard")
        
        // Optionally auto-paste if enabled
        if settings.autoPasteAfterConvert {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                simulatePaste()
                
                // Play success sound if enabled
                if settings.playSoundOnConvert {
                    SoundManager.shared.playSuccess()
                }
            }
        } else {
            // Still play sound even if not pasting
            if settings.playSoundOnConvert {
                SoundManager.shared.playSuccess()
            }
        }
    }
    
    private func simulatePaste() {
        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        keyDownEvent.flags = CGEventFlags.maskCommand
        keyUpEvent.flags = CGEventFlags.maskCommand
        
        let location = CGEventTapLocation.cghidEventTap
        keyDownEvent.post(tap: location)
        usleep(10000) // 10ms delay
        keyUpEvent.post(tap: location)
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
