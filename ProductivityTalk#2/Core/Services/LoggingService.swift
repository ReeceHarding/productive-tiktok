import Foundation
import OSLog

/**
 LoggingService provides a consistent logging interface across the app.
 It uses OSLog for efficient logging and supports different log levels and components.
 */
enum LoggingService {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.productivitytalk"
    
    private static let logger = Logger(subsystem: subsystem, category: "App")
    
    static func debug(_ message: String, component: String) {
        logger.debug("[\(component)] \(message)")
    }
    
    static func info(_ message: String, component: String) {
        logger.info("[\(component)] \(message)")
    }
    
    static func warning(_ message: String, component: String) {
        logger.warning("[\(component)] \(message)")
    }
    
    static func error(_ message: String, component: String) {
        logger.error("[\(component)] \(message)")
    }
    
    static func success(_ message: String, component: String) {
        logger.notice("[\(component)] ✅ \(message)")
    }
    
    static func failure(_ message: String, component: String) {
        logger.error("[\(component)] ❌ \(message)")
    }
    
    static func critical(_ message: String, component: String) {
        logger.critical("[\(component)] 🚨 \(message)")
    }
    
    static func network(_ message: String, component: String) {
        logger.debug("[\(component)] 🌐 \(message)")
    }
    
    static func storage(_ message: String, component: String) {
        logger.debug("[\(component)] 💾 \(message)")
    }
    
    static func video(_ message: String, component: String) {
        logger.debug("[\(component)] 🎥 \(message)")
    }
    
    static func progress(_ operation: String, progress: Double, component: String) {
        let percentage = Int(progress * 100)
        if percentage % 10 == 0 {
            logger.info("[\(component)] 📊 Progress: \(operation) - \(percentage)%")
        }
    }
} 