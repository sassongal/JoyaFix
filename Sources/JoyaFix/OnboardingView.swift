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
                    PermissionsSlide(
                        accessibilityGranted: $accessibilityGranted,
                        screenRecordingGranted: $screenRecordingGranted
                    )
                case 3:
                    ReadySlide(onComplete: {
                        hasCompletedOnboarding = true
                        onComplete()
                    })
                default:
                    WelcomeSlide()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            
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
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                // Next/Get Started button
                if currentPage < 3 {
                    Button(action: {
                        withAnimation {
                            currentPage += 1
                        }
                    }) {
                        HStack {
                            Text(NSLocalizedString("onboarding.next", comment: "Next button"))
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
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
    var body: some View {
        VStack(spacing: 24) {
            // Logo
            Group {
                if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: "png"),
                   let logoImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: JoyaFixConstants.onboardingLogoSize, height: JoyaFixConstants.onboardingLogoSize)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: nil),
                          let logoImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: JoyaFixConstants.onboardingLogoSize, height: JoyaFixConstants.onboardingLogoSize)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else {
                    Image("FLATLOGO")
                        .resizable()
                        .scaledToFit()
                        .frame(width: JoyaFixConstants.onboardingLogoSize, height: JoyaFixConstants.onboardingLogoSize)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
            }
            
            Text(NSLocalizedString("onboarding.welcome.title", comment: "Welcome title"))
                .font(.system(size: 36, weight: .bold))
            
            Text(NSLocalizedString("onboarding.welcome.subtitle", comment: "Welcome subtitle"))
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            
            Text(NSLocalizedString("onboarding.welcome.description", comment: "Welcome description"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(40)
    }
}

// MARK: - Features Slide

struct FeaturesSlide: View {
    var body: some View {
        VStack(spacing: 32) {
            Text(NSLocalizedString("onboarding.features.title", comment: "Features title"))
                .font(.system(size: 32, weight: .bold))
                .padding(.bottom, 8)
            
            VStack(spacing: 24) {
                FeatureCard(
                    icon: "arrow.left.arrow.right",
                    title: NSLocalizedString("onboarding.feature.convert.title", comment: "Convert feature title"),
                    description: NSLocalizedString("onboarding.feature.convert.description", comment: "Convert feature description")
                )
                
                FeatureCard(
                    icon: "viewfinder",
                    title: NSLocalizedString("onboarding.feature.ocr.title", comment: "OCR feature title"),
                    description: NSLocalizedString("onboarding.feature.ocr.description", comment: "OCR feature description")
                )
                
                FeatureCard(
                    icon: "text.bubble",
                    title: NSLocalizedString("onboarding.feature.snippets.title", comment: "Snippets feature title"),
                    description: NSLocalizedString("onboarding.feature.snippets.description", comment: "Snippets feature description"),
                    example: NSLocalizedString("onboarding.feature.snippets.example", comment: "Snippets feature example")
                )
            }
            
            // AI Features Note
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text(NSLocalizedString("onboarding.ai.features.note", comment: "AI features note"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(.top, 8)
        }
        .padding(40)
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    var example: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                    .frame(width: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Show example if provided
            if let example = example {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(example)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(.leading, 66) // Align with content above
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Permissions Slide

struct PermissionsSlide: View {
    @Binding var accessibilityGranted: Bool
    @Binding var screenRecordingGranted: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            Text(NSLocalizedString("onboarding.permissions.title", comment: "Permissions title"))
                .font(.system(size: 32, weight: .bold))
                .padding(.bottom, 8)
            
            Text(NSLocalizedString("onboarding.permissions.description", comment: "Permissions description"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            VStack(spacing: 20) {
                PermissionRow(
                    title: NSLocalizedString("onboarding.permissions.accessibility.title", comment: "Accessibility permission title"),
                    description: NSLocalizedString("onboarding.permissions.accessibility.description", comment: "Accessibility permission description"),
                    isGranted: accessibilityGranted,
                    onGrant: {
                        PermissionManager.shared.openAccessibilitySettings()
                        // Polling will automatically detect the change
                    }
                )
                
                PermissionRow(
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
    let title: String
    let description: String
    let isGranted: Bool
    let onGrant: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(isGranted ? .green : .red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !isGranted {
                Button(NSLocalizedString("onboarding.permissions.grant.access", comment: "Grant access button"), action: onGrant)
                    .buttonStyle(.borderedProminent)
            } else {
                Text(NSLocalizedString("onboarding.permissions.granted", comment: "Granted status"))
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Ready Slide

struct ReadySlide: View {
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text(NSLocalizedString("onboarding.ready.title", comment: "Ready title"))
                .font(.system(size: 36, weight: .bold))
            
            Text(NSLocalizedString("onboarding.ready.description", comment: "Ready description"))
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            Button(NSLocalizedString("onboarding.ready.button", comment: "Get started button"), action: onComplete)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 16)
        }
        .padding(40)
    }
}

