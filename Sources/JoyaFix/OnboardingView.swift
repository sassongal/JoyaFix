import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var permissionCheckTimer: Timer?
    
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Current slide content
            Group {
                switch currentPage {
                case 0:
                    WelcomeSlide()
                case 1:
                    FeaturesSlide()
                case 2:
                    DetailedFeaturesSlide()
                case 3:
                    PermissionsSlide(
                        accessibilityGranted: $accessibilityGranted,
                        screenRecordingGranted: $screenRecordingGranted
                    )
                case 4:
                    ReadySlide(onComplete: {
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
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                
                Spacer()
                
                // Next/Get Started button
                if currentPage < 4 {
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

// MARK: - Welcome Slide

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

// MARK: - Features Slide

struct FeaturesSlide: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.features.title", comment: "Features title"))
                        .font(.system(size: 36, weight: .bold))
                    
                    Text(NSLocalizedString("onboarding.features.subtitle", comment: "Features subtitle"))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                VStack(spacing: 20) {
                    FeatureCard(
                        icon: "arrow.left.arrow.right",
                        iconColor: .blue,
                        title: NSLocalizedString("onboarding.feature.convert.title", comment: "Convert feature title"),
                        description: NSLocalizedString("onboarding.feature.convert.description", comment: "Convert feature description")
                    )
                    
                    FeatureCard(
                        icon: "viewfinder",
                        iconColor: .green,
                        title: NSLocalizedString("onboarding.feature.ocr.title", comment: "OCR feature title"),
                        description: NSLocalizedString("onboarding.feature.ocr.description", comment: "OCR feature description")
                    )
                    
                    FeatureCard(
                        icon: "text.bubble",
                        iconColor: .purple,
                        title: NSLocalizedString("onboarding.feature.snippets.title", comment: "Snippets feature title"),
                        description: NSLocalizedString("onboarding.feature.snippets.description", comment: "Snippets feature description"),
                        example: NSLocalizedString("onboarding.feature.snippets.example", comment: "Snippets feature example")
                    )
                }
                
                // AI Features Note
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("onboarding.ai.features.note", comment: "AI features note"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(40)
        }
    }
}

struct FeatureCard: View {
    let icon: String
    var iconColor: Color = .blue
    let title: String
    let description: String
    var example: String? = nil
    
    var body: some View {
        HStack(spacing: 20) {
            // Icon with background
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Show example if provided
                if let example = example {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(example)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .padding(.top, 4)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Detailed Features Slide

struct DetailedFeaturesSlide: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.detailed.features.title", comment: "Detailed Features Title"))
                        .font(.system(size: 36, weight: .bold))
                    
                    Text(NSLocalizedString("onboarding.detailed.features.subtitle", comment: "Detailed Features Subtitle"))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 16)
                
                VStack(spacing: 16) {
                    DetailedFeatureRow(
                        icon: "textformat",
                        iconColor: .blue,
                        title: NSLocalizedString("onboarding.detailed.convert.title", comment: "Detailed Convert Title"),
                        description: NSLocalizedString("onboarding.detailed.convert.description", comment: "Detailed Convert Description"),
                        hotkey: "⌘⌥K"
                    )
                    
                    DetailedFeatureRow(
                        icon: "viewfinder",
                        iconColor: .green,
                        title: NSLocalizedString("onboarding.detailed.ocr.title", comment: "Detailed OCR Title"),
                        description: NSLocalizedString("onboarding.detailed.ocr.description", comment: "Detailed OCR Description"),
                        hotkey: "⌘⌥X"
                    )
                    
                    DetailedFeatureRow(
                        icon: "text.bubble",
                        iconColor: .purple,
                        title: NSLocalizedString("onboarding.detailed.snippets.title", comment: "Detailed Snippets Title"),
                        description: NSLocalizedString("onboarding.detailed.snippets.description", comment: "Detailed Snippets Description"),
                        hotkey: "Auto"
                    )
                    
                    DetailedFeatureRow(
                        icon: "clipboard",
                        iconColor: .orange,
                        title: NSLocalizedString("onboarding.detailed.clipboard.title", comment: "Detailed Clipboard Title"),
                        description: NSLocalizedString("onboarding.detailed.clipboard.description", comment: "Detailed Clipboard Description"),
                        hotkey: "Click"
                    )
                    
                    DetailedFeatureRow(
                        icon: "keyboard",
                        iconColor: .red,
                        title: NSLocalizedString("onboarding.detailed.keyboard.title", comment: "Detailed Keyboard Title"),
                        description: NSLocalizedString("onboarding.detailed.keyboard.description", comment: "Detailed Keyboard Description"),
                        hotkey: "⌘⌥L"
                    )
                    
                    DetailedFeatureRow(
                        icon: "sparkles",
                        iconColor: .pink,
                        title: NSLocalizedString("onboarding.detailed.ai.title", comment: "Detailed AI Title"),
                        description: NSLocalizedString("onboarding.detailed.ai.description", comment: "Detailed AI Description"),
                        hotkey: "⌘⌥P"
                    )
                }
            }
            .padding(40)
        }
    }
}

struct DetailedFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let hotkey: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    
                    Spacer()
                    
                    // Hotkey badge
                    Text(hotkey)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
        )
    }
}

// MARK: - Permissions Slide

struct PermissionsSlide: View {
    @Binding var accessibilityGranted: Bool
    @Binding var screenRecordingGranted: Bool
    
    var body: some View {
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
            
            VStack(spacing: 20) {
                PermissionRow(
                    icon: "hand.point.up.left.fill",
                    title: NSLocalizedString("onboarding.permissions.accessibility.title", comment: "Accessibility permission title"),
                    description: NSLocalizedString("onboarding.permissions.accessibility.description", comment: "Accessibility permission description"),
                    isGranted: accessibilityGranted,
                    onGrant: {
                        PermissionManager.shared.openAccessibilitySettings()
                        // Polling will automatically detect the change
                    }
                )
                
                PermissionRow(
                    icon: "camera.fill",
                    title: NSLocalizedString("onboarding.permissions.screen.recording.title", comment: "Screen recording permission title"),
                    description: NSLocalizedString("onboarding.permissions.screen.recording.description", comment: "Screen recording permission description"),
                    isGranted: screenRecordingGranted,
                    onGrant: {
                        PermissionManager.shared.openScreenRecordingSettings()
                        // Polling will automatically detect the change
                    }
                )
            }
        }
        .padding(40)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
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
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                
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

// MARK: - Ready Slide

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

