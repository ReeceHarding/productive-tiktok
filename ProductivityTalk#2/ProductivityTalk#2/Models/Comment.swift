import Foundation
import FirebaseFirestore

struct Comment: Identifiable, Codable {
    let id: String
    let videoId: String
    let userId: String
    let text: String
    let createdAt: Date
    var likeCount: Int
    
    // Additional metadata for UI
    var userUsername: String
    var userProfilePicURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case videoId
        case userId
        case text
        case createdAt
        case likeCount
        case userUsername
        case userProfilePicURL
    }
    
    // Initialize from Firestore document
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else {
            print("❌ Comment: Failed to initialize - No data in document")
            return nil
        }
        
        self.id = document.documentID
        guard let videoId = data["videoId"] as? String,
              let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let userUsername = data["userUsername"] as? String else {
            print("❌ Comment: Failed to initialize - Missing required fields")
            return nil
        }
        
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.createdAt = createdAt
        self.likeCount = (data["likeCount"] as? Int) ?? 0
        self.userUsername = userUsername
        self.userProfilePicURL = data["userProfilePicURL"] as? String
        
        print("✅ Comment: Successfully initialized comment with ID: \(id)")
    }
    
    // Initialize directly
    init(id: String, videoId: String, userId: String, text: String, 
         userUsername: String, userProfilePicURL: String? = nil) {
        self.id = id
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.createdAt = Date()
        self.likeCount = 0
        self.userUsername = userUsername
        self.userProfilePicURL = userProfilePicURL
        
        print("✅ Comment: Created new comment with ID: \(id)")
    }
    
    // Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "videoId": videoId,
            "userId": userId,
            "text": text,
            "createdAt": Timestamp(date: createdAt),
            "likeCount": likeCount,
            "userUsername": userUsername
        ]
        
        if let userProfilePicURL = userProfilePicURL {
            data["userProfilePicURL"] = userProfilePicURL
        }
        
        print("✅ Comment: Converted comment data to Firestore format")
        return data
    }
} 