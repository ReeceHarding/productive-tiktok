import Foundation

enum LogLevel: String {
    case info = "ℹ️"
    case success = "✅"
    case warning = "⚠️"
    case error = "❌"
    case debug = "🔍"
    case network = "🌐"
    case storage = "💾"
    case video = "🎥"
    case progress = "📊"
}

class LoggingService {
    static let shared = LoggingService()
    private let appTag = "[new-productivity-talk]"
    
    private init() {}
    
    func log(_ message: String, level: LogLevel, component: String? = nil) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let componentStr = component.map { "[\($0)]" } ?? ""
        print("\(timestamp) \(appTag)\(componentStr) \(level.rawValue) \(message)")
    }
    
    func progress(_ operation: String, progress: Double, id: String? = nil) {
        let percentage = Int(progress * 100)
        if percentage % 10 == 0 {
            let idStr = id.map { "[\($0)]" } ?? ""
            log("Progress\(idStr): \(operation) - \(percentage)%", level: .progress)
        }
    }
}

// Extension for easy access
extension LoggingService {
    static func info(_ message: String, component: String? = nil) {
        shared.log(message, level: .info, component: component)
    }
    
    static func success(_ message: String, component: String? = nil) {
        shared.log(message, level: .success, component: component)
    }
    
    static func warning(_ message: String, component: String? = nil) {
        shared.log(message, level: .warning, component: component)
    }
    
    static func error(_ message: String, component: String? = nil) {
        shared.log(message, level: .error, component: component)
    }
    
    static func debug(_ message: String, component: String? = nil) {
        shared.log(message, level: .debug, component: component)
    }
    
    static func network(_ message: String, component: String? = nil) {
        shared.log(message, level: .network, component: component)
    }
    
    static func storage(_ message: String, component: String? = nil) {
        shared.log(message, level: .storage, component: component)
    }
    
    static func video(_ message: String, component: String? = nil) {
        shared.log(message, level: .video, component: component)
    }
    
    static func progress(_ operation: String, progress: Double, id: String? = nil) {
        shared.progress(operation, progress: progress, id: id)
    }
} 