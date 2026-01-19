import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var microphoneGranted = false
    @State private var speechRecognitionGranted = false
    @State private var permissionCheckTimer: Timer?
    @State private var selectedAIProvider: AIProvider = .gemini
    
    @ObservedObject private var downloadManager = ModelDownloadManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    let onComplete: () -> Void
    
    // Total pages: 6
    private let totalPages = 6
    
    var body: some View {
        VStack(spacing: 0) {
            // Current slide content
            Group {
                switch currentPage {
                case 0:
                    WelcomeSlide()
                case 1:
                    TheMagicSlide() // AI Text Enhancement & Translation
                case 2:
                    AIChoiceSlide(selectedProvider: $selectedAIProvider) // Privacy Choice
                case 3:
                    YourAgentSlide() // Agent Personality
                case 4:
                    PermissionsSlide(
                        accessibilityGranted: $accessibilityGranted,
                        screenRecordingGranted: $screenRecordingGranted,
                        microphoneGranted: $microphoneGranted,
                        speechRecognitionGranted: $speechRecognitionGranted
                    )
                case 5:
                    ReadySlide(onComplete: {
                        // Save the selected AI provider
                        settings.selectedAIProvider = selectedAIProvider
                        hasCompletedOnboarding = true
                        onComplete()
                    })
                default:
                    WelcomeSlide()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            
            // Navigation controls
            HStack {
                // Back button
                if currentPage > 0 {
                    Button(action: {
                        withAnimation {
                            currentPage -= 1
                        }
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text(NSLocalizedString("onboarding.back", comment: "Back button"))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                
                Spacer()
                
                // Next/Get Started button
                if currentPage < totalPages - 1 {
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentPage += 1
                        }
                    }) {
                        HStack {
                            Text(NSLocalizedString("onboarding.next", comment: "Next button"))
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 700, height: 600)
        .onAppear {
            checkPermissions()
            startPermissionPolling()
            // Load current AI provider setting
            selectedAIProvider = settings.selectedAIProvider
        }
        .onDisappear {
            stopPermissionPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh permissions immediately when app becomes active (user returns from Settings)
            // Small delay to ensure system has updated permission status
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                checkPermissions()
            }
        }
    }
    
    private func checkPermissions() {
        // Use refreshAccessibilityStatus to force fresh check (bypass cache)
        accessibilityGranted = PermissionManager.shared.refreshAccessibilityStatus()
        screenRecordingGranted = PermissionManager.shared.isScreenRecordingTrusted()
        microphoneGranted = PermissionManager.shared.isMicrophoneGranted()
        speechRecognitionGranted = PermissionManager.shared.isSpeechRecognitionGranted()
    }
    
    private func startPermissionPolling() {
        // Poll permissions every 0.5 seconds to detect changes quickly
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            checkPermissions()
        }
    }
    
    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
}

// MARK: - Welcome Slide (Screen 1)

struct WelcomeSlide: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Logo with animation
            Group {
                if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: "png"),
                   let logoImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                } else if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: nil),
                          let logoImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                } else {
                    Image("FLATLOGO")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }
            }
            
            VStack(spacing: 16) {
                Text(NSLocalizedString("onboarding.welcome.title", comment: "Welcome title"))
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(NSLocalizedString("onboarding.welcome.subtitle", comment: "Welcome subtitle"))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(NSLocalizedString("onboarding.welcome.description", comment: "Welcome description"))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }
            
            Spacer()
        }
        .padding(40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
        }
    }
}

// MARK: - The Magic Slide (Screen 2)

struct TheMagicSlide: View {
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // AI Icon with animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .shadow(color: .purple.opacity(0.3), radius: 20, x: 0, y: 10)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 70))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
            }
            
            VStack(spacing: 16) {
                Text(NSLocalizedString("onboarding.the.magic.title", comment: "The Magic title"))
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(NSLocalizedString("onboarding.the.magic.subtitle", comment: "The Magic subtitle"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(NSLocalizedString("onboarding.the.magic.description", comment: "The Magic description"))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                    .padding(.top, 8)
            }
            
            // Feature highlights
            VStack(spacing: 12) {
                FeatureBullet(icon: "text.bubble.fill", text: NSLocalizedString("onboarding.the.magic.feature1", comment: "Magic feature 1"))
                FeatureBullet(icon: "globe", text: NSLocalizedString("onboarding.the.magic.feature2", comment: "Magic feature 2"))
                FeatureBullet(icon: "wand.and.stars", text: NSLocalizedString("onboarding.the.magic.feature3", comment: "Magic feature 3"))
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .padding(40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
        }
    }
}

// MARK: - Privacy Choice Slide (Screen 3)

struct AIChoiceSlide: View {
    @Binding var selectedProvider: AIProvider
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 12) {
                Text(NSLocalizedString("onboarding.ai.choice.title", comment: "AI choice title"))
                    .font(.system(size: 36, weight: .bold))
                
                Text(NSLocalizedString("onboarding.ai.choice.subtitle", comment: "AI choice subtitle"))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            HStack(spacing: 24) {
                // Cloud Option (Gemini)
                ProviderOptionCard(
                    icon: "cloud.fill",
                    iconColor: .blue,
                    title: NSLocalizedString("onboarding.ai.choice.cloud.title", comment: "Cloud option title"),
                    features: [
                        NSLocalizedString("onboarding.ai.choice.cloud.feature1", comment: "Cloud feature 1"),
                        NSLocalizedString("onboarding.ai.choice.cloud.feature2", comment: "Cloud feature 2"),
                        NSLocalizedString("onboarding.ai.choice.cloud.feature3", comment: "Cloud feature 3")
                    ],
                    isSelected: selectedProvider == .gemini || selectedProvider == .openRouter
                ) {
                    selectedProvider = .gemini
                }
                
                // Local Option
                ProviderOptionCard(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: NSLocalizedString("onboarding.ai.choice.local.title", comment: "Local option title"),
                    features: [
                        NSLocalizedString("onboarding.ai.choice.local.feature1", comment: "Local feature 1"),
                        NSLocalizedString("onboarding.ai.choice.local.feature2", comment: "Local feature 2"),
                        NSLocalizedString("onboarding.ai.choice.local.feature3", comment: "Local feature 3")
                    ],
                    isSelected: selectedProvider == .local
                ) {
                    selectedProvider = .local
                }
            }
            .padding(.horizontal, 20)
            
            // Note about changing later
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(NSLocalizedString("onboarding.ai.choice.note", comment: "Can change later note"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(40)
    }
}

struct ProviderOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let features: [String]
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundColor(iconColor)
                }
                
                // Title
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Features
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(iconColor)
                            Text(feature)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? iconColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Local Model Setup Slide (Screen 4)

struct LocalModelSetupSlide: View {
    @Binding var selectedProvider: AIProvider
    @ObservedObject var downloadManager: ModelDownloadManager
    
    // Recommended model (Gemma 2B)
    private var recommendedModel: LocalModelInfo? {
        LocalModelRegistry.availableModels.first { $0.id == "gemma-2-2b-instruct" }
    }
    
    private var isModelDownloaded: Bool {
        guard let model = recommendedModel else { return false }
        return downloadManager.downloadedModels.contains { $0.id == model.id && $0.exists }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.3), Color.teal.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: .green.opacity(0.3), radius: 15, x: 0, y: 8)
                
                Image(systemName: "cpu.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text(NSLocalizedString("onboarding.local.setup.title", comment: "Local setup title"))
                    .font(.system(size: 32, weight: .bold))
                
                if selectedProvider == .local {
                    Text(NSLocalizedString("onboarding.local.setup.description", comment: "Local setup description"))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    Text(NSLocalizedString("onboarding.local.setup.skip.description", comment: "Skip local setup description"))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            
            // Download section (only show if local is selected)
            if selectedProvider == .local {
                VStack(spacing: 16) {
                    if let model = recommendedModel {
                        // Model info card
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.displayName)
                                        .font(.system(size: 18, weight: .semibold))
                                    Text(model.description)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                
                                if isModelDownloaded {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text(NSLocalizedString("onboarding.local.setup.downloaded", comment: "Downloaded"))
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            
                            HStack(spacing: 16) {
                                Label(model.fileSizeFormatted, systemImage: "internaldrive")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Label(model.requiredRAMFormatted + " RAM", systemImage: "memorychip")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        )
                        
                        // Download button or progress
                        if downloadManager.isDownloading && downloadManager.currentDownloadModel?.id == model.id {
                            VStack(spacing: 8) {
                                ProgressView(value: downloadManager.downloadProgress)
                                    .progressViewStyle(.linear)
                                
                                HStack {
                                    Text("\(Int(downloadManager.downloadProgress * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button(NSLocalizedString("onboarding.local.setup.cancel", comment: "Cancel")) {
                                        downloadManager.cancelDownload()
                                    }
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 40)
                        } else if !isModelDownloaded {
                            Button(action: {
                                Task {
                                    try? await downloadManager.downloadModel(model)
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text(NSLocalizedString("onboarding.local.setup.download", comment: "Download button"))
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                }
                .padding(.horizontal, 40)
            } else {
                // Show option to switch to local
                VStack(spacing: 12) {
                    Text(NSLocalizedString("onboarding.local.setup.switch.hint", comment: "Switch hint"))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        selectedProvider = .local
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text(NSLocalizedString("onboarding.local.setup.switch", comment: "Switch to local"))
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Your Agent Slide (Screen 4)

struct YourAgentSlide: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Agent Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 16) {
                Text(NSLocalizedString("onboarding.agent.title", comment: "Your Agent title"))
                    .font(.system(size: 36, weight: .bold))
                
                Text(NSLocalizedString("onboarding.agent.subtitle", comment: "Your Agent subtitle"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(NSLocalizedString("onboarding.agent.description", comment: "Your Agent description"))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                    .padding(.top, 8)
            }
            
            // Agent features
            VStack(spacing: 12) {
                FeatureBullet(icon: "slider.horizontal.3", text: NSLocalizedString("onboarding.agent.feature1", comment: "Agent feature 1"))
                FeatureBullet(icon: "sparkles", text: NSLocalizedString("onboarding.agent.feature2", comment: "Agent feature 2"))
                FeatureBullet(icon: "gearshape", text: NSLocalizedString("onboarding.agent.feature3", comment: "Agent feature 3"))
            }
            .padding(.top, 16)
            
            // Note
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(NSLocalizedString("onboarding.agent.note", comment: "Agent note"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Permissions Slide (Screen 5)

struct PermissionsSlide: View {
    @Binding var accessibilityGranted: Bool
    @Binding var screenRecordingGranted: Bool
    @Binding var microphoneGranted: Bool
    @Binding var speechRecognitionGranted: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text(NSLocalizedString("onboarding.permissions.title", comment: "Permissions title"))
                        .font(.system(size: 36, weight: .bold))
                    
                    Text(NSLocalizedString("onboarding.permissions.description", comment: "Permissions description"))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                VStack(spacing: 16) {
                    PermissionRow(
                        icon: "hand.point.up.left.fill",
                        title: NSLocalizedString("onboarding.permissions.accessibility.title", comment: "Accessibility permission title"),
                        description: NSLocalizedString("onboarding.permissions.accessibility.description", comment: "Accessibility permission description"),
                        isGranted: accessibilityGranted,
                        isRequired: true,
                        onGrant: {
                            PermissionDeepLinker.openAccessibility()
                        }
                    )
                    
                    PermissionRow(
                        icon: "keyboard",
                        title: NSLocalizedString("onboarding.permissions.input.monitoring.title", comment: "Input Monitoring permission title"),
                        description: NSLocalizedString("onboarding.permissions.input.monitoring.description", comment: "Input Monitoring permission description"),
                        isGranted: accessibilityGranted, // Input Monitoring is part of Accessibility
                        isRequired: true,
                        onGrant: {
                            PermissionDeepLinker.openInputMonitoring()
                        }
                    )
                    
                    PermissionRow(
                        icon: "camera.fill",
                        title: NSLocalizedString("onboarding.permissions.screen.recording.title", comment: "Screen recording permission title"),
                        description: NSLocalizedString("onboarding.permissions.screen.recording.description", comment: "Screen recording permission description"),
                        isGranted: screenRecordingGranted,
                        isRequired: false,
                        onGrant: {
                            PermissionDeepLinker.openScreenRecording()
                        }
                    )
                    
                    PermissionRow(
                        icon: "mic.fill",
                        title: NSLocalizedString("onboarding.permissions.microphone.title", comment: "Microphone permission title"),
                        description: NSLocalizedString("onboarding.permissions.microphone.description", comment: "Microphone permission description"),
                        isGranted: microphoneGranted,
                        isRequired: false,
                        onGrant: {
                            PermissionManager.shared.openMicrophoneSettings()
                        }
                    )
                    
                    PermissionRow(
                        icon: "waveform",
                        title: NSLocalizedString("onboarding.permissions.speech.title", comment: "Speech recognition permission title"),
                        description: NSLocalizedString("onboarding.permissions.speech.description", comment: "Speech recognition permission description"),
                        isGranted: speechRecognitionGranted,
                        isRequired: false,
                        onGrant: {
                            PermissionManager.shared.openSpeechRecognitionSettings()
                        }
                    )
                }
            }
            .padding(40)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    var isRequired: Bool = false
    let onGrant: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            // Icon with status
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: isGranted ? 28 : 24, weight: .medium))
                    .foregroundColor(isGranted ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    
                    if isRequired {
                        Text(NSLocalizedString("onboarding.permissions.required", comment: "Required badge"))
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            if !isGranted {
                Button(NSLocalizedString("onboarding.permissions.grant.access", comment: "Grant access button"), action: onGrant)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(NSLocalizedString("onboarding.permissions.granted", comment: "Granted status"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Ready Slide (Screen 6)

struct ReadySlide: View {
    let onComplete: () -> Void
    @State private var checkmarkScale: CGFloat = 0.5
    @State private var checkmarkOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }
            
            VStack(spacing: 16) {
                Text(NSLocalizedString("onboarding.ready.title", comment: "Ready title"))
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(NSLocalizedString("onboarding.ready.description", comment: "Ready description"))
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Hotkey reminder
                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.ready.hotkey.hint", comment: "Hotkey hint"))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text("⌘ ⌥ P")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(10)
                }
                .padding(.top, 8)
            }
            
            Button(action: {
                SoundManager.shared.playSuccess()
                onComplete()
            }) {
                HStack(spacing: 10) {
                    Text(NSLocalizedString("onboarding.ready.button", comment: "Get started button"))
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 24)
            
            Spacer()
        }
        .padding(40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
        }
    }
}

// MARK: - Feature Bullet

struct FeatureBullet: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
}
