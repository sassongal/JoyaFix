import Foundation

/// Centralized constants for JoyaFix application
enum JoyaFixConstants {
    
    // MARK: - Buffer Sizes
    
    /// Maximum number of characters to keep in snippet expansion buffer
    static let maxSnippetBufferSize = 50
    
    // MARK: - History Limits
    
    /// Maximum number of OCR scans to keep in history
    static let maxOCRHistoryCount = 50
    
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
    
    /// Delay before capturing screen after selection (seconds)
    static let ocrCaptureDelay: TimeInterval = 0.1
    
    /// Delay after canceling selection (seconds)
    static let ocrCancelDelay: TimeInterval = 0.05
    
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
    
    // MARK: - OCR Rate Limiting
    
    /// Maximum number of Cloud OCR requests per minute
    static let maxCloudOCRRequestsPerMinute = 10
    
    /// Time window for rate limiting (seconds)
    static let rateLimitWindow: TimeInterval = 60.0
    
    /// Initial retry delay for failed OCR requests (seconds)
    static let ocrRetryInitialDelay: TimeInterval = 1.0
    
    /// Maximum retry delay for exponential backoff (seconds)
    static let ocrRetryMaxDelay: TimeInterval = 30.0
    
    /// Maximum number of retry attempts for OCR
    static let ocrMaxRetryAttempts = 3
    
    // MARK: - Image Processing
    
    /// JPEG compression factor for Cloud OCR
    static let cloudOCRCompressionFactor: CGFloat = 0.8
    
    /// Minimum selection size for OCR (pixels)
    static let minOCRSelectionSize: CGFloat = 10.0
    
    /// Minimum dimension threshold for OCR upscaling (pixels)
    /// Images smaller than this will be upscaled to improve OCR accuracy
    static let ocrMinDimensionThreshold: CGFloat = 400.0
    
    /// Target minimum dimension after upscaling (pixels)
    /// Small images will be scaled to reach at least this dimension
    static let ocrTargetMinDimension: CGFloat = 800.0
    
    /// Maximum scale factor for OCR upscaling
    /// Prevents over-processing of very small images
    static let ocrMaxScaleFactor: CGFloat = 4.0
    
    /// Minimum scale factor for OCR upscaling
    /// Ensures meaningful upscaling when applied
    static let ocrMinScaleFactor: CGFloat = 1.2
    
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
        static let ocrHistory = "OCRHistory"
        static let snippets = "JoyaFixSnippets"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let promptLibrary = "PromptLibrary"
    }
    
    // MARK: - Keychain
    
    enum Keychain {
        static let service = "com.joyafix.app"
        static let geminiKeyAccount = "gemini_api_key"
    }
    
    // MARK: - API Endpoints
    
    enum API {
        static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    }
    
    // MARK: - File Paths
    
    enum FilePaths {
        static let ocrPreviewsDirectory = "JoyaFix/OCRPreviews"
        static let clipboardDataDirectory = "JoyaFix/ClipboardData"
    }
}

