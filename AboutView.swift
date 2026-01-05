import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    /// Fail-safe logo loading - tries multiple methods
    private func loadLogoImage() -> NSImage? {
        // Method 1: Try from bundle with .png extension
        if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: "png"),
           let logoImage = NSImage(contentsOfFile: logoPath) {
            return logoImage
        }
        
        // Method 2: Try from bundle without extension
        if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: nil),
           let logoImage = NSImage(contentsOfFile: logoPath) {
            return logoImage
        }
        
        // Method 3: Try using NSImage(named:) (for production bundle)
        if let logoImage = NSImage(named: "FLATLOGO") {
            return logoImage
        }
        
        // Method 4: Development path (only in DEBUG builds)
        #if DEBUG
        let devPath = "/Users/galsasson/Desktop/JoyaFix/FLATLOGO.png"
        if FileManager.default.fileExists(atPath: devPath),
           let logoImage = NSImage(contentsOfFile: devPath) {
            return logoImage
        }
        #endif
        
        return nil
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // App Icon - Fail-safe logo loading
            Group {
                // Try multiple methods to load logo (development and production)
                if let logoImage = loadLogoImage() {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: JoyaFixConstants.aboutLogoSize, height: JoyaFixConstants.aboutLogoSize)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else {
                    // Fallback: System icon if logo not found
                    Image(systemName: "app.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .frame(width: 128, height: 128)
                }
            }
            
            // App Name
            Text(NSLocalizedString("about.app.name", comment: "App name"))
                .font(.system(size: 36, weight: .bold))
            
            // Version
            Text(String(format: NSLocalizedString("about.version", comment: "Version"), "1.0.0"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Credits
            VStack(spacing: 8) {
                Text(NSLocalizedString("about.created.by", comment: "Created by"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Gal Sasson")
                    .font(.system(size: 16, weight: .semibold))
                
                Text(NSLocalizedString("about.powered.by", comment: "Powered by"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Text("JoyaTech")
                    .font(.system(size: 16, weight: .semibold))
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Features
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("about.features", comment: "Features"))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.bottom, 4)
                    
                    FeatureRow(icon: "textformat", text: NSLocalizedString("about.feature.text.conversion", comment: "Text conversion feature"))
                    FeatureRow(icon: "viewfinder", text: NSLocalizedString("about.feature.ocr", comment: "OCR feature"))
                    FeatureRow(icon: "keyboard", text: NSLocalizedString("about.feature.keyboard.cleaner", comment: "Keyboard cleaner feature"))
                    FeatureRow(icon: "text.bubble", text: NSLocalizedString("about.feature.snippets", comment: "Snippets feature"))
                    FeatureRow(icon: "clipboard", text: NSLocalizedString("about.feature.clipboard", comment: "Clipboard feature"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Copyright
            Text(NSLocalizedString("about.copyright", comment: "Copyright"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            // Close Button
            Button(NSLocalizedString("about.close", comment: "Close button"), action: { dismiss() })
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(width: 500, height: 700)
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
        }
        .padding(.vertical, 2)
    }
}

