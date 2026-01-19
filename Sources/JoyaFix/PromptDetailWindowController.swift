import Cocoa
import SwiftUI

class PromptDetailWindowController {
    static let shared = PromptDetailWindowController()
    
    private var detailWindow: NSWindow?
    private var windowCloseObserver: NSObjectProtocol?
    private var windowDelegate: WindowDelegate?
    
    private init() {}
    
    deinit {
        // Remove observer on deinit
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Shows the prompt detail window with full content
    func show(prompt: PromptTemplate) {
        DispatchQueue.main.async {
            // Don't open if we're already closing or just closed
            guard self.detailWindow == nil || (self.detailWindow?.isVisible == true) else {
                // Window is closing or closed, don't reopen
                return
            }
            
            // Check if window already exists and is visible
            if let existingWindow = self.detailWindow, existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                existingWindow.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                // Update content if needed
                if let hostingController = existingWindow.contentViewController as? NSHostingController<PromptDetailView> {
                    hostingController.rootView = PromptDetailView(prompt: prompt)
                }
                return
            }
            
            // Create new prompt detail window
            let detailView = PromptDetailView(prompt: prompt)
            let hostingController = NSHostingController(rootView: detailView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            
            window.title = prompt.title
            window.contentViewController = hostingController
            window.center()
            window.setFrameAutosaveName("PromptDetail")
            window.isReleasedWhenClosed = false
            window.level = .floating
            
            // Set window delegate to handle closing properly
            let delegate = WindowDelegate(controller: self)
            self.windowDelegate = delegate
            window.delegate = delegate
            
            // Handle window closing - store observer for cleanup
            self.windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] notification in
                // Clear reference when window closes
                if let closedWindow = notification.object as? NSWindow,
                   closedWindow == self?.detailWindow {
                    self?.detailWindow = nil
                    self?.windowDelegate = nil
                    // Remove observer when window closes
                    if let observer = self?.windowCloseObserver {
                        NotificationCenter.default.removeObserver(observer)
                        self?.windowCloseObserver = nil
                    }
                }
            }
            
            // Show window with premium animation
            window.showWithPremiumAnimation()
            NSApp.activate(ignoringOtherApps: true)
            
            self.detailWindow = window
        }
    }
    
    /// Closes the prompt detail window
    func close() {
        DispatchQueue.main.async {
            // Prefer the tracked window, but fall back to the visible PromptDetail window.
            let windowToClose =
                self.detailWindow ??
                NSApp.windows.first(where: { $0.frameAutosaveName == "PromptDetail" && $0.isVisible })

            windowToClose?.close()
            self.clearWindowReference()
        }
    }
    
    /// Clears the window reference (called by delegate)
    func clearWindowReference() {
        DispatchQueue.main.async {
            // Set to nil immediately to prevent reopening
            self.detailWindow = nil
            self.windowDelegate = nil
            
            // Also clear any sheet state that might try to reopen
            // This prevents the sheet from reopening the window
            NotificationCenter.default.post(name: NSNotification.Name("PromptDetailWindowClosed"), object: nil)
        }
    }
}

// MARK: - Window Delegate

private class WindowDelegate: NSObject, NSWindowDelegate {
    weak var controller: PromptDetailWindowController?
    
    init(controller: PromptDetailWindowController) {
        self.controller = controller
    }
    
    func windowWillClose(_ notification: Notification) {
        // Clear reference when window closes
        DispatchQueue.main.async {
            self.controller?.clearWindowReference()
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
}

// MARK: - Prompt Detail View

struct PromptDetailView: View {
    let prompt: PromptTemplate
    @ObservedObject var promptManager = PromptLibraryManager.shared
    @State private var isEditing = false
    @State private var editedPrompt: PromptTemplate?
    @State private var showDeleteConfirmation = false

    private func closeSelf() {
        // Close the actual window hosting this view (more reliable than relying on controller state).
        // First clear the reference to prevent reopening
        PromptDetailWindowController.shared.clearWindowReference()
        
        // Then close the window
        if let key = NSApp.keyWindow, key.isVisible, key.frameAutosaveName == "PromptDetail" {
            key.close()
        } else if let w = NSApp.windows.first(where: { $0.frameAutosaveName == "PromptDetail" && $0.isVisible }) {
            w.close()
        } else {
            PromptDetailWindowController.shared.close()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editedPrompt?.title ?? prompt.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: (editedPrompt?.category ?? prompt.category).icon)
                            .foregroundColor((editedPrompt?.category ?? prompt.category).color)
                            .font(.system(size: 12))
                        Text((editedPrompt?.category ?? prompt.category).rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        if (editedPrompt?.isSystem ?? prompt.isSystem) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 10))
                                Text("System")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    // Close button
                    Button(action: {
                        closeSelf()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Close")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Button(action: {
                        let promptToCopy = editedPrompt ?? prompt
                        promptManager.copyPromptToClipboard(promptToCopy)
                        SoundManager.shared.playSuccess()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("c", modifiers: .command)
                    
                    if !(editedPrompt?.isSystem ?? prompt.isSystem) {
                        Button(action: {
                            isEditing = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("e", modifiers: .command)
                        
                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        .keyboardShortcut(.delete, modifiers: .command)
                    }
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Content - Editable if in edit mode
            if isEditing {
                PromptEditorView(
                    prompt: editedPrompt ?? prompt,
                    onSave: { updatedPrompt in
                        editedPrompt = updatedPrompt
                        promptManager.updatePrompt(updatedPrompt)
                        isEditing = false
                        SoundManager.shared.playSuccess()
                    },
                    onCancel: {
                        editedPrompt = nil
                        isEditing = false
                    }
                )
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Metadata section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Details")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            // Rating
                            HStack {
                                Text("Rating:")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 4) {
                                    ForEach(1...5, id: \.self) { star in
                                        Button(action: {
                                            let currentPrompt = editedPrompt ?? prompt
                                            let newRating = (currentPrompt.rating) == star ? nil : star
                                            promptManager.updateRating(for: currentPrompt, rating: newRating)
                                            
                                            // Reload prompt from manager to get updated version
                                            if let updated = promptManager.prompts.first(where: { $0.id == prompt.id }) {
                                                editedPrompt = updated
                                            }
                                        }) {
                                            Image(systemName: star <= (editedPrompt?.rating ?? prompt.rating ?? 0) ? "star.fill" : "star")
                                                .font(.system(size: 16))
                                                .foregroundColor(star <= (editedPrompt?.rating ?? prompt.rating ?? 0) ? .yellow : .gray.opacity(0.3))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                Spacer()
                            }
                            
                            // Favorite toggle
                            HStack {
                                Button(action: {
                                    let currentPrompt = editedPrompt ?? prompt
                                    promptManager.toggleFavorite(for: currentPrompt)
                                    
                                    // Reload prompt from manager to get updated version
                                    if let updated = promptManager.prompts.first(where: { $0.id == prompt.id }) {
                                        editedPrompt = updated
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: (editedPrompt?.isFavorite ?? prompt.isFavorite) ? "heart.fill" : "heart")
                                            .foregroundColor((editedPrompt?.isFavorite ?? prompt.isFavorite) ? .pink : .secondary)
                                        Text((editedPrompt?.isFavorite ?? prompt.isFavorite) ? "Remove from Favorites" : "Add to Favorites")
                                            .font(.system(size: 12))
                                    }
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                // Usage stats
                                HStack(spacing: 12) {
                                    if (editedPrompt?.usageCount ?? prompt.usageCount) > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 10))
                                            Text("Used \(editedPrompt?.usageCount ?? prompt.usageCount) times")
                                                .font(.system(size: 11))
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                    
                                    if let lastUsed = editedPrompt?.lastUsed ?? prompt.lastUsed {
                                        Text("Last used: \(lastUsed.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            // Tags
                            if !(editedPrompt?.tags ?? prompt.tags).isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Tags:")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    
                                    FlowLayout(spacing: 6) {
                                        ForEach(editedPrompt?.tags ?? prompt.tags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.blue)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            
                            // Collection
                            if let collection = editedPrompt?.collection ?? prompt.collection {
                                HStack {
                                    Text("Collection:")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(collection)
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(8)
                        
                        // Notes section
                        if let notes = editedPrompt?.notes ?? prompt.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notes:")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Text(notes)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                            .padding(16)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .cornerRadius(8)
                        }
                        
                        // Prompt Content
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Prompt Content")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(editedPrompt?.content.count ?? prompt.content.count) characters")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(editedPrompt?.content ?? prompt.content)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                                .cornerRadius(8)
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, idealWidth: 900, maxWidth: 1200, minHeight: 600, idealHeight: 700, maxHeight: 1000)
        .alert("Delete Prompt", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                promptManager.deletePrompt(editedPrompt ?? prompt)
                closeSelf()
                SoundManager.shared.playSuccess()
            }
        } message: {
            Text("Are you sure you want to delete \"\(prompt.title)\"? This action cannot be undone.")
        }
        .onAppear {
            editedPrompt = prompt
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    closeSelf()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}
