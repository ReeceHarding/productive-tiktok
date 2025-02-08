import Foundation
import FirebaseFirestore

struct Comment: Identifiable, Codable {
    let id: String
    let videoId: String
    let userId: String
    let text: String
    let timestamp: Date
    var userName: String?
    var userProfileImageURL: String?
    var isInSecondBrain: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case videoId
        case userId
        case text
        case timestamp
        case userName
        case userProfileImageURL
        case isInSecondBrain
    }
    
    init(id: String = UUID().uuidString,
         videoId: String,
         userId: String,
         text: String,
         timestamp: Date = Date(),
         userName: String? = nil,
         userProfileImageURL: String? = nil,
         isInSecondBrain: Bool = false) {
        self.id = id
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.userName = userName
        self.userProfileImageURL = userProfileImageURL
        self.isInSecondBrain = isInSecondBrain
    }
    
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        guard let videoId = data["videoId"] as? String,
              let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
            print("❌ Comment: Failed to parse required fields from document")
            return nil
        }
        
        self.id = document.documentID
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.userName = data["userName"] as? String
        self.userProfileImageURL = data["userProfileImageURL"] as? String
        self.isInSecondBrain = data["isInSecondBrain"] as? Bool ?? false
        
        print("✅ Comment: Successfully parsed comment with ID: \(self.id)")
    }
    
    var toFirestore: [String: Any] {
        var data: [String: Any] = [
            "videoId": videoId,
            "userId": userId,
            "text": text,
            "timestamp": Timestamp(date: timestamp),
            "isInSecondBrain": isInSecondBrain
        ]
        
        if let userName = userName {
            data["userName"] = userName
        }
        
        if let userProfileImageURL = userProfileImageURL {
            data["userProfileImageURL"] = userProfileImageURL
        }
        
        return data
    }
} 