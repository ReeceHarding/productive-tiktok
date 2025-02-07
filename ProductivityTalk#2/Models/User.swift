import Foundation
import FirebaseFirestore

struct AppUser: Identifiable, Codable {
    let id: String
    let username: String
    let email: String
    var profilePicURL: String?
    let createdAt: Date
    var bio: String?
    
    // Firestore serialization keys
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case profilePicURL
        case createdAt
        case bio
    }
    
    // Initialize from Firestore document
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else {
            print("❌ AppUser: Failed to initialize - No data in document")
            return nil
        }
        
        self.id = document.documentID
        guard let username = data["username"] as? String,
              let email = data["email"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            print("❌ AppUser: Failed to initialize - Missing required fields")
            return nil
        }
        
        self.username = username
        self.email = email
        self.createdAt = createdAt
        self.profilePicURL = data["profilePicURL"] as? String
        self.bio = data["bio"] as? String
        
        print("✅ AppUser: Successfully initialized user with ID: \(id)")
    }
    
    // Initialize directly
    init(id: String, username: String, email: String, profilePicURL: String? = nil, bio: String? = nil) {
        self.id = id
        self.username = username
        self.email = email
        self.profilePicURL = profilePicURL
        self.createdAt = Date()
        self.bio = bio
        
        print("✅ AppUser: Created new user with ID: \(id)")
    }
    
    // Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "username": username,
            "email": email,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let profilePicURL = profilePicURL {
            data["profilePicURL"] = profilePicURL
        }
        
        if let bio = bio {
            data["bio"] = bio
        }
        
        print("✅ AppUser: Converted user data to Firestore format")
        return data
    }
} 