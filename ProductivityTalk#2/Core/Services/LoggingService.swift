import Foundation
import OSLog

/**
 LoggingService provides a consistent logging interface across the app.
 It uses OSLog for efficient logging and supports different log levels and components.
 */
public enum LoggingService {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.productivitytalk"
    
    private static let logger = Logger(subsystem: subsystem, category: "App")
    
    // MARK: - Standard Logging
    
    public static func debug(_ message: String, component: String) {
        logger.debug("[\(component)] \(message)")
        #if DEBUG
        print("[\(component)] 🔍 \(message)")
        #endif
    }
    
    static func info(_ message: String, component: String) {
        logger.info("[\(component)] \(message)")
        #if DEBUG
        print("[\(component)] ℹ️ \(message)")
        #endif
    }
    
    static func warning(_ message: String, component: String) {
        logger.warning("[\(component)] \(message)")
        #if DEBUG
        print("[\(component)] ⚠️ \(message)")
        #endif
    }
    
    static func error(_ message: String, component: String) {
        logger.error("[\(component)] \(message)")
        #if DEBUG
        print("[\(component)] ❌ \(message)")
        #endif
    }
    
    // MARK: - Status Logging
    
    static func success(_ message: String, component: String) {
        logger.notice("[\(component)] ✅ \(message)")
        #if DEBUG
        print("[\(component)] ✅ \(message)")
        #endif
    }
    
    static func failure(_ message: String, component: String) {
        logger.error("[\(component)] ❌ \(message)")
        #if DEBUG
        print("[\(component)] ❌ \(message)")
        #endif
    }
    
    static func critical(_ message: String, component: String) {
        logger.critical("[\(component)] 🚨 \(message)")
        #if DEBUG
        print("[\(component)] 🚨 \(message)")
        #endif
    }
    
    // MARK: - Feature Specific Logging
    
    static func network(_ message: String, component: String) {
        logger.debug("[\(component)] 🌐 \(message)")
        #if DEBUG
        print("[\(component)] 🌐 \(message)")
        #endif
    }
    
    static func storage(_ message: String, component: String) {
        logger.debug("[\(component)] 💾 \(message)")
        #if DEBUG
        print("[\(component)] 💾 \(message)")
        #endif
    }
    
    static func video(_ message: String, component: String) {
        logger.debug("[\(component)] 🎥 \(message)")
        #if DEBUG
        print("[\(component)] 🎥 \(message)")
        #endif
    }
    
    static func progress(_ operation: String, progress: Double, component: String) {
        let percentage = Int(progress * 100)
        if percentage % 10 == 0 {
            logger.info("[\(component)] 📊 Progress: \(operation) - \(percentage)%")
            #if DEBUG
            print("[\(component)] 📊 Progress: \(operation) - \(percentage)%")
            #endif
        }
    }
    
    // MARK: - Integration Logging
    
    static func integration(_ message: String, component: String) {
        logger.debug("[\(component)] 🔄 \(message)")
        #if DEBUG
        print("[\(component)] 🔄 \(message)")
        #endif
    }
    
    static func firebase(_ message: String, component: String) {
        logger.debug("[\(component)] 🔥 \(message)")
        #if DEBUG
        print("[\(component)] 🔥 \(message)")
        #endif
    }
    
    static func authentication(_ message: String, component: String) {
        logger.debug("[\(component)] 🔐 \(message)")
        #if DEBUG
        print("[\(component)] 🔐 \(message)")
        #endif
    }
} 