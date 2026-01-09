import SwiftUI
import CoreGraphics
import ApplicationServices
import Carbon

struct HistoryView: View {
    @ObservedObject var clipboardManager = ClipboardHistoryManager.shared
    @ObservedObject var promptManager = PromptLibraryManager.shared
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var selectedTab = 0 // 0 = Clipboard, 1 = OCR Scans, 2 = Library
    @FocusState private var isSearchFocused: Bool
    @State private var editingPrompt: PromptTemplate?
    @State private var showingEditor = false

    var onPasteItem: (ClipboardItem, Bool) -> Void  // Bool indicates plainTextOnly
    var onClose: () -> Void

    var filteredHistory: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardManager.history
        }
        // Use fuzzy search with threshold
        let threshold = 0.3 // Minimum score to show (0.0 = no match, 1.0 = exact match)
        return clipboardManager.history.filter { item in
            let score = item.plainTextPreview.fuzzyScore(word: searchText)
            return score >= threshold
        }.sorted { item1, item2 in
            // Sort by score (highest first)
            let score1 = item1.plainTextPreview.fuzzyScore(word: searchText)
            let score2 = item2.plainTextPreview.fuzzyScore(word: searchText)
            return score1 > score2
        }
    }
    
    var filteredPrompts: [PromptTemplate] {
        if searchText.isEmpty {
            // Sort by lastUsed (most recent first), then by title
            return promptManager.prompts.sorted { prompt1, prompt2 in
                if let date1 = prompt1.lastUsed, let date2 = prompt2.lastUsed {
                    return date1 > date2
                } else if prompt1.lastUsed != nil {
                    return true
                } else if prompt2.lastUsed != nil {
                    return false
                } else {
                    return prompt1.title < prompt2.title
                }
            }
        }
        // Use fuzzy search with threshold
        let threshold = 0.3
        return promptManager.prompts.filter { prompt in
            let titleScore = prompt.title.fuzzyScore(word: searchText)
            let contentScore = prompt.content.fuzzyScore(word: searchText)
            return max(titleScore, contentScore) >= threshold
        }.sorted { prompt1, prompt2 in
            // Sort by score (highest first)
            let score1 = max(prompt1.title.fuzzyScore(word: searchText), prompt1.content.fuzzyScore(word: searchText))
            let score2 = max(prompt2.title.fuzzyScore(word: searchText), prompt2.content.fuzzyScore(word: searchText))
            return score1 > score2
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
            
            // Scratchpad Tab
            ScratchpadTabView(onClose: onClose)
                .tabItem {
                    Label("Scratchpad", systemImage: "note.text")
                }
                .tag(1)
            
            // Library Tab
            PromptLibraryTabView(
                filteredPrompts: filteredPrompts,
                searchText: $searchText,
                selectedIndex: $selectedIndex,
                isSearchFocused: $isSearchFocused,
                editingPrompt: $editingPrompt,
                showingEditor: $showingEditor,
                onClose: onClose
            )
            .tabItem {
                Label(NSLocalizedString("library.tab.title", comment: "Library"), systemImage: "book")
            }
            .tag(2)
            
            // Vision Lab Tab
            VisionLabView()
                .tabItem {
                    Label("Vision Lab", systemImage: "eye")
                }
                .tag(3)
        }
        .frame(width: 400)
        .onChange(of: selectedTab) { oldValue, newValue in
            // Notify AppDelegate to resize popover when tab changes
            NotificationCenter.default.post(name: NSNotification.Name("JoyaFixResizePopover"), object: nil, userInfo: ["tab": newValue])
        }
        .sheet(isPresented: $showingEditor) {
            if let prompt = editingPrompt {
                PromptEditorView(
                    prompt: prompt,
                    onSave: { updatedPrompt in
                        if promptManager.prompts.contains(where: { $0.id == updatedPrompt.id }) {
                            promptManager.updatePrompt(updatedPrompt)
                        } else {
                            promptManager.addPrompt(updatedPrompt)
                        }
                        editingPrompt = nil
                        showingEditor = false
                    },
                    onCancel: {
                        editingPrompt = nil
                        showingEditor = false
                    }
                )
            } else {
                PromptEditorView(
                    prompt: nil,
                    onSave: { newPrompt in
                        promptManager.addPrompt(newPrompt)
                        editingPrompt = nil
                        showingEditor = false
                    },
                    onCancel: {
                        editingPrompt = nil
                        showingEditor = false
                    }
                )
            }
        }
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
    var onPasteItem: (ClipboardItem, Bool) -> Void  // Bool indicates plainTextOnly
    var onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Tools Section (Caffeine, Color Picker)
            ToolsSection()
            
            Divider()
            
            // Quick Actions Section (Convert Text)
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
                                    onPaste: { plainTextOnly in
                                        onPasteItem(item, plainTextOnly)
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
                FooterHintView(icon: "shift", text: "⇧ Plain Text")
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
            // CRITICAL FIX: Force refresh of history when view appears
            // This ensures history is displayed even on first open
            if ClipboardHistoryManager.shared.history.isEmpty {
                // History might not be loaded yet, trigger a refresh
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Force SwiftUI to refresh by accessing history
                    _ = ClipboardHistoryManager.shared.history
                }
            }
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
                // Check if Shift is held for plain text paste
                let isShiftHeld = NSEvent.modifierFlags.contains(.shift)
                onPasteItem(filteredHistory[selectedIndex], isShiftHeld)
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

// MARK: - History Item Row

struct HistoryItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onPaste: (Bool) -> Void  // Bool indicates plainTextOnly
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
            // Icon or Image Thumbnail
            if let imagePath = item.imagePath, let nsImage = NSImage(contentsOfFile: imagePath) {
                // Show image thumbnail
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            } else {
                // Show icon for text items
                HStack(spacing: 4) {
                    Image(systemName: contentIcon)
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    
                    // Show red lock icon if item is sensitive (password)
                    if item.isSensitive {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                .frame(width: 24)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                if item.isImage {
                    Text("Image")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                } else {
                    // Mask sensitive content (passwords) for security
                    if item.isSensitive {
                        Text("••••••")
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(item.singleLineText(maxLength: 60))
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundColor(.primary)
                    }
                }

                HStack(spacing: 8) {
                    // Timestamp
                    Text(timeAgo(from: item.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    // Character count or image indicator
                    if item.isImage {
                        Text("Image")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else if item.isSensitive {
                        // Don't show character count for sensitive items
                        Text("Password")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(item.plainTextPreview.count) chars")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
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
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.3) : Color.clear), lineWidth: isSelected ? 1.5 : 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            // Check modifier keys for plain text paste
            let event = NSApp.currentEvent
            let isShiftHeld = event?.modifierFlags.contains(.shift) ?? false
            let isOptionHeld = event?.modifierFlags.contains(.option) ?? false
            let plainTextOnly = isShiftHeld || isOptionHeld
            onPaste(plainTextOnly)
        }
        .help(tooltipText) // Display full text content or image info on hover
    }
    
    private var tooltipText: String {
        if let imagePath = item.imagePath {
             return "Image: \(imagePath)"
        }
        // Return full text content for tooltip (handles multi-line and long text)
        return item.textForPasting
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

// MARK: - Tools Section

struct ToolsSection: View {
    @ObservedObject private var caffeineManager = CaffeineManager.shared
    @State private var isHoveredCaffeine = false
    @State private var isHoveredColor = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Section Header
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Tools")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // Tools Grid
            HStack(spacing: 8) {
                // Caffeine Mode Toggle
                Button(action: {
                    caffeineManager.toggle()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 14))
                            .foregroundColor(caffeineManager.isActive ? .orange : .secondary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep Awake")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Text(caffeineManager.isActive ? "Active" : "Inactive")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveredCaffeine ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHoveredCaffeine ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveredCaffeine = hovering
                }
                
                // Color Picker
                Button(action: {
                    ColorPickerManager.shared.pickColor()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        
                        Text("Pick Color")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveredColor ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHoveredColor ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveredColor = hovering
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
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
            .padding(8) // Reduced from 10
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

// MARK: - Prompt Library Tab

struct PromptLibraryTabView: View {
    let filteredPrompts: [PromptTemplate]
    @Binding var searchText: String
    @Binding var selectedIndex: Int
    @FocusState.Binding var isSearchFocused: Bool
    @Binding var editingPrompt: PromptTemplate?
    @Binding var showingEditor: Bool
    var onClose: () -> Void
    @ObservedObject var promptManager = PromptLibraryManager.shared
    @State private var selectedCategory: PromptCategory? = nil
    
    // Computed: Get prompts to display based on search and category
    var displayedPrompts: [PromptTemplate] {
        let categoryFiltered = selectedCategory == nil ? filteredPrompts : filteredPrompts.filter { $0.category == selectedCategory }
        return categoryFiltered
    }
    
    var body: some View {
        HSplitView {
            // LEFT: Sidebar with Categories
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    TextField(NSLocalizedString("library.search.placeholder", comment: "Search prompts..."), text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .font(.system(size: 11))

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                Divider()
                
                // Categories List
                List(selection: $selectedCategory) {
                    Section("Categories") {
                        // "All" option
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(.blue)
                                .frame(width: 16)
                            Text("All")
                            Spacer()
                            Text("\(filteredPrompts.count)")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .tag(nil as PromptCategory?)
                        
                        ForEach(PromptCategory.allCases) { category in
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundColor(category.color)
                                    .frame(width: 16)
                                Text(category.rawValue)
                                    .font(.system(size: 12))
                                Spacer()
                                Text("\(promptManager.prompts(in: category).count)")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                            }
                            .tag(category as PromptCategory?)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 180)
            }
            .frame(width: 200)

            // RIGHT: Prompts List
            VStack(spacing: 0) {
                // Add Prompt Button
                HStack {
                    Button(action: {
                        editingPrompt = nil
                        showingEditor = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text(NSLocalizedString("library.add.new", comment: "Add Prompt"))
                                .font(.system(size: 13))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()

                // Prompts List
                if displayedPrompts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "book")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text(NSLocalizedString("library.empty.state", comment: "No prompts found. Create your own!"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .frame(height: 200)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            // Group by category if "All" is selected, otherwise show flat list
                            if selectedCategory == nil && searchText.isEmpty {
                                LazyVStack(spacing: 12) {
                                    ForEach(PromptCategory.allCases) { category in
                                        let categoryPrompts = promptManager.prompts(in: category)
                                        if !categoryPrompts.isEmpty {
                                            CategorySection(
                                                category: category,
                                                prompts: categoryPrompts,
                                                selectedIndex: $selectedIndex,
                                                promptManager: promptManager,
                                                editingPrompt: $editingPrompt,
                                                showingEditor: $showingEditor,
                                                onClose: onClose
                                            )
                                        }
                                    }
                                }
                                .padding(8)
                            } else {
                                LazyVStack(spacing: 6) {
                                    ForEach(Array(displayedPrompts.enumerated()), id: \.element.id) { index, prompt in
                                        PromptRowView(
                                            prompt: prompt,
                                            isSelected: index == selectedIndex,
                                            onCopy: {
                                                promptManager.copyPromptToClipboard(prompt)
                                                onClose()
                                            },
                                            onEdit: {
                                                editingPrompt = prompt
                                                showingEditor = true
                                            },
                                            onDelete: {
                                                promptManager.deletePrompt(prompt)
                                                if selectedIndex >= displayedPrompts.count - 1 {
                                                    selectedIndex = max(0, displayedPrompts.count - 2)
                                                }
                                            }
                                        )
                                        .id(index)
                                    }
                                }
                                .padding(8)
                            }
                        }
                        .frame(height: min(CGFloat(displayedPrompts.count * 70 + 16), 400))
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
                    FooterHintView(icon: "return", text: NSLocalizedString("library.action.copy", comment: "Copy"))
                    FooterHintView(icon: "arrow.up.arrow.down", text: "Navigate")
                    FooterHintView(icon: "plus", text: NSLocalizedString("library.add.new", comment: "Add Prompt"))

                    Spacer()

                    Text("\(displayedPrompts.count) prompts")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .frame(width: 600, height: 500)
        .background(Color.clear)
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < displayedPrompts.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if !displayedPrompts.isEmpty {
                promptManager.copyPromptToClipboard(displayedPrompts[selectedIndex])
                onClose()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress("n") {
            if NSEvent.modifierFlags.contains(.command) {
                editingPrompt = nil
                showingEditor = true
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - Category Section View

struct CategorySection: View {
    let category: PromptCategory
    let prompts: [PromptTemplate]
    @Binding var selectedIndex: Int
    @ObservedObject var promptManager: PromptLibraryManager
    @Binding var editingPrompt: PromptTemplate?
    @Binding var showingEditor: Bool
    var onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category Header
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                    .font(.system(size: 14))
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(prompts.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(category.color.opacity(0.1))
            .cornerRadius(6)
            
            // Prompts in this category
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                PromptRowView(
                    prompt: prompt,
                    isSelected: false, // Category view doesn't use selection
                    onCopy: {
                        promptManager.copyPromptToClipboard(prompt)
                        onClose()
                    },
                    onEdit: {
                        editingPrompt = prompt
                        showingEditor = true
                    },
                    onDelete: {
                        promptManager.deletePrompt(prompt)
                    }
                )
            }
        }
    }
}

// MARK: - Prompt Row View

struct PromptRowView: View {
    let prompt: PromptTemplate
    let isSelected: Bool
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: prompt.isSystem ? "star.fill" : "doc.text")
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .accentColor : (prompt.isSystem ? .orange : .secondary))
                .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(truncatedContent)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons (show on hover)
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    if !prompt.isSystem {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
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
        .help(prompt.content) // Display full prompt content on hover
    }
    
    private var truncatedContent: String {
        let maxLength = 60
        if prompt.content.count > maxLength {
            return String(prompt.content.prefix(maxLength)) + "..."
        }
        return prompt.content
    }
}

// MARK: - Prompt Editor View

struct PromptEditorView: View {
    let prompt: PromptTemplate?
    let onSave: (PromptTemplate) -> Void
    let onCancel: () -> Void
    
    @State private var title: String
    @State private var content: String
    @FocusState private var isTitleFocused: Bool
    
    init(prompt: PromptTemplate?, onSave: @escaping (PromptTemplate) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: prompt?.title ?? "")
        _content = State(initialValue: prompt?.content ?? "")
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text(prompt == nil ? NSLocalizedString("library.editor.title.add", comment: "New Prompt") : NSLocalizedString("library.editor.title.edit", comment: "Edit Prompt"))
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 20)
            
            // Form
            VStack(alignment: .leading, spacing: 12) {
                // Title field
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("library.editor.title.label", comment: "Title"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTitleFocused)
                }
                
                // Content field
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("library.editor.content.label", comment: "Prompt Content"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $content)
                        .frame(height: 200)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 20)
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text(NSLocalizedString("library.editor.cancel", comment: "Cancel"))
                        .frame(width: 80)
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: {
                    let newPrompt = PromptTemplate(
                        id: prompt?.id ?? UUID(),
                        title: title,
                        content: content,
                        isSystem: prompt?.isSystem ?? false,
                        lastUsed: prompt?.lastUsed
                    )
                    onSave(newPrompt)
                }) {
                    Text(NSLocalizedString("library.editor.save", comment: "Save"))
                        .frame(width: 80)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 400)
        .onAppear {
            isTitleFocused = true
        }
    }
}

// MARK: - Scratchpad Tab

struct ScratchpadTabView: View {
    @ObservedObject private var scratchpadManager = ScratchpadManager.shared
    var onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Scratchpad")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: {
                    scratchpadManager.clear()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Text Editor
            TextEditor(text: $scratchpadManager.content)
                .font(.system(size: 13))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer
            HStack {
                Text("Auto-saves as you type")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(scratchpadManager.content.count) chars")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 400)
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
