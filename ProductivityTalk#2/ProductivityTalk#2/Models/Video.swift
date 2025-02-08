import Foundation
import FirebaseFirestore

public enum VideoProcessingStatus: String, Codable {
    case uploading = "uploading"
    case ready = "ready"
    case error = "error"
}

public struct Video: Identifiable, Codable {
    public var id: String
    public let ownerId: String
    public var videoURL: String
    public let thumbnailURL: String?
    public let title: String
    public var tags: [String]
    public var description: String
    public let createdAt: Date
    public var likeCount: Int
    public var saveCount: Int
    public var commentCount: Int
    public var processingStatus: VideoProcessingStatus
    public var transcript: String?
    public var extractedQuotes: [String]?
    public var autoTitle: String?
    public var autoDescription: String?
    public var autoTags: [String]?
    
    // Additional metadata for UI
    public var ownerUsername: String
    public var ownerProfilePicURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerId
        case videoURL
        case thumbnailURL
        case title
        case tags
        case description
        case createdAt
        case likeCount
        case saveCount
        case commentCount
        case ownerUsername
        case ownerProfilePicURL
        case processingStatus
        case transcript
        case extractedQuotes
        case autoTitle
        case autoDescription
        case autoTags
    }
    
    // Initialize from Firestore document
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else {
            LoggingService.error("Failed to initialize - No data in document", component: "Video")
            return nil
        }
        
        self.id = document.documentID
        guard let ownerId = data["ownerId"] as? String,
              let videoURL = data["videoURL"] as? String,
              let thumbnailURL = data["thumbnailURL"] as? String,
              let title = data["title"] as? String,
              let tags = data["tags"] as? [String],
              let description = data["description"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let ownerUsername = data["ownerUsername"] as? String,
              let processingStatusRaw = data["processingStatus"] as? String,
              let processingStatus = VideoProcessingStatus(rawValue: processingStatusRaw) else {
            LoggingService.error("Failed to initialize - Missing required fields", component: "Video")
            return nil
        }
        
        self.ownerId = ownerId
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.tags = tags
        self.description = description
        self.createdAt = createdAt
        self.likeCount = (data["likeCount"] as? Int) ?? 0
        self.saveCount = (data["saveCount"] as? Int) ?? 0
        self.commentCount = (data["commentCount"] as? Int) ?? 0
        self.ownerUsername = ownerUsername
        self.ownerProfilePicURL = data["ownerProfilePicURL"] as? String
        self.processingStatus = processingStatus
        self.transcript = data["transcript"] as? String
        self.extractedQuotes = data["extractedQuotes"] as? [String]
        self.autoTitle = data["autoTitle"] as? String
        self.autoDescription = data["autoDescription"] as? String
        self.autoTags = data["autoTags"] as? [String]
        
        LoggingService.success("Successfully initialized video with ID: \(id)", component: "Video")
    }
    
    // Initialize directly
    init(id: String, ownerId: String, videoURL: String, thumbnailURL: String, 
         title: String, tags: [String], description: String, ownerUsername: String,
         ownerProfilePicURL: String? = nil) {
        
        self.id = id
        self.ownerId = ownerId
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.tags = tags
        self.description = description
        self.createdAt = Date()
        self.likeCount = 0
        self.saveCount = 0
        self.commentCount = 0
        self.ownerUsername = ownerUsername
        self.ownerProfilePicURL = ownerProfilePicURL
        self.processingStatus = .uploading
        self.transcript = nil
        self.extractedQuotes = nil
        self.autoTitle = nil
        self.autoDescription = nil
        self.autoTags = nil
        
        LoggingService.success("Created new video with ID: \(id)", component: "Video")
    }
    
    // Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "ownerId": ownerId,
            "videoURL": videoURL,
            "thumbnailURL": thumbnailURL ?? "",
            "title": title,
            "tags": tags,
            "description": description,
            "createdAt": Timestamp(date: createdAt),
            "likeCount": likeCount,
            "saveCount": saveCount,
            "commentCount": commentCount,
            "ownerUsername": ownerUsername,
            "processingStatus": processingStatus.rawValue
        ]
        
        if let ownerProfilePicURL = ownerProfilePicURL {
            data["ownerProfilePicURL"] = ownerProfilePicURL
        }
        
        if let transcript = transcript {
            data["transcript"] = transcript
        }
        
        if let extractedQuotes = extractedQuotes {
            data["extractedQuotes"] = extractedQuotes
        }
        
        if let autoTitle = autoTitle {
            data["autoTitle"] = autoTitle
        }
        
        if let autoDescription = autoDescription {
            data["autoDescription"] = autoDescription
        }
        
        if let autoTags = autoTags {
            data["autoTags"] = autoTags
        }
        
        LoggingService.success("Converted video data to Firestore format", component: "Video")
        return data
    }
} 