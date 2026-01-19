import SwiftUI
import Combine

// MARK: - Toast Message Model

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let style: ToastStyle
    let duration: TimeInterval

    enum ToastStyle {
        case success, error, warning, info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }
    }

    init(text: String, style: ToastStyle = .info, duration: TimeInterval = 3.0) {
        self.text = text
        self.style = style
        self.duration = duration
    }
}

// MARK: - Toast Manager

class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentToast: ToastMessage?

    private var hideTask: Task<Void, Never>?
    private var toastWindow: NSWindow?
    
    private var settings: ToastSettings {
        SettingsManager.shared.toastSettings
    }

    private init() {
        // Setup NotificationCenter listener
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowToastNotification(_:)),
            name: .showToast,
            object: nil
        )
        
        // Observe settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func settingsChanged() {
        // Update toast if currently showing
        if currentToast != nil {
            hide()
        }
    }

    @objc private func handleShowToastNotification(_ notification: Notification) {
        if let message = notification.object as? ToastMessage {
            show(message)
        }
    }

    func show(_ message: ToastMessage) {
        Task { @MainActor in
            // Cancel previous hide task
            hideTask?.cancel()
            
            // Use settings duration if message duration is default
            let duration = message.duration == 3.0 ? settings.duration.rawValue : message.duration
            
            // Play sound if enabled
            if duration > 0 {
                playSound(settings.sound)
            }

            // Show new toast with animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentToast = message
            }

            // Auto-hide after duration (if not off)
            if duration > 0 {
                hideTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if currentToast?.id == message.id {
                                currentToast = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func playSound(_ sound: ToastSettings.ToastSound) {
        guard let soundName = sound.soundName else { return }
        
        // Try to play system sound
        if soundName == "default" {
            NSSound.beep()
        } else if let soundFile = NSSound(named: soundName) {
            soundFile.play()
        } else {
            // Fallback to beep
            NSSound.beep()
        }
    }

    func hide() {
        Task { @MainActor in
            hideTask?.cancel()
            withAnimation(.spring(response: 0.2, dampingFraction: 1.0)) {
                currentToast = nil
            }
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: ToastMessage
    @ObservedObject private var settings = SettingsManager.shared
    
    private var toastSettings: ToastSettings {
        settings.toastSettings
    }
    
    private var position: ToastSettings.ToastPosition {
        toastSettings.position
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon (only if detailed style)
            if toastSettings.visualStyle.showIcon {
                Image(systemName: message.style.icon)
                    .foregroundColor(message.style.color)
                    .font(.system(size: 20))
                    .frame(width: 24)
            }

            // Text
            Text(message.text)
                .font(.system(size: toastSettings.visualStyle == .minimal ? 12 : 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, toastSettings.visualStyle == .minimal ? 12 : 16)
        .padding(.vertical, toastSettings.visualStyle == .minimal ? 8 : 12)
        .background(
            Group {
                if toastSettings.visualStyle.showBackground {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                }
            }
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: 400)
        .transition(transitionForPosition)
    }
    
    private var transitionForPosition: AnyTransition {
        switch position {
        case .topRight, .topLeft:
            return .move(edge: .top).combined(with: .opacity)
        case .bottomRight, .bottomLeft:
            return .move(edge: .bottom).combined(with: .opacity)
        case .center:
            return .scale.combined(with: .opacity)
        }
    }
}

// MARK: - NotificationCenter Extensions

extension Notification.Name {
    static let showToast = Notification.Name("showToast")
    static let hideToast = Notification.Name("hideToast")
}

// MARK: - Global Helper Functions

/// Shows a toast notification
/// - Parameters:
///   - text: The message to display
///   - style: Visual style (.success, .error, .warning, .info)
///   - duration: How long to show (default: 3 seconds)
func showToast(_ text: String, style: ToastMessage.ToastStyle = .info, duration: TimeInterval = 3.0) {
    let message = ToastMessage(text: text, style: style, duration: duration)
    NotificationCenter.default.post(name: .showToast, object: message)
}

/// Hides the current toast immediately
func hideToast() {
    NotificationCenter.default.post(name: .hideToast, object: nil)
}
