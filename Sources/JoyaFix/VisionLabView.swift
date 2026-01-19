import SwiftUI
import AppKit

struct VisionLabView: View {
    @State private var selectedImage: NSImage?
    @State private var description: String = ""
    @State private var isProcessing = false
    @State private var processingStatus: String = ""
    @State private var errorMessage: String?
    @State private var isDragging = false
    @State private var showSuccessFeedback = false
    
    @ObservedObject private var settings = SettingsManager.shared
    
    // Reactive AI service - always uses latest provider from settings
    private var aiService: AIServiceProtocol {
        AIServiceFactory.createService()
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "eye")
                        .font(.system(size: 24))
                        .foregroundColor(.pink)
                    Text("Vision Lab")
                        .font(.system(size: 24, weight: .bold))
                }
                
                Text("Transform images into detailed prompts for AI image generation")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            Divider()
            
            // Image Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDragging ? Color.pink.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isDragging ? Color.pink : Color.gray.opacity(0.3), lineWidth: 2)
                    )
                    .frame(height: 200)
                
                if let image = selectedImage {
                    // Show selected image
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .cornerRadius(12)
                        .padding(10)
                } else {
                    // Drop zone content
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("Drag & drop an image here")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("or click to browse")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDrop(of: [.image], isTargeted: $isDragging) { providers in
                handleDrop(providers: providers)
            }
            .onTapGesture {
                selectImage()
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                if selectedImage != nil {
                    Button(action: {
                        selectedImage = nil
                        description = ""
                        errorMessage = nil
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Clear")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: selectImage) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundColor(.blue)
                        Text("Browse")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                
                Button(action: processImage) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "sparkles")
                                .foregroundColor(.pink)
                        }
                        Text(isProcessing ? (processingStatus.isEmpty ? "Processing..." : processingStatus) : "Generate Description")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedImage == nil || isProcessing)
            }
            
            // Error Message
            if let error = errorMessage {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }

                    // Show "Open Settings" button if API key is missing
                    if error.contains("API key not found") || error.contains("Invalid API key") {
                        Button(action: {
                            // Close popover and open settings
                            SettingsWindowController.shared.show()
                        }) {
                            HStack {
                                Image(systemName: "gearshape")
                                Text("Open Settings")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Description Output
            if !description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Description")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button(action: {
                            ClipboardHelper.writeToClipboard(description)
                            SoundManager.shared.playSuccess()
                            // Show success feedback
                            showSuccessFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                showSuccessFeedback = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                if showSuccessFeedback {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 12))
                                }
                                Text(showSuccessFeedback ? "Copied!" : "Magic Copy")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.bordered)
                        .animation(.easeInOut(duration: 0.2), value: showSuccessFeedback)
                    }
                    
                    ScrollView {
                        Text(description)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                    .frame(height: 150)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .frame(minWidth: 500, idealWidth: 550, maxWidth: 700, minHeight: 600, idealHeight: 650, maxHeight: 800)
    }
    
    // MARK: - Helper Methods
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { image, error in
                DispatchQueue.main.async {
                    if let nsImage = image as? NSImage {
                        self.selectedImage = nsImage
                        self.errorMessage = nil
                    }
                }
            }
            return true
        }
        
        return false
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        // Use asynchronous begin() to prevent popover from closing
        panel.begin { response in
            if response == .OK {
                if let url = panel.url,
                   let image = NSImage(contentsOf: url) {
                    // Update on main thread since this is a SwiftUI @State
                    DispatchQueue.main.async {
                        self.selectedImage = image
                        self.errorMessage = nil
                    }
                }
            }
        }
    }
    
    private func processImage() {
        guard let image = selectedImage else { return }
        
        isProcessing = true
        errorMessage = nil
        description = ""
        processingStatus = "Analyzing image..."
        
        Task { @MainActor in
            do {
                processingStatus = "Sending to AI service..."
                let providerName = settings.selectedAIProvider == .gemini ? "Gemini" : "OpenRouter"
                processingStatus = "Processing with \(providerName)..."
                
                let result = try await aiService.describeImage(image: image)
                description = result
                isProcessing = false
                processingStatus = ""
                SoundManager.shared.playSuccess()
            } catch {
                // Provide user-friendly error messages
                let userFriendlyMessage: String
                if let aiError = error as? AIServiceError {
                    switch aiError {
                    case .apiKeyNotFound:
                        userFriendlyMessage = "API key not found. Please configure your API key in Settings > API Configuration."
                    case .httpError(let code, let message):
                        if code == 401 {
                            userFriendlyMessage = "Invalid API key. Please check your API key in Settings."
                        } else if code == 429 {
                            userFriendlyMessage = "Rate limit exceeded. Please try again in a few moments."
                        } else {
                            userFriendlyMessage = "Error \(code): \(message ?? "Unknown error"). Please try again."
                        }
                    case .networkError:
                        userFriendlyMessage = "Network error. Please check your internet connection and try again."
                    case .rateLimitExceeded:
                        userFriendlyMessage = "Rate limit exceeded. Please wait a moment and try again."
                    default:
                        userFriendlyMessage = "Error processing image: \(aiError.localizedDescription)"
                    }
                } else {
                    userFriendlyMessage = "Error processing image: \(error.localizedDescription)"
                }
                
                errorMessage = userFriendlyMessage
                isProcessing = false
                processingStatus = ""
                Logger.error("Vision Lab error: \(error.localizedDescription)", category: Logger.network)
            }
        }
    }
}

