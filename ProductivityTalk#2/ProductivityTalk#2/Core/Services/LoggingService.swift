import Foundation

public enum LogLevel: String {
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

public class LoggingService {
    public static let shared = LoggingService()
    private let appTag = "[new-productivity-talk]"
    
    private init() {}
    
    public func log(_ message: String, level: LogLevel, component: String? = nil) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let componentStr = component.map { "[\($0)]" } ?? ""
        print("\(timestamp) \(appTag)\(componentStr) \(level.rawValue) \(message)")
    }
    
    public func progress(_ operation: String, progress: Double, id: String? = nil) {
        let percentage = Int(progress * 100)
        if percentage % 10 == 0 {
            let idStr = id.map { "[\($0)]" } ?? ""
            log("Progress\(idStr): \(operation) - \(percentage)%", level: .progress)
        }
    }
}

// Extension for easy access
extension LoggingService {
    public static func info(_ message: String, component: String? = nil) {
        shared.log(message, level: .info, component: component)
    }
    
    public static func success(_ message: String, component: String? = nil) {
        shared.log(message, level: .success, component: component)
    }
    
    public static func warning(_ message: String, component: String? = nil) {
        shared.log(message, level: .warning, component: component)
    }
    
    public static func error(_ message: String, component: String? = nil) {
        shared.log(message, level: .error, component: component)
    }
    
    public static func debug(_ message: String, component: String? = nil) {
        shared.log(message, level: .debug, component: component)
    }
    
    public static func network(_ message: String, component: String? = nil) {
        shared.log(message, level: .network, component: component)
    }
    
    public static func storage(_ message: String, component: String? = nil) {
        shared.log(message, level: .storage, component: component)
    }
    
    public static func video(_ message: String, component: String? = nil) {
        shared.log(message, level: .video, component: component)
    }
    
    public static func progress(_ operation: String, progress: Double, id: String? = nil) {
        shared.progress(operation, progress: progress, id: id)
    }
} 