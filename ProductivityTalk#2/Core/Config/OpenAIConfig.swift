import Foundation

enum OpenAIConfig {
    /// The OpenAI API key used for Whisper and GPT-4 requests
    static var apiKey: String {
        // In production, load from keychain or encrypted storage
        // For development, load from environment
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            fatalError("OPENAI_API_KEY environment variable not set. Please set it in Xcode scheme.")
        }
        return key
    }
    
    /// Base URL for OpenAI API
    static let baseURL = "https://api.openai.com/v1"
    
    /// Endpoints
    enum Endpoint {
        static let transcription = "/audio/transcriptions"
        static let chat = "/chat/completions"
    }
    
    /// Models
    enum Model {
        static let whisper = "whisper-1"
        static let gpt4 = "gpt-4"
    }
    
    /// Request configuration
    enum Config {
        static let maxTranscriptionSize = 25 * 1024 * 1024  // 25MB max for Whisper
        static let maxTokens = 4096  // For GPT-4
        static let timeout: TimeInterval = 300  // 5 minutes
    }
} 