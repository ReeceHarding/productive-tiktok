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
        guard document.exists else {
            LoggingService.error("Failed to initialize - Document does not exist", component: "Video")
            return nil
        }
        
        guard let data = document.data() else {
            LoggingService.error("Failed to initialize - No data in document: \(document.documentID)", component: "Video")
            return nil
        }
        
        LoggingService.debug("🎥 Video: Processing document \(document.documentID)", component: "Video")
        LoggingService.debug("📄 Document data: \(data)", component: "Video")
        
        // Add detailed field logging with validation
        LoggingService.debug("🔍 Validating required fields:", component: "Video")
        LoggingService.debug("  • processingStatus: \(data["processingStatus"] as? String ?? "❌ MISSING")", component: "Video")
        LoggingService.debug("  • ownerId: \(data["ownerId"] as? String ?? "❌ MISSING")", component: "Video")
        LoggingService.debug("  • ownerUsername: \(data["ownerUsername"] as? String ?? "❌ MISSING")", component: "Video")
        
        LoggingService.debug("🔍 Validating optional fields:", component: "Video")
        LoggingService.debug("  • videoURL: \(data["videoURL"] as? String ?? "⚠️ Not set")", component: "Video")
        LoggingService.debug("  • thumbnailURL: \(data["thumbnailURL"] as? String ?? "⚠️ Not set")", component: "Video")
        LoggingService.debug("  • title: \(data["title"] as? String ?? "⚠️ Not set")", component: "Video")
        LoggingService.debug("  • tags: \(data["tags"] as? [String] ?? [])", component: "Video")
        LoggingService.debug("  • description: \(data["description"] as? String ?? "⚠️ Not set")", component: "Video")
        LoggingService.debug("  • createdAt: \((data["createdAt"] as? Timestamp)?.dateValue().description ?? "⚠️ Not set")", component: "Video")
        
        self.id = document.documentID
        
        // First check processing status as it affects required fields
        guard let processingStatusRaw = data["processingStatus"] as? String,
              let processingStatus = VideoProcessingStatus(rawValue: processingStatusRaw) else {
            LoggingService.error("❌ Failed to initialize - Missing or invalid processing status for document: \(document.documentID)", component: "Video")
            LoggingService.error("  • Raw status value: \(data["processingStatus"] ?? "nil")", component: "Video")
            return nil
        }
        
        self.processingStatus = processingStatus
        
        // Handle owner information with graceful fallback
        if let ownerId = data["ownerId"] as? String {
            self.ownerId = ownerId
            LoggingService.debug("✅ Found ownerId: \(ownerId)", component: "Video")
        } else {
            LoggingService.warning("⚠️ Missing ownerId for video: \(document.documentID)", component: "Video")
            LoggingService.warning("  • Processing status: \(processingStatus.rawValue)", component: "Video")
            // Use document ID as fallback ownerId to maintain functionality
            self.ownerId = document.documentID
        }
        
        if let ownerUsername = data["ownerUsername"] as? String {
            self.ownerUsername = ownerUsername
            LoggingService.debug("✅ Found ownerUsername: \(ownerUsername)", component: "Video")
        } else {
            LoggingService.warning("⚠️ Missing ownerUsername for video: \(document.documentID)", component: "Video")
            LoggingService.warning("  • Processing status: \(processingStatus.rawValue)", component: "Video")
            // Use a descriptive placeholder that indicates this is auto-generated
            self.ownerUsername = "User_\(String(document.documentID.prefix(8)))"
        }
        
        // Handle fields that might not be available during processing
        self.videoURL = data["videoURL"] as? String ?? ""
        if self.videoURL.isEmpty && processingStatus == .ready {
            LoggingService.warning("⚠️ Video marked as ready but has no URL: \(document.documentID)", component: "Video")
        }
        
        self.thumbnailURL = data["thumbnailURL"] as? String
        self.title = data["title"] as? String ?? "Processing..."
        self.tags = data["tags"] as? [String] ?? []
        self.description = data["description"] as? String ?? "Processing..."
        
        // Validate and set createdAt with detailed logging
        if let timestamp = data["createdAt"] as? Timestamp {
            self.createdAt = timestamp.dateValue()
            LoggingService.debug("📅 Created at: \(timestamp.dateValue())", component: "Video")
        } else {
            LoggingService.warning("⚠️ No creation timestamp for \(document.documentID), using current date", component: "Video")
            self.createdAt = Date()
        }
        
        // Optional counts with defaults and validation
        self.likeCount = (data["likeCount"] as? Int) ?? 0
        self.saveCount = (data["saveCount"] as? Int) ?? 0
        self.commentCount = (data["commentCount"] as? Int) ?? 0
        self.brainCount = (data["brainCount"] as? Int) ?? 0
        self.viewCount = (data["viewCount"] as? Int) ?? 0
        
        // Validate non-negative counts
        if self.likeCount < 0 || self.saveCount < 0 || self.commentCount < 0 || 
           self.brainCount < 0 || self.viewCount < 0 {
            LoggingService.warning("⚠️ Negative count detected for video \(document.documentID):", component: "Video")
            LoggingService.warning("  • Likes: \(self.likeCount)", component: "Video")
            LoggingService.warning("  • Saves: \(self.saveCount)", component: "Video")
            LoggingService.warning("  • Comments: \(self.commentCount)", component: "Video")
            LoggingService.warning("  • Brains: \(self.brainCount)", component: "Video")
            LoggingService.warning("  • Views: \(self.viewCount)", component: "Video")
        }
        
        // Optional metadata
        self.ownerProfilePicURL = data["ownerProfilePicURL"] as? String
        self.transcript = data["transcript"] as? String
        
        // Handle quotes with validation
        if let quotes = data["quotes"] as? [String] {
            LoggingService.debug("📝 Video: Found \(quotes.count) quotes", component: "Video")
            self.quotes = quotes
        } else if let extractedQuotes = data["extractedQuotes"] as? [String] {
            LoggingService.debug("📝 Video: Using \(extractedQuotes.count) legacy quotes", component: "Video")
            self.quotes = extractedQuotes
            LoggingService.warning("⚠️ Using legacy 'extractedQuotes' field for \(document.documentID)", component: "Video")
        } else {
            LoggingService.debug("ℹ️ Video: No quotes available yet", component: "Video")
            self.quotes = nil
        }
        
        self.autoTitle = data["autoTitle"] as? String
        self.autoDescription = data["autoDescription"] as? String
        self.autoTags = data["autoTags"] as? [String]
        
        // Log successful initialization with key metadata
        LoggingService.success("✅ Successfully initialized video:", component: "Video")
        LoggingService.success("  • ID: \(id)", component: "Video")
        LoggingService.success("  • Owner: \(ownerUsername) (\(ownerId))", component: "Video")
        LoggingService.success("  • Status: \(processingStatus.rawValue)", component: "Video")
        LoggingService.success("  • Has URL: \(!videoURL.isEmpty)", component: "Video")
        LoggingService.success("  • Has Thumbnail: \(thumbnailURL != nil)", component: "Video")
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
        self.brainCount = 0
        self.viewCount = 0
        self.ownerUsername = ownerUsername
        self.ownerProfilePicURL = ownerProfilePicURL
        self.processingStatus = .uploading
        self.transcript = nil
        self.extractedQuotes = nil
        self.quotes = nil
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