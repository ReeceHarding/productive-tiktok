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
        print("🔍 SecondBrain: Processing document \(document.documentID)")
        print("📄 Document data: \(data)")
        
        // Check each required field individually for better error reporting
        guard let userId = data["userId"] as? String else {
            print("❌ SecondBrain: Missing required field 'userId' in document \(document.documentID)")
            return nil
        }
        
        guard let videoId = data["videoId"] as? String else {
            print("❌ SecondBrain: Missing required field 'videoId' in document \(document.documentID)")
            return nil
        }
        
        guard let transcript = data["transcript"] as? String else {
            print("❌ SecondBrain: Missing required field 'transcript' in document \(document.documentID)")
            return nil
        }
        
        guard let quotes = data["quotes"] as? [String] else {
            print("❌ SecondBrain: Missing required field 'quotes' in document \(document.documentID)")
            return nil
        }
        
        guard let savedAtTimestamp = data["savedAt"] as? Timestamp else {
            print("❌ SecondBrain: Missing required field 'savedAt' in document \(document.documentID)")
            return nil
        }
        
        let savedAt = savedAtTimestamp.dateValue()
        
        self.userId = userId
        self.videoId = videoId
        self.transcript = transcript
        self.quotes = quotes
        self.savedAt = savedAt
        self.videoTitle = data["videoTitle"] as? String
        self.videoThumbnailURL = data["videoThumbnailURL"] as? String
        
        print("✅ SecondBrain: Successfully initialized entry with ID: \(id)")
        print("📊 SecondBrain: Document Summary:")
        print("   - User ID: \(userId)")
        print("   - Video ID: \(videoId)")
        print("   - Quotes Count: \(quotes.count)")
        print("   - Has Transcript: \(transcript.isEmpty ? "Empty" : "Yes")")
        print("   - Saved At: \(savedAt)")
        print("   - Video Title: \(self.videoTitle ?? "Not Set")")
        print("   - Thumbnail URL: \(self.videoThumbnailURL ?? "Not Set")")
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