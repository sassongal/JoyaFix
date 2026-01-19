import SwiftUI
import CoreGraphics
import ApplicationServices
import Carbon

struct HistoryView: View {
    @ObservedObject var clipboardManager = ClipboardHistoryManager.shared
    @ObservedObject var promptManager = PromptLibraryManager.shared
    @ObservedObject var toastManager = ToastManager.shared
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedIndex = 0
    @State private var selectedTab = 0 // 0 = Clipboard, 1 = OCR Scans, 2 = Library
    @FocusState private var isSearchFocused: Bool
    @State private var editingPrompt: PromptTemplate?
    @State private var showingEditor = false
    
    // Advanced search options
    @State private var searchOptions = AdvancedSearchOptions()
    @State private var showAdvancedFilters = false

    var onPasteItem: (ClipboardItem, PasteFormattingOption) -> Void
    var onClose: () -> Void
    
    @ObservedObject private var settings = SettingsManager.shared
    
    private var layoutSettings: PopoverLayoutSettings {
        settings.popoverLayoutSettings
    }
    
    private var toastAlignment: Alignment {
        let position = settings.toastSettings.position
        switch position {
        case .topRight: return .topTrailing
        case .topLeft: return .topLeading
        case .bottomRight: return .bottomTrailing
        case .bottomLeft: return .bottomLeading
        case .center: return .center
        }
    }
    
    private var toastPadding: EdgeInsets {
        let position = settings.toastSettings.position
        switch position {
        case .topRight, .topLeft:
            return EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20)
        case .bottomRight, .bottomLeft:
            return EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20)
        case .center:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }
    }

    var filteredHistory: [ClipboardItem] {
        var options = searchOptions
        options.searchText = debouncedSearchText
        
        // Apply advanced filters
        return options.filter(clipboardManager.history)
    }
    
    var filteredPrompts: [PromptTemplate] {
        if debouncedSearchText.isEmpty {
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
            let titleScore = prompt.title.fuzzyScore(word: debouncedSearchText)
            let contentScore = prompt.content.fuzzyScore(word: debouncedSearchText)
            return max(titleScore, contentScore) >= threshold
        }.sorted { prompt1, prompt2 in
            // Sort by score (highest first)
            let score1 = max(prompt1.title.fuzzyScore(word: debouncedSearchText), prompt1.content.fuzzyScore(word: debouncedSearchText))
            let score2 = max(prompt2.title.fuzzyScore(word: debouncedSearchText), prompt2.content.fuzzyScore(word: debouncedSearchText))
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
                searchOptions: $searchOptions,
                showAdvancedFilters: $showAdvancedFilters,
                layoutSettings: layoutSettings,
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
        // Premium toast notifications overlay with customizable position
        .overlay(alignment: toastAlignment) {
            if let toast = toastManager.currentToast {
                ToastView(message: toast)
                    .padding(toastPadding)
                    .zIndex(999)  // Above all other content
            }
        }
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { oldValue, newValue in
            // Immediately update if search is cleared (no delay for clearing)
            if newValue.isEmpty {
                debouncedSearchText = ""
                return
            }

            // Debounce search by 300ms to reduce CPU usage with large histories
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                // Only update if searchText hasn't changed again
                if searchText == newValue {
                    debouncedSearchText = newValue
                }
            }
        }
    }
}

// MARK: - Clipboard History Tab

struct ClipboardHistoryTabView: View {
    let filteredHistory: [ClipboardItem]
    @Binding var searchText: String
    @Binding var selectedIndex: Int
    @FocusState.Binding var isSearchFocused: Bool
    @Binding var searchOptions: AdvancedSearchOptions
    @Binding var showAdvancedFilters: Bool
    let layoutSettings: PopoverLayoutSettings
    var onPasteItem: (ClipboardItem, PasteFormattingOption) -> Void
    var onClose: () -> Void
    
    // Lazy loading state
    @ObservedObject private var clipboardManager = ClipboardHistoryManager.shared
    
    private var hasActiveFilters: Bool {
        searchOptions.dateRange != .all || !searchOptions.contentTypes.isEmpty
    }
    
    /// Check if we should load more items based on current scroll position
    private func checkAndLoadMore(currentIndex: Int) {
        // Load more when user scrolls to last 10 items
        let threshold = max(0, filteredHistory.count - 10)
        if currentIndex >= threshold && clipboardManager.hasMoreItems && !clipboardManager.isLoadingMore {
            clipboardManager.loadMoreHistory()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tools Section (Caffeine, Color Picker)
            ToolsSection()
            
            Divider()
            
            // Search Bar with Advanced Options
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))

                    TextField("Search clipboard...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .font(.system(size: 14))

                    // Regex toggle
                    Button(action: {
                        searchOptions.useRegex.toggle()
                    }) {
                        Image(systemName: searchOptions.useRegex ? "textformat.123" : "textformat")
                            .foregroundColor(searchOptions.useRegex ? .accentColor : .secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Use Regular Expression")

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Advanced filters toggle
                    Button(action: {
                        withAnimation {
                            showAdvancedFilters.toggle()
                        }
                    }) {
                        Image(systemName: showAdvancedFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(hasActiveFilters ? .accentColor : .secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Advanced Filters")
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                // Advanced Filters Panel
                if showAdvancedFilters {
                    AdvancedFiltersPanel(searchOptions: $searchOptions)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            Divider()

            // Recent History Footer (like Clipboard app)
            if !filteredHistory.isEmpty {
                RecentHistoryFooter(
                    items: filteredHistory,
                    maxRows: SettingsManager.shared.recentHistoryRowsCount,
                    onPasteItem: onPasteItem
                )
                Divider()
            }

            // History List or Grid
            if filteredHistory.isEmpty {
                EmptyStateView(isSearching: !searchText.isEmpty)
                    .frame(height: 200)
            } else {
                if layoutSettings.viewMode == .grid {
                    // Grid View with Lazy Loading
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                                ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, item in
                                    HistoryItemGridCard(
                                        item: item,
                                        isSelected: index == selectedIndex,
                                        itemSize: layoutSettings.itemSize,
                                        theme: layoutSettings.theme,
                                        onPaste: { option in
                                            onPasteItem(item, option)
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
                                    .onAppear {
                                        // Trigger lazy loading when item appears
                                        checkAndLoadMore(currentIndex: index)
                                    }
                                }
                                
                                // Loading indicator at the bottom
                                if clipboardManager.isLoadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading more...")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(8)
                        }
                        .onChange(of: selectedIndex) { _, newValue in
                            withAnimation {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                            // Check for lazy loading on selection change
                            checkAndLoadMore(currentIndex: newValue)
                        }
                    }
                } else {
                    // List View with Lazy Loading
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, item in
                                    HistoryItemRow(
                                        item: item,
                                        isSelected: index == selectedIndex,
                                        itemSize: layoutSettings.itemSize,
                                        theme: layoutSettings.theme,
                                        onPaste: { option in
                                            onPasteItem(item, option)
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
                                    .onAppear {
                                        // Trigger lazy loading when item appears
                                        checkAndLoadMore(currentIndex: index)
                                    }
                                }
                                
                                // Loading indicator at the bottom
                                if clipboardManager.isLoadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading more...")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(8)
                        }
                        .onChange(of: selectedIndex) { _, newValue in
                            withAnimation {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                            // Check for lazy loading on selection change
                            checkAndLoadMore(currentIndex: newValue)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                FooterHintView(icon: "return", text: "Paste")
                FooterHintView(icon: "shift", text: "⇧ Plain")
                FooterHintView(icon: "command", text: "⌘⇧ MD")
                FooterHintView(icon: "command", text: "⌘⌥ Code")
                FooterHintView(icon: "arrow.up.arrow.down", text: "Navigate")
                FooterHintView(icon: "command", text: "⌫ Clear")
                
                // Additional formatting hints (compact)
                Text("⌃ No Breaks • ⌥ Trim")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                Spacer()

                // Show pagination info: loaded/total items
                if clipboardManager.totalItemCount > 0 && clipboardManager.totalItemCount != filteredHistory.count {
                    Text("\(filteredHistory.count)/\(clipboardManager.totalItemCount) items")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("\(filteredHistory.count) items")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: 900, minHeight: 700, idealHeight: 800, maxHeight: 1000)
        .background(Color.clear) // Transparent to show blur
        .onAppear {
            selectedIndex = 0
            // Delay focus to allow SwiftUI to complete initial render and data binding
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
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
                // Detect modifier keys for formatting options
                let modifiers = NSEvent.modifierFlags
                let option: PasteFormattingOption
                
                if modifiers.contains(.command) && modifiers.contains(.shift) {
                    option = .markdown
                } else if modifiers.contains(.command) && modifiers.contains(.option) {
                    option = .code
                } else if modifiers.contains(.control) {
                    option = .removeLineBreaks
                } else if modifiers.contains(.option) {
                    option = .trimWhitespace
                } else if modifiers.contains(.shift) {
                    option = .plainText
                } else {
                    option = .normal
                }
                
                onPasteItem(filteredHistory[selectedIndex], option)
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
    let itemSize: PopoverLayoutSettings.ItemSize
    let theme: PopoverLayoutSettings.Theme
    let onPaste: (PasteFormattingOption) -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showPreview = false
    @State private var showHoverPreview = false
    @State private var hoverTimer: Timer?
    
    init(item: ClipboardItem, isSelected: Bool, itemSize: PopoverLayoutSettings.ItemSize = .normal, theme: PopoverLayoutSettings.Theme = .default, onPaste: @escaping (PasteFormattingOption) -> Void, onTogglePin: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.isSelected = isSelected
        self.itemSize = itemSize
        self.theme = theme
        self.onPaste = onPaste
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
    }
    
    private func showEnhancedPreview() {
        showPreview = true
    }

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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                } else {
                    // Mask sensitive content (passwords) for security
                    if item.isSensitive {
                        Text("••••••")
                            .font(.system(size: 14))
                            .lineLimit(3)
                            .foregroundColor(.secondary)
                    } else {
                    Text(item.singleLineText(maxLength: 100))
                        .font(.system(size: itemSize.fontSize))
                        .lineLimit(itemSize == .compact ? 2 : 3)
                        .foregroundColor(.primary)
                    }
                }

                HStack(spacing: 8) {
                    // Timestamp
                    Text(timeAgo(from: item.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    // Character count or image indicator
                    if item.isImage {
                        Text("Image")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else if item.isSensitive {
                        // Don't show character count for sensitive items
                        Text("Password")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(item.plainTextPreview.count) chars")
                            .font(.system(size: 11))
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
        .padding(itemSize == .compact ? 6 : (itemSize == .large ? 14 : 10))
        .frame(height: itemSize.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? theme.accentColor.opacity(0.15) : (isHovered ? theme.accentColor.opacity(0.08) : theme.backgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? theme.accentColor : (isHovered ? theme.accentColor.opacity(0.3) : Color.clear), lineWidth: isSelected ? 1.5 : 1)
        )
    }
    
    private func handleHover(_ hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            isHovered = hovering
        }
        
        // Show hover preview after a short delay
        if hovering {
            hoverTimer?.invalidate()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                showHoverPreview = true
            }
        } else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            showHoverPreview = false
        }
    }
    
    private func handleTap() {
        // Single click - check modifier keys for formatting options
        let event = NSApp.currentEvent
        let modifiers = event?.modifierFlags ?? []
        let option: PasteFormattingOption
        
        if modifiers.contains(.command) && modifiers.contains(.shift) {
            option = .markdown
        } else if modifiers.contains(.command) && modifiers.contains(.option) {
            option = .code
        } else if modifiers.contains(.control) {
            option = .removeLineBreaks
        } else if modifiers.contains(.option) {
            option = .trimWhitespace
        } else if modifiers.contains(.shift) {
            option = .plainText
        } else {
            option = .normal
        }
        
        onPaste(option)
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
    @State private var showingPromptDetail: PromptTemplate? = nil
    @State private var sortOption: SortOption = .lastUsed
    @State private var showFavoritesOnly = false
    @State private var selectedCollection: String? = nil
    @State private var selectedTag: String? = nil
    
    enum SortOption: String, CaseIterable {
        case lastUsed = "Last Used"
        case mostUsed = "Most Used"
        case rating = "Rating"
        case title = "Title"
        case createdAt = "Created Date"
    }
    
    // Computed: Get prompts to display based on search, category, filters, and sorting
    var displayedPrompts: [PromptTemplate] {
        var result = filteredPrompts
        
        // Category filter
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        
        // Favorites filter
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        
        // Collection filter
        if let collection = selectedCollection {
            result = result.filter { $0.collection == collection }
        }
        
        // Tag filter
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        
        // Sorting
        switch sortOption {
        case .lastUsed:
            result = result.sorted { ($0.lastUsed ?? Date.distantPast) > ($1.lastUsed ?? Date.distantPast) }
        case .mostUsed:
            result = result.sorted { $0.usageCount > $1.usageCount }
        case .rating:
            result = result.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .title:
            result = result.sorted { $0.title < $1.title }
        case .createdAt:
            result = result.sorted { $0.createdAt > $1.createdAt }
        }
        
        return result
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategory = nil
                        }
                        
                        // Favorites
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.pink)
                                .frame(width: 16)
                            Text("Favorites")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(promptManager.favoritePrompts.count)")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showFavoritesOnly = true
                            selectedCategory = nil
                        }
                        
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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCategory = category
                            }
                        }
                    }
                    
                    // Tags section (if any tags exist)
                    if !promptManager.allTags.isEmpty {
                        Section("Tags") {
                            ForEach(promptManager.allTags.prefix(10), id: \.self) { tag in
                                HStack {
                                    Image(systemName: "tag.fill")
                                        .foregroundColor(.blue)
                                        .frame(width: 16)
                                    Text(tag)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Text("\(promptManager.prompts(withTag: tag).count)")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 10))
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTag = tag
                                }
                            }
                        }
                    }
                    
                    // Collections section (if any collections exist)
                    if !promptManager.allCollections.isEmpty {
                        Section("Collections") {
                            ForEach(promptManager.allCollections, id: \.self) { collection in
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.orange)
                                        .frame(width: 16)
                                    Text(collection)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Text("\(promptManager.prompts(in: collection).count)")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 10))
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCollection = collection
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selectedCategory) { oldValue, newValue in
                    // Ensure selection is updated
                }
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            // RIGHT: Prompts List
            VStack(spacing: 0) {
                // Toolbar with filters and sorting
                HStack(spacing: 8) {
                    // Add Prompt Button
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
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                    
                    // Favorites filter
                    Button(action: {
                        showFavoritesOnly.toggle()
                    }) {
                        Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                            .foregroundColor(showFavoritesOnly ? .pink : .secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .help("Show favorites only")
                    
                    // Sort picker
                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    
                    // Collection picker (if any collections exist)
                    if !promptManager.allCollections.isEmpty {
                        Picker("Collection", selection: $selectedCollection) {
                            Text("All Collections").tag(nil as String?)
                            ForEach(promptManager.allCollections, id: \.self) { collection in
                                Text(collection).tag(collection as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }
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
                                                showingPromptDetail: $showingPromptDetail,
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
                                            onView: {
                                                showingPromptDetail = prompt
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
                        .frame(maxHeight: .infinity)
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
        .frame(minWidth: 900, idealWidth: 1000, maxWidth: 1200, minHeight: 600, idealHeight: 700, maxHeight: 900)
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
        .sheet(item: $showingPromptDetail) { prompt in
            PromptDetailView(prompt: prompt)
                .frame(minWidth: 800, idealWidth: 900, maxWidth: 1200, minHeight: 600, idealHeight: 700, maxHeight: 1000)
                .onDisappear {
                    // Clear sheet state when dismissed
                    showingPromptDetail = nil
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PromptDetailWindowClosed"))) { _ in
            // Clear sheet state when window closes to prevent reopening
            showingPromptDetail = nil
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
    @Binding var showingPromptDetail: PromptTemplate?
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
                    onView: {
                        showingPromptDetail = prompt
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
    var onView: (() -> Void)? = nil
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ObservedObject var promptManager = PromptLibraryManager.shared

    @State private var isHovered = false
    @State private var showHoverPreview = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: prompt.isSystem ? "star.fill" : "doc.text")
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .accentColor : (prompt.isSystem ? .orange : .secondary))
                .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(prompt.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    // Favorite indicator
                    if prompt.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                    }
                    
                    // Rating stars (interactive)
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: {
                                let newRating = prompt.rating == star ? nil : star
                                promptManager.updateRating(for: prompt, rating: newRating)
                            }) {
                                Image(systemName: star <= (prompt.rating ?? 0) ? "star.fill" : "star")
                                    .font(.system(size: 8))
                                    .foregroundColor(star <= (prompt.rating ?? 0) ? .yellow : .gray.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                            .help("Rate \(star) star\(star == 1 ? "" : "s")")
                        }
                    }
                }
                
                Text(truncatedContent)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Tags and metadata
                HStack(spacing: 6) {
                    // Tags
                    if !prompt.tags.isEmpty {
                        ForEach(prompt.tags.prefix(2), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                        if prompt.tags.count > 2 {
                            Text("+\(prompt.tags.count - 2)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Usage count
                    if prompt.usageCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 8))
                            Text("\(prompt.usageCount)")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // Collection badge
                    if let collection = prompt.collection {
                        HStack(spacing: 2) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 8))
                            Text(collection)
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.3) : Color.clear), lineWidth: 1.5)
        )
        .onHover { hovering in
            isHovered = hovering
            // Show hover preview after a short delay
            if hovering {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isHovered {
                        showHoverPreview = true
                    }
                }
            } else {
                showHoverPreview = false
            }
        }
        .popover(isPresented: $showHoverPreview, arrowEdge: .leading) {
            PromptHoverPreviewView(prompt: prompt)
                .frame(width: 400, height: 300)
        }
        .onTapGesture {
            // Single click - open detail window for editing/viewing
            if let onView = onView {
                onView()
            } else {
                PromptDetailWindowController.shared.show(prompt: prompt)
            }
        }
        .contextMenu {
            Button(action: onCopy) {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(action: {
                Task { @MainActor in
                    PromptLibraryManager.shared.toggleFavorite(for: prompt)
                }
            }) {
                Label(prompt.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: prompt.isFavorite ? "heart.slash" : "heart")
            }
            
            if !prompt.isSystem {
                Divider()
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    private var truncatedContent: String {
        let maxLength = 60
        if prompt.content.count > maxLength {
            return String(prompt.content.prefix(maxLength)) + "..."
        }
        return prompt.content
    }
}

// MARK: - Prompt Hover Preview View

struct PromptHoverPreviewView: View {
    let prompt: PromptTemplate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 6) {
                        Image(systemName: prompt.category.icon)
                            .foregroundColor(prompt.category.color)
                            .font(.system(size: 10))
                        Text(prompt.category.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            // Full content
            ScrollView {
                Text(prompt.content)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Footer with metadata
            HStack {
                if prompt.isSystem {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 9))
                        Text("System Prompt")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Text("\(prompt.content.count) characters")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 400, height: 300)
    }
}

// MARK: - Prompt Editor View

struct PromptEditorView: View {
    let prompt: PromptTemplate?
    let onSave: (PromptTemplate) -> Void
    let onCancel: () -> Void
    
    @State private var title: String
    @State private var content: String
    @State private var selectedCategory: PromptCategory
    @FocusState private var isTitleFocused: Bool

    init(prompt: PromptTemplate?, onSave: @escaping (PromptTemplate) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: prompt?.title ?? "")
        _content = State(initialValue: prompt?.content ?? "")
        _selectedCategory = State(initialValue: prompt?.category ?? .productivity)
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
                        .font(.system(size: 14))
                }

                // Category picker
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("library.editor.category.label", comment: "Category"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedCategory) {
                        ForEach(PromptCategory.allCases) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Content field
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(NSLocalizedString("library.editor.content.label", comment: "Prompt Content"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(content.count) characters")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    TextEditor(text: $content)
                        .frame(minHeight: 300, maxHeight: .infinity)
                        .padding(8)
                        .font(.system(size: 13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
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
                        category: selectedCategory,
                        isSystem: prompt?.isSystem ?? false,
                        lastUsed: prompt?.lastUsed,
                        rating: prompt?.rating,
                        tags: prompt?.tags ?? [],
                        isFavorite: prompt?.isFavorite ?? false,
                        usageCount: prompt?.usageCount ?? 0,
                        createdAt: prompt?.createdAt ?? Date(),
                        notes: prompt?.notes,
                        collection: prompt?.collection
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
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 900, minHeight: 600, idealHeight: 700, maxHeight: 850)
        .onAppear {
            isTitleFocused = true
        }
    }
}

// MARK: - Scratchpad Tab

struct ScratchpadTabView: View {
    @ObservedObject private var scratchpadManager = ScratchpadManager.shared
    var onClose: () -> Void
    
    @State private var showingRenameDialog = false
    @State private var renamingTabId: UUID? = nil
    @State private var newTabName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Tabs
            VStack(spacing: 0) {
                // Tabs Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(scratchpadManager.tabs) { tab in
                            ScratchpadTabButton(
                                tab: tab,
                                isSelected: scratchpadManager.selectedTabId == tab.id,
                                onSelect: {
                                    scratchpadManager.selectTab(tab.id)
                                },
                                onClose: {
                                    scratchpadManager.deleteTab(tab.id)
                                },
                                onRename: {
                                    renamingTabId = tab.id
                                    newTabName = tab.name
                                    showingRenameDialog = true
                                },
                                canClose: scratchpadManager.tabs.count > 1
                            )
                        }
                        
                        // Add new tab button
                        Button(action: {
                            scratchpadManager.createNewTab()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10))
                                Text("New")
                                    .font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                
                Divider()
                
                // Toolbar
                HStack {
                    Text("Scratchpad")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        scratchpadManager.clear()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Clear")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            
            Divider()
            
            // Text Editor
            if scratchpadManager.selectedTabId != nil {
                TextEditor(text: $scratchpadManager.content)
                    .font(.system(size: 13))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: scratchpadManager.content) { oldValue, newValue in
                        // Content is automatically saved via didSet in ScratchpadManager
                    }
            } else {
                VStack {
                    Text("No tab selected")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("Auto-saves as you type")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                if let currentTab = scratchpadManager.currentTab {
                    Text("\(currentTab.content.count) chars")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: 900, minHeight: 700, idealHeight: 800, maxHeight: 1000)
        .alert("Rename Tab", isPresented: $showingRenameDialog) {
            TextField("Tab name", text: $newTabName)
            Button("Cancel", role: .cancel) {
                renamingTabId = nil
                newTabName = ""
            }
            Button("Rename") {
                if let tabId = renamingTabId {
                    scratchpadManager.renameTab(tabId, newName: newTabName)
                    renamingTabId = nil
                    newTabName = ""
                }
            }
        } message: {
            Text("Enter a new name for this tab")
        }
    }
}

// MARK: - Scratchpad Tab Button

struct ScratchpadTabButton: View {
    let tab: ScratchpadTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: () -> Void
    let canClose: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                Text(tab.name)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            }
            .buttonStyle(.plain)
            
            if isHovered || isSelected {
                Button(action: onRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                if canClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.accentColor.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Recent History Footer

struct RecentHistoryFooter: View {
    let items: [ClipboardItem]
    let maxRows: Int
    var onPasteItem: (ClipboardItem, PasteFormattingOption) -> Void
    
    private var recentItems: [ClipboardItem] {
        Array(items.prefix(maxRows))
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                    RecentHistoryRow(
                        item: item,
                        index: index,
                        onPaste: { option in
                            onPasteItem(item, option)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 50)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Recent History Row

struct RecentHistoryRow: View {
    let item: ClipboardItem
    let index: Int
    var onPaste: (PasteFormattingOption) -> Void
    
    @State private var isHovered = false
    
    private var keyboardShortcut: String {
        "⌘\(index)"
    }
    
    private var compactTime: String {
        let seconds = Date().timeIntervalSince(item.timestamp)
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
    
    private var previewText: String {
        if item.isSensitive {
            return "••••••"
        } else if item.isImage {
            return "Image"
        } else {
            let text = item.plainTextPreview.replacingOccurrences(of: "\n", with: " ")
            if text.count > 70 {
                return String(text.prefix(70)) + "..."
            }
            return text
        }
    }
    
    var body: some View {
        Button(action: {
            let event = NSApp.currentEvent
            let modifiers = event?.modifierFlags ?? []
            let option: PasteFormattingOption
            
            if modifiers.contains(.command) && modifiers.contains(.shift) {
                option = .markdown
            } else if modifiers.contains(.command) && modifiers.contains(.option) {
                option = .code
            } else if modifiers.contains(.control) {
                option = .removeLineBreaks
            } else if modifiers.contains(.option) {
                option = .trimWhitespace
            } else if modifiers.contains(.shift) {
                option = .plainText
            } else {
                option = .normal
            }
            
            onPaste(option)
        }) {
            HStack(spacing: 6) {
                // Keyboard shortcut
                Text(keyboardShortcut)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 32)
                
                // Preview text
                Text(previewText)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .leading)
                
                // Time
                Text(compactTime)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(item.isSensitive ? "Password" : (item.isImage ? "Image" : item.textForPasting))
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
