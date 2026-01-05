import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    
    let onComplete: () -> Void
    
    var body: some View {
        TabView(selection: $currentPage) {
            // Slide 1: Welcome
            WelcomeSlide()
                .tag(0)
            
            // Slide 2: Features
            FeaturesSlide()
                .tag(1)
            
            // Slide 3: Permissions
            PermissionsSlide(
                accessibilityGranted: $accessibilityGranted,
                screenRecordingGranted: $screenRecordingGranted
            )
            .tag(2)
            
            // Slide 4: Ready
            ReadySlide(onComplete: {
                hasCompletedOnboarding = true
                onComplete()
            })
            .tag(3)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(width: 600, height: 500)
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        accessibilityGranted = PermissionManager.shared.isAccessibilityTrusted()
        screenRecordingGranted = PermissionManager.shared.isScreenRecordingTrusted()
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
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: nil),
                          let logoImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                }
            }
            
            Text("Welcome to JoyaFix")
                .font(.system(size: 36, weight: .bold))
            
            Text("Your Ultimate Mac Utility")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            
            Text("Transform your workflow with smart text conversion,\nOCR, snippets, and more.")
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
            Text("Powerful Features")
                .font(.system(size: 32, weight: .bold))
                .padding(.bottom, 8)
            
            VStack(spacing: 24) {
                FeatureCard(
                    icon: "arrow.left.arrow.right",
                    title: "Fix Hebrew/English",
                    description: "Instantly convert between Hebrew and English keyboard layouts"
                )
                
                FeatureCard(
                    icon: "viewfinder",
                    title: "Smart OCR",
                    description: "Extract text from any screen region with cloud or local OCR"
                )
                
                FeatureCard(
                    icon: "text.bubble",
                    title: "Text Snippets",
                    description: "Create shortcuts that expand into full text automatically"
                )
            }
        }
        .padding(40)
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
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
            Text("Required Permissions")
                .font(.system(size: 32, weight: .bold))
                .padding(.bottom, 8)
            
            Text("JoyaFix needs these permissions to work properly:")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            VStack(spacing: 20) {
                PermissionRow(
                    title: "Accessibility",
                    description: "Required to simulate keyboard shortcuts (Cmd+C, Cmd+V, Delete)",
                    isGranted: accessibilityGranted,
                    onGrant: {
                        PermissionManager.shared.openAccessibilitySettings()
                        // Recheck after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            accessibilityGranted = PermissionManager.shared.isAccessibilityTrusted()
                        }
                    }
                )
                
                PermissionRow(
                    title: "Screen Recording",
                    description: "Required to capture screen regions for OCR",
                    isGranted: screenRecordingGranted,
                    onGrant: {
                        PermissionManager.shared.openScreenRecordingSettings()
                        // Recheck after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            screenRecordingGranted = PermissionManager.shared.isScreenRecordingTrusted()
                        }
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
                Button("Grant Access", action: onGrant)
                    .buttonStyle(.borderedProminent)
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
            
            Text("You're All Set!")
                .font(.system(size: 36, weight: .bold))
            
            Text("JoyaFix is ready to enhance your workflow.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            Button("Let's Go", action: onComplete)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 16)
        }
        .padding(40)
    }
}

