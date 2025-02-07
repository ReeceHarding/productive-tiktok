import Foundation
import FirebaseFirestore

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
        case ownerUsername
        case ownerProfilePicURL
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
              let ownerUsername = data["ownerUsername"] as? String else {
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
        self.ownerUsername = ownerUsername
        self.ownerProfilePicURL = data["ownerProfilePicURL"] as? String
        
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
        self.ownerUsername = ownerUsername
        self.ownerProfilePicURL = ownerProfilePicURL
        
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
            "ownerUsername": ownerUsername
        ]
        
        if let ownerProfilePicURL = ownerProfilePicURL {
            data["ownerProfilePicURL"] = ownerProfilePicURL
        }
        
        print("✅ Video: Converted video data to Firestore format")
        return data
    }
} 