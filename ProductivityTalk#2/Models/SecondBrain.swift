import Foundation
import FirebaseFirestore

public struct SecondBrain: Identifiable, Codable {
    public let id: String
    public let userId: String
    public let videoId: String
    public let transcript: String
    public var quotes: [String]
    public let savedAt: Date
    
    // Additional metadata for UI
    public var videoTitle: String?
    public var videoThumbnailURL: String?
    
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
            LoggingService.error("❌ SecondBrain: Failed to initialize - No data in document", component: "SecondBrain")
            return nil
        }
        
        self.id = document.documentID
        LoggingService.debug("🔍 SecondBrain: Processing document \(document.documentID)", component: "SecondBrain")
        LoggingService.debug("📄 Document data: \(data)", component: "SecondBrain")
        
        // Check each required field individually for better error reporting
        guard let userId = data["userId"] as? String else {
            LoggingService.error("❌ SecondBrain: Missing required field 'userId' in document \(document.documentID)", component: "SecondBrain")
            return nil
        }
        
        guard let videoId = data["videoId"] as? String else {
            LoggingService.error("❌ SecondBrain: Missing required field 'videoId' in document \(document.documentID)", component: "SecondBrain")
            return nil
        }
        
        guard let transcript = data["transcript"] as? String else {
            LoggingService.error("❌ SecondBrain: Missing required field 'transcript' in document \(document.documentID)", component: "SecondBrain")
            return nil
        }
        
        // Try to get quotes from either field
        var fetchedQuotes: [String]? = data["quotes"] as? [String]
        if let quotes = fetchedQuotes, !quotes.isEmpty {
            LoggingService.debug("📝 SecondBrain: Found quotes in 'quotes' field for document \(document.documentID): \(quotes)", component: "SecondBrain")
        } else if let extractedQuotes = data["extractedQuotes"] as? [String], !extractedQuotes.isEmpty {
            LoggingService.debug("📝 SecondBrain: Found quotes in 'extractedQuotes' field for document \(document.documentID): \(extractedQuotes)", component: "SecondBrain")
            fetchedQuotes = extractedQuotes
        } else {
            LoggingService.warning("⚠️ SecondBrain: No quotes found in document \(document.documentID)", component: "SecondBrain")
            fetchedQuotes = []
        }
        
        guard let savedAtTimestamp = data["savedAt"] as? Timestamp else {
            LoggingService.error("❌ SecondBrain: Missing required field 'savedAt' in document \(document.documentID)", component: "SecondBrain")
            return nil
        }
        
        let savedAt = savedAtTimestamp.dateValue()
        
        self.userId = userId
        self.videoId = videoId
        self.transcript = transcript
        self.quotes = fetchedQuotes ?? []
        self.savedAt = savedAt
        self.videoTitle = data["videoTitle"] as? String
        self.videoThumbnailURL = data["videoThumbnailURL"] as? String
        
        LoggingService.success("✅ SecondBrain: Successfully initialized entry with ID: \(id)", component: "SecondBrain")
        LoggingService.debug("📊 SecondBrain: Document Summary:", component: "SecondBrain")
        LoggingService.debug("   - User ID: \(userId)", component: "SecondBrain")
        LoggingService.debug("   - Video ID: \(videoId)", component: "SecondBrain")
        LoggingService.debug("   - Quotes Count: \(self.quotes.count)", component: "SecondBrain")
        LoggingService.debug("   - Has Transcript: \(transcript.isEmpty ? "Empty" : "Yes")", component: "SecondBrain")
        LoggingService.debug("   - Saved At: \(savedAt)", component: "SecondBrain")
        LoggingService.debug("   - Video Title: \(self.videoTitle ?? "Not Set")", component: "SecondBrain")
        LoggingService.debug("   - Thumbnail URL: \(self.videoThumbnailURL ?? "Not Set")", component: "SecondBrain")
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
        
        LoggingService.success("✅ SecondBrain: Created new entry with ID: \(id)", component: "SecondBrain")
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
        
        LoggingService.success("✅ SecondBrain: Converted entry data to Firestore format", component: "SecondBrain")
        return data
    }
    
    // Add a new quote
    mutating func addQuote(_ quote: String) {
        quotes.append(quote)
        LoggingService.success("✅ SecondBrain: Added new quote to entry \(id)", component: "SecondBrain")
    }
    
    // Remove a quote
    mutating func removeQuote(_ quote: String) {
        quotes.removeAll { $0 == quote }
        LoggingService.success("✅ SecondBrain: Removed quote from entry \(id)", component: "SecondBrain")
    }
} 