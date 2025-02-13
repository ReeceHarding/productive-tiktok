import Foundation
import FirebaseFirestore

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable {
    let id: String
    let role: ChatRole
    let content: String
    let timestamp: Date
    let userId: String
    var associatedVideos: [VideoInfo]
    
    struct VideoInfo: Codable {
        let id: String
        let title: String
        let thumbnailURL: String
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case timestamp
        case userId
        case associatedVideos
    }
    
    init(id: String = UUID().uuidString,
         role: ChatRole,
         content: String,
         timestamp: Date = Date(),
         userId: String,
         associatedVideos: [VideoInfo] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.userId = userId
        self.associatedVideos = associatedVideos
    }
    
    // Firestore conversion
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        guard let roleString = data["role"] as? String,
              let role = ChatRole(rawValue: roleString),
              let content = data["content"] as? String,
              let timestamp = data["timestamp"] as? Timestamp,
              let userId = data["userId"] as? String else {
            return nil
        }
        
        self.id = document.documentID
        self.role = role
        self.content = content
        self.timestamp = timestamp.dateValue()
        self.userId = userId
        
        if let videosData = data["associatedVideos"] as? [[String: Any]] {
            self.associatedVideos = videosData.compactMap { videoData in
                guard let id = videoData["id"] as? String,
                      let title = videoData["title"] as? String,
                      let thumbnailURL = videoData["thumbnailURL"] as? String else {
                    return nil
                }
                return VideoInfo(id: id, title: title, thumbnailURL: thumbnailURL)
            }
        } else {
            self.associatedVideos = []
        }
    }
    
    var asDictionary: [String: Any] {
        [
            "role": role.rawValue,
            "content": content,
            "timestamp": Timestamp(date: timestamp),
            "userId": userId,
            "associatedVideos": associatedVideos.map { video in
                [
                    "id": video.id,
                    "title": video.title,
                    "thumbnailURL": video.thumbnailURL
                ]
            }
        ]
    }
} 