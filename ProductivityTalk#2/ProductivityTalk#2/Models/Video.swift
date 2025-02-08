import Foundation
import FirebaseFirestore

enum VideoProcessingStatus: String, Codable {
    case uploading = "uploading"
    case processing = "processing"
    case transcribing = "transcribing"
    case extracting_quotes = "extracting_quotes"
    case ready = "ready"
    case error = "error"
}

struct Video: Identifiable, Codable {
    let id: String
    let ownerId: String
    let videoURL: String
    let thumbnailURL: String
    let title: String
    var tags: [String]
    var description: String
    let createdAt: Date
    var likeCount: Int
    var saveCount: Int
    var commentCount: Int
    var processingStatus: VideoProcessingStatus
    var transcript: String?
    var extractedQuotes: [String]?
    
    // Additional metadata for UI
    var ownerUsername: String
    var ownerProfilePicURL: String?
    
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
    }
    
    // Initialize from Firestore document
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else {
            print("❌ Video: Failed to initialize - No data in document")
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
            print("❌ Video: Failed to initialize - Missing required fields")
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
        
        print("✅ Video: Successfully initialized video with ID: \(id)")
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
        
        print("✅ Video: Created new video with ID: \(id)")
    }
    
    // Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "ownerId": ownerId,
            "videoURL": videoURL,
            "thumbnailURL": thumbnailURL,
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
        
        print("✅ Video: Converted video data to Firestore format")
        return data
    }
} 