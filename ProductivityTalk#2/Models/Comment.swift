import Foundation
import FirebaseFirestore

struct Comment: Identifiable, Codable, Hashable {
    let id: String
    let videoId: String
    let userId: String
    let text: String
    let timestamp: Date
    var userName: String
    var userProfileImageURL: String?
    var isInSecondBrain: Bool
    var saveCount: Int
    var viewCount: Int
    
    // Use a static cache for thread-safe date formatting
    private static let dateFormattingCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 1000 // Limit cache size
        return cache
    }()
    
    enum CodingKeys: String, CodingKey {
        case id
        case videoId
        case userId
        case text
        case timestamp
        case userName
        case userProfileImageURL
        case isInSecondBrain
        case saveCount
        case viewCount
    }
    
    init(id: String = UUID().uuidString,
         videoId: String,
         userId: String,
         text: String,
         timestamp: Date = Date(),
         userName: String = "Anonymous",
         userProfileImageURL: String? = nil,
         isInSecondBrain: Bool = false,
         saveCount: Int = 0,
         viewCount: Int = 0) {
        self.id = id
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.userName = userName
        self.userProfileImageURL = userProfileImageURL
        self.isInSecondBrain = isInSecondBrain
        self.saveCount = saveCount
        self.viewCount = viewCount
    }
    
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        guard let videoId = data["videoId"] as? String,
              let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
            LoggingService.error("Failed to parse required fields from comment document \(document.documentID)", component: "Comment")
            return nil
        }
        
        self.id = document.documentID
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.userName = data["userName"] as? String ?? "Anonymous"
        self.userProfileImageURL = data["userProfileImageURL"] as? String
        self.isInSecondBrain = data["isInSecondBrain"] as? Bool ?? false
        self.saveCount = data["saveCount"] as? Int ?? 0
        self.viewCount = data["viewCount"] as? Int ?? 0
    }
    
    var toFirestore: [String: Any] {
        var data: [String: Any] = [
            "videoId": videoId,
            "userId": userId,
            "text": text,
            "timestamp": Timestamp(date: timestamp),
            "userName": userName,
            "isInSecondBrain": isInSecondBrain,
            "saveCount": saveCount,
            "viewCount": viewCount
        ]
        
        if let userProfileImageURL = userProfileImageURL {
            data["userProfileImageURL"] = userProfileImageURL
        }
        
        return data
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Comment, rhs: Comment) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Helper Methods
    func formattedDate() -> String {
        // Create a cache key using the timestamp
        let cacheKey = "\(id)_\(timestamp.timeIntervalSince1970)" as NSString
        
        // Check cache first
        if let cached = Self.dateFormattingCache.object(forKey: cacheKey) as String? {
            LoggingService.debug("Using cached date format for comment \(id)", component: "Comment")
            return cached
        }
        
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute], from: timestamp, to: now)
        
        let formatted: String
        if let days = components.day, days > 0 {
            formatted = "\(days)d ago"
        } else if let hours = components.hour, hours > 0 {
            formatted = "\(hours)h ago"
        } else if let minutes = components.minute, minutes > 0 {
            formatted = "\(minutes)m ago"
        } else {
            formatted = "just now"
        }
        
        // Cache the result
        LoggingService.debug("Caching date format for comment \(id)", component: "Comment")
        Self.dateFormattingCache.setObject(formatted as NSString, forKey: cacheKey)
        return formatted
    }
} 