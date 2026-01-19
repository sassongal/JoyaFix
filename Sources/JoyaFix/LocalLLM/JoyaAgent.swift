import Foundation

/// Represents an AI agent configuration with system instructions and parameters
struct JoyaAgent: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var systemInstructions: String
    var temperature: Double
    var maxTokens: Int
    
    /// Default agent for general text enhancement
    static let `default` = JoyaAgent(
        name: "Joya Standard",
        systemInstructions: "You are a helpful AI assistant specialized in text enhancement. Improve clarity, grammar, and style while preserving the original meaning.",
        temperature: 0.7,
        maxTokens: 1024
    )
    
    /// Agent optimized for code review and programming tasks
    static let coder = JoyaAgent(
        name: "Code Expert",
        systemInstructions: "You are an expert software engineer. Review code, fix bugs, and optimize performance. Provide concise explanations.",
        temperature: 0.2,
        maxTokens: 2048
    )
    
    /// Agent for creative writing
    static let creative = JoyaAgent(
        name: "Creative Writer",
        systemInstructions: "You are a creative writing assistant. Enhance text with vivid descriptions, engaging narrative, and stylistic flair while maintaining the core message.",
        temperature: 0.9,
        maxTokens: 2048
    )
    
    /// Agent for formal/professional writing
    static let formal = JoyaAgent(
        name: "Professional Editor",
        systemInstructions: "You are a professional editor. Refine text for formal communication, business documents, and academic writing. Ensure clarity, precision, and professional tone.",
        temperature: 0.3,
        maxTokens: 1024
    )
    
    /// Agent for translation tasks
    static let translator = JoyaAgent(
        name: "Translator",
        systemInstructions: "You are a professional translator. Translate text accurately while preserving tone, context, and cultural nuances. Maintain natural flow in the target language.",
        temperature: 0.5,
        maxTokens: 2048
    )
    
    /// Predefined agents available to users
    static let predefinedAgents: [JoyaAgent] = [
        .default,
        .coder,
        .creative,
        .formal,
        .translator
    ]
}
