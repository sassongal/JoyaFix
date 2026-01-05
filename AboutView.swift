import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // App Icon
            Group {
                if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: "png"),
                   let logoImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else if let logoPath = Bundle.main.path(forResource: "FLATLOGO", ofType: nil),
                          let logoImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else {
                    Image("FLATLOGO")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
            }
            
            // App Name
            Text("JoyaFix")
                .font(.system(size: 36, weight: .bold))
            
            // Version
            Text("Version 1.0.0")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Credits
            VStack(spacing: 8) {
                Text("Created by")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Gal Sasson")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Powered by")
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
                    Text("Features")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.bottom, 4)
                    
                    FeatureRow(icon: "textformat", text: "Smart Text Conversion (Hebrew ↔ English)")
                    FeatureRow(icon: "viewfinder", text: "Smart OCR with Cloud & Local Support")
                    FeatureRow(icon: "keyboard", text: "Keyboard Cleaner Mode")
                    FeatureRow(icon: "text.bubble", text: "Text Snippets & Auto-Expansion")
                    FeatureRow(icon: "clipboard", text: "Advanced Clipboard History")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Copyright
            Text("© 2026 JoyaTech. All Rights Reserved.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            // Close Button
            Button("Close", action: { dismiss() })
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

