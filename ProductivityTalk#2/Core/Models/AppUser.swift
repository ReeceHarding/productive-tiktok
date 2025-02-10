import Foundation
import FirebaseFirestore

struct AppUser: Codable, Identifiable {
    let id: String
    var username: String
    var email: String
    var profilePicURL: String?
    let createdAt: Date
    var bio: String?
    
    // Video Engagement Statistics
    var totalVideosUploaded: Int
    var totalVideoViews: Int
    var totalVideoLikes: Int
    var totalVideoShares: Int
    var totalVideoSaves: Int
    
    // Comment Engagement Statistics
    var totalCommentsPosted: Int
    var totalCommentSecondBrains: Int
    var commentsReceivedSecondBrains: Int
    
    // Second Brain Statistics
    var totalSecondBrainSaves: Int
    var totalQuotesSaved: Int
    var totalTranscriptsSaved: Int
    
    // Derived Statistics
    var videoEngagementRate: Double
    var commentEngagementRate: Double
    var secondBrainEngagementRate: Double
    
    // Growth Statistics
    var weeklySecondBrainGrowth: Double
    var monthlySecondBrainGrowth: Double
    var yearlySecondBrainGrowth: Double
    
    // Achievement Statistics
    var totalAchievementsUnlocked: Int
    var currentStreak: Int
    var longestStreak: Int
    var lastActiveDate: Date
    
    // Ranking Statistics
    var globalRank: Int
    var weeklyRank: Int
    var monthlyRank: Int
    var rankLastUpdated: Date
    
    // Topic Distribution
    var topicDistribution: [String: Int]
    
    // Firestore serialization keys
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case profilePicURL
        case createdAt
        case bio
        
        // Video Engagement
        case totalVideosUploaded
        case totalVideoViews
        case totalVideoLikes
        case totalVideoShares
        case totalVideoSaves
        
        // Comment Engagement
        case totalCommentsPosted
        case totalCommentSecondBrains
        case commentsReceivedSecondBrains
        
        // Second Brain
        case totalSecondBrainSaves
        case totalQuotesSaved
        case totalTranscriptsSaved
        
        // Derived Statistics
        case videoEngagementRate
        case commentEngagementRate
        case secondBrainEngagementRate
        
        // Growth
        case weeklySecondBrainGrowth
        case monthlySecondBrainGrowth
        case yearlySecondBrainGrowth
        
        // Achievements
        case totalAchievementsUnlocked
        case currentStreak
        case longestStreak
        case lastActiveDate
        
        // Rankings
        case globalRank
        case weeklyRank
        case monthlyRank
        case rankLastUpdated
        
        // Topics
        case topicDistribution
    }
    
    // Initialize from Firestore document
    init?(document: DocumentSnapshot) {
        guard document.exists else {
            LoggingService.error("❌ AppUser: Failed to initialize - Document does not exist for ID: \(document.documentID)", component: "AppUser")
            return nil
        }
        
        guard let data = document.data() else {
            LoggingService.error("❌ AppUser: Failed to initialize - No data in document for ID: \(document.documentID)", component: "AppUser")
            return nil
        }
        
        self.id = document.documentID
        guard let username = data["username"] as? String,
              let email = data["email"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            LoggingService.error("❌ AppUser: Failed to initialize - Missing required fields for ID: \(document.documentID)", component: "AppUser")
            if let username = data["username"] {
                LoggingService.error("Username type: \(type(of: username))", component: "AppUser")
            }
            if let email = data["email"] {
                LoggingService.error("Email type: \(type(of: email))", component: "AppUser")
            }
            if let createdAt = data["createdAt"] {
                LoggingService.error("CreatedAt type: \(type(of: createdAt))", component: "AppUser")
            }
            return nil
        }
        
        // Basic Info
        self.username = username
        self.email = email
        self.createdAt = createdAt
        self.profilePicURL = data["profilePicURL"] as? String
        self.bio = data["bio"] as? String
        
        // Video Engagement
        self.totalVideosUploaded = (data["totalVideosUploaded"] as? Int) ?? 0
        self.totalVideoViews = (data["totalVideoViews"] as? Int) ?? 0
        self.totalVideoLikes = (data["totalVideoLikes"] as? Int) ?? 0
        self.totalVideoShares = (data["totalVideoShares"] as? Int) ?? 0
        self.totalVideoSaves = (data["totalVideoSaves"] as? Int) ?? 0
        
        // Comment Engagement
        self.totalCommentsPosted = (data["totalCommentsPosted"] as? Int) ?? 0
        self.totalCommentSecondBrains = (data["totalCommentSecondBrains"] as? Int) ?? 0
        self.commentsReceivedSecondBrains = (data["commentsReceivedSecondBrains"] as? Int) ?? 0
        
        // Second Brain
        self.totalSecondBrainSaves = (data["totalSecondBrainSaves"] as? Int) ?? 0
        self.totalQuotesSaved = (data["totalQuotesSaved"] as? Int) ?? 0
        self.totalTranscriptsSaved = (data["totalTranscriptsSaved"] as? Int) ?? 0
        
        // Derived Statistics
        self.videoEngagementRate = (data["videoEngagementRate"] as? Double) ?? 0.0
        self.commentEngagementRate = (data["commentEngagementRate"] as? Double) ?? 0.0
        self.secondBrainEngagementRate = (data["secondBrainEngagementRate"] as? Double) ?? 0.0
        
        // Growth
        self.weeklySecondBrainGrowth = (data["weeklySecondBrainGrowth"] as? Double) ?? 0.0
        self.monthlySecondBrainGrowth = (data["monthlySecondBrainGrowth"] as? Double) ?? 0.0
        self.yearlySecondBrainGrowth = (data["yearlySecondBrainGrowth"] as? Double) ?? 0.0
        
        // Achievements
        self.totalAchievementsUnlocked = (data["totalAchievementsUnlocked"] as? Int) ?? 0
        self.currentStreak = (data["currentStreak"] as? Int) ?? 0
        self.longestStreak = (data["longestStreak"] as? Int) ?? 0
        self.lastActiveDate = (data["lastActiveDate"] as? Timestamp)?.dateValue() ?? createdAt
        
        // Rankings
        self.globalRank = (data["globalRank"] as? Int) ?? 0
        self.weeklyRank = (data["weeklyRank"] as? Int) ?? 0
        self.monthlyRank = (data["monthlyRank"] as? Int) ?? 0
        self.rankLastUpdated = (data["rankLastUpdated"] as? Timestamp)?.dateValue() ?? createdAt
        
        // Topic Distribution
        self.topicDistribution = (data["topicDistribution"] as? [String: Int]) ?? [:]
        
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
        
        // Initialize all statistics with default values
        self.totalVideosUploaded = 0
        self.totalVideoViews = 0
        self.totalVideoLikes = 0
        self.totalVideoShares = 0
        self.totalVideoSaves = 0
        
        self.totalCommentsPosted = 0
        self.totalCommentSecondBrains = 0
        self.commentsReceivedSecondBrains = 0
        
        self.totalSecondBrainSaves = 0
        self.totalQuotesSaved = 0
        self.totalTranscriptsSaved = 0
        
        self.videoEngagementRate = 0.0
        self.commentEngagementRate = 0.0
        self.secondBrainEngagementRate = 0.0
        
        self.weeklySecondBrainGrowth = 0.0
        self.monthlySecondBrainGrowth = 0.0
        self.yearlySecondBrainGrowth = 0.0
        
        self.totalAchievementsUnlocked = 0
        self.currentStreak = 0
        self.longestStreak = 0
        self.lastActiveDate = Date()
        
        self.globalRank = 0
        self.weeklyRank = 0
        self.monthlyRank = 0
        self.rankLastUpdated = Date()
        
        self.topicDistribution = [:]
        
        print("✅ AppUser: Created new user with ID: \(id)")
    }
    
    // Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "username": username,
            "email": email,
            "createdAt": Timestamp(date: createdAt),
            
            // Video Engagement
            "totalVideosUploaded": totalVideosUploaded,
            "totalVideoViews": totalVideoViews,
            "totalVideoLikes": totalVideoLikes,
            "totalVideoShares": totalVideoShares,
            "totalVideoSaves": totalVideoSaves,
            
            // Comment Engagement
            "totalCommentsPosted": totalCommentsPosted,
            "totalCommentSecondBrains": totalCommentSecondBrains,
            "commentsReceivedSecondBrains": commentsReceivedSecondBrains,
            
            // Second Brain
            "totalSecondBrainSaves": totalSecondBrainSaves,
            "totalQuotesSaved": totalQuotesSaved,
            "totalTranscriptsSaved": totalTranscriptsSaved,
            
            // Derived Statistics
            "videoEngagementRate": videoEngagementRate,
            "commentEngagementRate": commentEngagementRate,
            "secondBrainEngagementRate": secondBrainEngagementRate,
            
            // Growth
            "weeklySecondBrainGrowth": weeklySecondBrainGrowth,
            "monthlySecondBrainGrowth": monthlySecondBrainGrowth,
            "yearlySecondBrainGrowth": yearlySecondBrainGrowth,
            
            // Achievements
            "totalAchievementsUnlocked": totalAchievementsUnlocked,
            "currentStreak": currentStreak,
            "longestStreak": longestStreak,
            "lastActiveDate": Timestamp(date: lastActiveDate),
            
            // Rankings
            "globalRank": globalRank,
            "weeklyRank": weeklyRank,
            "monthlyRank": monthlyRank,
            "rankLastUpdated": Timestamp(date: rankLastUpdated),
            
            // Topics
            "topicDistribution": topicDistribution
        ]
        
        if let bio = bio {
            data["bio"] = bio
        }
        
        if let profilePicURL = profilePicURL {
            data["profilePicURL"] = profilePicURL
        }
        
        print("✅ AppUser: Converted user data to Firestore format")
        return data
    }
} 