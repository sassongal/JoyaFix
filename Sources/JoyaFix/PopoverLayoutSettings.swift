import SwiftUI
import Foundation

/// Settings for popover layout customization
struct PopoverLayoutSettings: Codable {
    var viewMode: ViewMode = .list
    var itemSize: ItemSize = .normal
    var theme: Theme = .default
    var layoutTemplate: LayoutTemplate = .general
    
    enum ViewMode: String, Codable, CaseIterable {
        case list = "List"
        case grid = "Grid"
    }
    
    enum ItemSize: String, Codable, CaseIterable {
        case compact = "Compact"
        case normal = "Normal"
        case large = "Large"
        
        var rowHeight: CGFloat {
            switch self {
            case .compact: return 50
            case .normal: return 70
            case .large: return 100
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .compact: return 11
            case .normal: return 14
            case .large: return 16
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .compact: return 14
            case .normal: return 16
            case .large: return 20
            }
        }
    }
    
    enum Theme: String, Codable, CaseIterable {
        case `default` = "Default"
        case dark = "Dark"
        case light = "Light"
        case colorful = "Colorful"
        case minimal = "Minimal"
        
        var backgroundColor: Color {
            switch self {
            case .default: return Color(NSColor.controlBackgroundColor)
            case .dark: return Color(NSColor.controlBackgroundColor).opacity(0.8)
            case .light: return Color.white
            case .colorful: return Color.blue.opacity(0.1)
            case .minimal: return Color.clear
            }
        }
        
        var accentColor: Color {
            switch self {
            case .default: return .accentColor
            case .dark: return .white
            case .light: return .blue
            case .colorful: return .purple
            case .minimal: return .gray
            }
        }
    }
    
    enum LayoutTemplate: String, Codable, CaseIterable {
        case general = "General"
        case developer = "Developer"
        case writer = "Writer"
        case student = "Student"
        
        var settings: PopoverLayoutSettings {
            switch self {
            case .general:
                return PopoverLayoutSettings()
            case .developer:
                return PopoverLayoutSettings(
                    viewMode: .list,
                    itemSize: .compact,
                    theme: .dark,
                    layoutTemplate: .developer
                )
            case .writer:
                return PopoverLayoutSettings(
                    viewMode: .list,
                    itemSize: .normal,
                    theme: .light,
                    layoutTemplate: .writer
                )
            case .student:
                return PopoverLayoutSettings(
                    viewMode: .grid,
                    itemSize: .normal,
                    theme: .colorful,
                    layoutTemplate: .student
                )
            }
        }
    }
}

/// Toast notification settings
struct ToastSettings: Codable {
    var position: ToastPosition = .topRight
    var duration: ToastDuration = .threeSeconds
    var sound: ToastSound = .default
    var visualStyle: ToastVisualStyle = .minimal
    
    enum ToastPosition: String, Codable, CaseIterable {
        case topRight = "Top Right"
        case bottomRight = "Bottom Right"
        case center = "Center"
        case topLeft = "Top Left"
        case bottomLeft = "Bottom Left"
    }
    
    enum ToastDuration: Double, Codable, CaseIterable {
        case oneSecond = 1.0
        case threeSeconds = 3.0
        case fiveSeconds = 5.0
        case off = 0.0
        
        var displayName: String {
            switch self {
            case .oneSecond: return "1 second"
            case .threeSeconds: return "3 seconds"
            case .fiveSeconds: return "5 seconds"
            case .off: return "Off"
            }
        }
    }
    
    enum ToastSound: String, Codable, CaseIterable {
        case `default` = "Default"
        case success = "Success"
        case error = "Error"
        case notification = "Notification"
        case chime = "Chime"
        case custom = "Custom"
        
        var soundName: String? {
            switch self {
            case .default: return "default"
            case .success: return "success"
            case .error: return "error"
            case .notification: return "notification"
            case .chime: return "chime"
            case .custom: return nil // User-defined
            }
        }
    }
    
    enum ToastVisualStyle: String, Codable, CaseIterable {
        case minimal = "Minimal"
        case detailed = "Detailed"
        
        var showIcon: Bool {
            switch self {
            case .minimal: return false
            case .detailed: return true
            }
        }
        
        var showBackground: Bool {
            switch self {
            case .minimal: return false
            case .detailed: return true
            }
        }
    }
}
