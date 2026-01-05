import SwiftUI

/// Toggle view for Launch at Login setting
struct LaunchAtLoginToggle: View {
    @State private var isEnabled: Bool = LaunchAtLoginManager.shared.isEnabled
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        HStack {
            Text(NSLocalizedString("settings.launch.at.login", comment: "Launch at Login"))
                .font(.body)
            Spacer()
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .onChange(of: isEnabled) { _, newValue in
                    let success = LaunchAtLoginManager.shared.setLaunchAtLogin(newValue)
                    if !success {
                        // Revert toggle if operation failed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isEnabled = !newValue
                            let actionKey = newValue ? "enable" : "disable"
                            let action = NSLocalizedString(actionKey, comment: actionKey)
                            errorMessage = String(format: NSLocalizedString("settings.launch.at.login.error", comment: "Launch at Login error"), action)
                            showError = true
                        }
                    }
                }
        }
        .alert(NSLocalizedString("settings.launch.at.login.error.title", comment: "Launch at Login Error"), isPresented: $showError) {
            Button(NSLocalizedString("alert.button.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}

