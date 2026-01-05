import SwiftUI

/// Toggle view for Launch at Login setting
struct LaunchAtLoginToggle: View {
    @State private var isEnabled: Bool = LaunchAtLoginManager.shared.isEnabled
    @State private var showPermissionAlert = false
    
    var body: some View {
        HStack {
            Text(NSLocalizedString("settings.launch.at.login", comment: "Launch at Login"))
                .font(.body)
            Spacer()
            
            // Use custom Binding to prevent loop and handle errors
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    // Attempt to change the setting
                    let success = LaunchAtLoginManager.shared.setLaunchAtLogin(newValue)
                    if success {
                        isEnabled = newValue
                    } else {
                        // If failed, don't change the toggle state and show error
                        // The local state (isEnabled) doesn't change, so toggle reverts automatically
                        showPermissionAlert = true
                    }
                }
            ))
            .toggleStyle(.switch)
        }
        .alert(NSLocalizedString("settings.launch.at.login.error.title", comment: "Error"), isPresented: $showPermissionAlert) {
            // Button that deep-links directly to Login Items settings
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(NSLocalizedString("alert.button.cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text("macOS requires you to manually enable JoyaFix in System Settings > General > Login Items.\n\nPlease click 'Open System Settings' and toggle the switch for JoyaFix.")
        }
    }
}

