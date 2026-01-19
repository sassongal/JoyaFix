import Foundation

/// Centralized constants for JoyaFix application
enum JoyaFixConstants {
    
    // MARK: - Buffer Sizes
    
    /// Maximum number of characters to keep in snippet expansion buffer
    static let maxSnippetBufferSize = 50
    
    // MARK: - History Limits
    
    
    /// Default maximum number of clipboard history items
    static let defaultMaxClipboardHistoryCount = 20
    
    /// Maximum allowed clipboard history items
    static let maxClipboardHistoryCount = 100
    
    /// Minimum allowed clipboard history items
    static let minClipboardHistoryCount = 5
    
    // MARK: - Text Limits
    
    /// Maximum length for snippet trigger
    static let maxSnippetTriggerLength = 20
    
    /// Minimum length for snippet trigger
    static let minSnippetTriggerLength = 2
    
    /// Maximum length for snippet content
    static let maxSnippetContentLength = 10_000
    
    /// Threshold for large text optimization in TextConverter
    static let largeTextOptimizationThreshold = 10_000
    
    /// Sample length for text detection (characters to analyze)
    static let textDetectionSampleLength = 1000
    
    /// Hebrew/English ratio threshold for conversion decision (0.3 = 30%)
    static let hebrewEnglishRatioThreshold: Double = 0.3
    
    // MARK: - Timing & Delays
    
    
    /// Delay for snippet backspace processing (seconds)
    /// Increased for better reliability under high CPU load
    static let snippetBackspaceDelay: TimeInterval = 0.1
    
    /// Minimum delay between backspace events (seconds)
    static let snippetBackspaceMinDelay: TimeInterval = 0.008
    
    /// Maximum delay between backspace events (seconds) - adaptive based on CPU load
    static let snippetBackspaceMaxDelay: TimeInterval = 0.02
    
    /// Delay after deletion before paste (seconds) - increased safety buffer
    static let snippetPostDeleteDelay: TimeInterval = 0.15
    
    /// Delay for clipboard paste simulation (seconds)
    static let clipboardPasteDelay: TimeInterval = 0.05
    
    /// Delay for text conversion clipboard update (seconds)
    static let textConversionClipboardDelay: TimeInterval = 0.25
    
    /// Delay for text conversion delete before paste (seconds)
    static let textConversionDeleteDelay: TimeInterval = 0.1
    
    
    // MARK: - Image Processing
    
    
    // MARK: - UI Sizes
    
    /// Menubar icon size (pixels)
    static let menubarIconSize: CGFloat = 22.0
    
    /// About window logo size (pixels)
    static let aboutLogoSize: CGFloat = 128.0
    
    /// Onboarding logo size (pixels)
    static let onboardingLogoSize: CGFloat = 120.0
    
    // MARK: - UserDefaults Keys
    
    enum UserDefaultsKeys {
        static let clipboardHistory = "ClipboardHistory"
        static let snippets = "JoyaFixSnippets"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let promptLibrary = "PromptLibrary"
    }
    
    // MARK: - Keychain
    
    enum Keychain {
        static let service = "com.joyafix.app"
        static let geminiKeyAccount = "gemini_api_key"
        static let openRouterKeyAccount = "openrouter_api_key"
    }
    
    // MARK: - API Endpoints
    
    enum API {
        // Updated to gemini-2.5-flash (stable, released June 2025)
        // gemini-1.5 models were deprecated in September 2025
        static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        static let openRouterBaseURL = "https://openrouter.ai/api/v1/chat/completions"
    }
    
    // MARK: - OpenRouter Models
    
    enum OpenRouterModel: Hashable {
        case deepseekChat
        case mistral7B
        case llama33_70B
        case gemini25Flash
        case gemini25Pro
        case custom(String)
        
        var displayName: String {
            switch self {
            case .deepseekChat:
                return "DeepSeek Chat (Free)"
            case .mistral7B:
                return "Mistral 7B Instruct (Free)"
            case .llama33_70B:
                return "Llama 3.3 70B (Free)"
            case .gemini25Flash:
                return "Gemini 2.5 Flash (Free, Vision)"
            case .gemini25Pro:
                return "Gemini 2.5 Pro (Vision)"
            case .custom(let name):
                return "Custom: \(name)"
            }
        }
        
        var modelID: String {
            switch self {
            case .deepseekChat:
                return "deepseek/deepseek-chat"
            case .mistral7B:
                return "mistralai/mistral-7b-instruct"
            case .llama33_70B:
                return "meta-llama/llama-3.3-70b-instruct"
            case .gemini25Flash:
                return "google/gemini-2.5-flash"
            case .gemini25Pro:
                return "google/gemini-2.5-pro"
            case .custom(let name):
                return name
            }
        }
        
        var supportsVision: Bool {
            switch self {
            case .gemini25Flash, .gemini25Pro:
                return true
            default:
                return false
            }
        }
        
        var isFree: Bool {
            switch self {
            case .deepseekChat, .mistral7B, .llama33_70B, .gemini25Flash:
                return true
            case .gemini25Pro, .custom:
                return false
            }
        }
        
        static var recommendedModels: [OpenRouterModel] {
            return [.deepseekChat, .mistral7B, .llama33_70B, .gemini25Flash, .gemini25Pro]
        }
        
        static func fromModelID(_ modelID: String) -> OpenRouterModel {
            switch modelID {
            case "deepseek/deepseek-chat":
                return .deepseekChat
            case "mistralai/mistral-7b-instruct":
                return .mistral7B
            case "meta-llama/llama-3.3-70b-instruct":
                return .llama33_70B
            case "google/gemini-2.5-flash":
                return .gemini25Flash
            case "google/gemini-2.5-pro":
                return .gemini25Pro
            case "google/gemini-1.5-flash":
                // Legacy support - map to 2.5-flash
                return .gemini25Flash
            default:
                return .custom(modelID)
            }
        }
    }
    
    // MARK: - File Paths
    
    enum FilePaths {
        static let clipboardDataDirectory = "JoyaFix/ClipboardData"
    }
}

