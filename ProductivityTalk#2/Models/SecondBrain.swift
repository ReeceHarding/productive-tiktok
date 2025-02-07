import Foundation
import FirebaseFirestore

struct SecondBrain: Identifiable, Codable {
    let id: String
    let userId: String
    let videoId: String
    let transcript: String
    var quotes: [String]
    let savedAt: Date
    
    // Additional metadata for UI
    var videoTitle: String?
    var videoThumbnailURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case videoId
        case transcript
        case quotes
        case savedAt
        case videoTitle
        case videoThumbnailURL
    }
    
    // Initialize from Firestore document
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else {
            print("❌ SecondBrain: Failed to initialize - No data in document")
            return nil
        }
        
        self.id = document.documentID
        guard let userId = data["userId"] as? String,
              let videoId = data["videoId"] as? String,
              let transcript = data["transcript"] as? String,
              let quotes = data["quotes"] as? [String],
              let savedAt = (data["savedAt"] as? Timestamp)?.dateValue() else {
            print("❌ SecondBrain: Failed to initialize - Missing required fields")
            return nil
        }
        
        self.userId = userId
        self.videoId = videoId
        self.transcript = transcript
        self.quotes = quotes
        self.savedAt = savedAt
        self.videoTitle = data["videoTitle"] as? String
        self.videoThumbnailURL = data["videoThumbnailURL"] as? String
        
        print("✅ SecondBrain: Successfully initialized entry with ID: \(id)")
    }
    
    // Initialize directly
    init(id: String, userId: String, videoId: String, transcript: String, quotes: [String],
         videoTitle: String? = nil, videoThumbnailURL: String? = nil) {
        self.id = id
        self.userId = userId
        self.videoId = videoId
        self.transcript = transcript
        self.quotes = quotes
        self.savedAt = Date()
        self.videoTitle = videoTitle
        self.videoThumbnailURL = videoThumbnailURL
        
        print("✅ SecondBrain: Created new entry with ID: \(id)")
    }
    
    // Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "userId": userId,
            "videoId": videoId,
            "transcript": transcript,
            "quotes": quotes,
            "savedAt": Timestamp(date: savedAt)
        ]
        
        if let videoTitle = videoTitle {
            data["videoTitle"] = videoTitle
        }
        
        if let videoThumbnailURL = videoThumbnailURL {
            data["videoThumbnailURL"] = videoThumbnailURL
        }
        
        print("✅ SecondBrain: Converted entry data to Firestore format")
        return data
    }
    
    // Add a new quote
    mutating func addQuote(_ quote: String) {
        quotes.append(quote)
        print("✅ SecondBrain: Added new quote to entry \(id)")
    }
    
    // Remove a quote
    mutating func removeQuote(_ quote: String) {
        quotes.removeAll { $0 == quote }
        print("✅ SecondBrain: Removed quote from entry \(id)")
    }
} 