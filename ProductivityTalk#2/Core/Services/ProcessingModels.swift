import Foundation

public enum ProcessingStatus: String, Codable {
    case uploading
    case extractingAudio
    case transcribing
    case analyzing
    case ready
    case error
}

public struct ProcessingProgress {
    public let step: ProcessingStatus
    public let progress: Double
    public let message: String

    public init(step: ProcessingStatus, progress: Double = 0.0, message: String = "") {
        self.step = step
        self.progress = progress
        self.message = message
    }
} 