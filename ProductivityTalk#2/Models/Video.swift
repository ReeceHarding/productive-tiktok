import Foundation
import FirebaseFirestore

public enum VideoProcessingStatus: String, Codable {
    case uploading = "uploading"
    case transcribing = "transcribing"
    case extractingQuotes = "extracting_quotes"
    case generatingMetadata = "generating_metadata"
    case processing = "processing"
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
    public var brainCount: Int
    public var viewCount: Int
    public var processingStatus: VideoProcessingStatus
    public var transcript: String?
    public var extractedQuotes: [String]?
    public var quotes: [String]?
    public var autoTitle: String?
    public var autoDescription: String?
    public var autoTags: [String]?
    
    // Additional metadata for UI
    public var ownerUsername: String
    public var ownerProfilePicURL: String?
    
    // MARK: - Mock Data for Previews
    public static let mock = Video(
        id: "mock_video",
        ownerId: "mock_user",
        videoURL: "https://example.com/mock_video.mp4",
        thumbnailURL: "https://example.com/mock_thumbnail.jpg",
        title: "Mock Video",
        tags: ["productivity", "tech"],
        description: "This is a mock video for SwiftUI previews",
        createdAt: Date(),
        likeCount: 100,
        saveCount: 50,
        commentCount: 25,
        brainCount: 10,
        viewCount: 1000,
        processingStatus: .ready,
        transcript: "This is a mock transcript",
        extractedQuotes: ["Mock quote 1", "Mock quote 2"],
        quotes: ["Mock quote 1", "Mock quote 2"],
        autoTitle: "Auto Mock Title",
        autoDescription: "Auto mock description",
        autoTags: ["auto", "mock", "tags"],
        ownerUsername: "MockUser",
        ownerProfilePicURL: "https://example.com/mock_profile.jpg"
    )
    
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
        case brainCount
        case viewCount
        case ownerUsername
        case ownerProfilePicURL
        case processingStatus
        case transcript
        case extractedQuotes
        case quotes
        case autoTitle
        case autoDescription
        case autoTags
    }
    
    // Initialize from Firestore document
    init?(document: DocumentSnapshot) {
        let data = document.data()
        guard let data = data else {
            LoggingService.error("Failed to initialize - No data in document", component: "Video")
            return nil
        }
        
        LoggingService.debug("🎥 Video: Processing document \(document.documentID)", component: "Video")
        LoggingService.debug("📄 Document data: \(data)", component: "Video")
        
        self.id = document.documentID
        
        // Check each required field individually for better error reporting
        guard let ownerId = data["ownerId"] as? String else {
            LoggingService.error("Missing required field 'ownerId' in document \(document.documentID)", component: "Video")
            return nil
        }
        
        guard let videoURL = data["videoURL"] as? String else {
            LoggingService.error("Missing required field 'videoURL' in document \(document.documentID)", component: "Video")
            return nil
        }
        
        guard let thumbnailURL = data["thumbnailURL"] as? String else {
            LoggingService.error("Missing required field 'thumbnailURL' in document \(document.documentID)", component: "Video")
            return nil
        }
        
        guard let title = data["title"] as? String else {
            LoggingService.error("Missing required field 'title' in document \(document.documentID)", component: "Video")
            return nil
        }
        
        guard let tags = data["tags"] as? [String] else {
            LoggingService.error("Missing required field 'tags' in document \(document.documentID)", component: "Video")
            return nil
        }
        
        guard let description = data["description"] as? String else {
            LoggingService.error("Missing required field 'description' in document \(document.documentID)", component: "Video")
            return nil
        }
        
        guard let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            LoggingService.error("Missing or invalid field 'createdAt' in document \(document.documentID)", component: "Video")
            return nil
        }
        
        guard let ownerUsername = data["ownerUsername"] as? String else {
            LoggingService.error("Missing required field 'ownerUsername' in document \(document.documentID)", component: "Video")
            return nil
        }
        
        guard let processingStatusRaw = data["processingStatus"] as? String,
              let processingStatus = VideoProcessingStatus(rawValue: processingStatusRaw) else {
            LoggingService.error("Missing or invalid field 'processingStatus' in document \(document.documentID)", component: "Video")
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
        self.brainCount = (data["brainCount"] as? Int) ?? 0
        self.viewCount = (data["viewCount"] as? Int) ?? 0
        self.ownerUsername = ownerUsername
        self.ownerProfilePicURL = data["ownerProfilePicURL"] as? String
        self.processingStatus = processingStatus
        self.transcript = data["transcript"] as? String
        
        // Log quote loading
        if let quotes = data["quotes"] as? [String] {
            LoggingService.debug("📝 Video: Found \(quotes.count) quotes", component: "Video")
            LoggingService.debug("   Content: \(quotes)", component: "Video")
            self.quotes = quotes
        } else if let extractedQuotes = data["extractedQuotes"] as? [String] {
            LoggingService.debug("📝 Video: Using \(extractedQuotes.count) legacy quotes", component: "Video")
            LoggingService.debug("   Content: \(extractedQuotes)", component: "Video")
            self.quotes = extractedQuotes
        } else {
            LoggingService.debug("ℹ️ Video: No quotes available yet", component: "Video")
            self.quotes = nil
        }
        
        self.autoTitle = data["autoTitle"] as? String
        self.autoDescription = data["autoDescription"] as? String
        self.autoTags = data["autoTags"] as? [String]
        
        LoggingService.success("Successfully initialized video \(document.documentID)", component: "Video")
        LoggingService.debug("Video details - Status: \(processingStatus.rawValue), URL: \(videoURL)", component: "Video")
    }
    
    // Initialize directly
    init(id: String, ownerId: String, videoURL: String, thumbnailURL: String, 
         title: String, tags: [String], description: String, createdAt: Date,
         likeCount: Int, saveCount: Int, commentCount: Int, brainCount: Int, viewCount: Int,
         processingStatus: VideoProcessingStatus, transcript: String?, extractedQuotes: [String]?,
         quotes: [String]?, autoTitle: String?, autoDescription: String?, autoTags: [String]?,
         ownerUsername: String, ownerProfilePicURL: String? = nil) {
        
        self.id = id
        self.ownerId = ownerId
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.tags = tags
        self.description = description
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.saveCount = saveCount
        self.commentCount = commentCount
        self.brainCount = brainCount
        self.viewCount = viewCount
        self.processingStatus = processingStatus
        self.transcript = transcript
        self.extractedQuotes = extractedQuotes
        self.quotes = quotes
        self.autoTitle = autoTitle
        self.autoDescription = autoDescription
        self.autoTags = autoTags
        self.ownerUsername = ownerUsername
        self.ownerProfilePicURL = ownerProfilePicURL
        
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
            "brainCount": brainCount,
            "viewCount": viewCount,
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
        
        if let quotes = quotes {
            data["quotes"] = quotes
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