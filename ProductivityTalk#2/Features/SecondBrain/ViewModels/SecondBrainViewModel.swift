import Foundation
import FirebaseFirestore
import Combine

@MainActor
class SecondBrainViewModel: ObservableObject {
    @Published private(set) var user: AppUser?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("🧠 SecondBrainViewModel: Initializing")
    }
    
    func loadUserData() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            print("❌ SecondBrainViewModel: No user ID found")
            self.error = "Please sign in to view your Second Brain"
            return
        }
        
        isLoading = true
        print("\n📥 SecondBrainViewModel: Starting user data load")
        print("👤 User ID: \(userId)")
        
        do {
            print("🔍 Querying Firestore: users/\(userId)")
            let document = try await db.collection("users").document(userId).getDocument()
            
            print("\n📄 Document Data Retrieved:")
            if let data = document.data() {
                print("   - Document exists")
                print("   - Fields found: \(data.keys.joined(separator: ", "))")
                
                // Print specific statistics
                print("\n📊 Second Brain Statistics:")
                print("   - Total Second Brain Saves: \(data["totalSecondBrainSaves"] as? Int ?? 0)")
                print("   - Total Quotes Saved: \(data["totalQuotesSaved"] as? Int ?? 0)")
                print("   - Total Transcripts Saved: \(data["totalTranscriptsSaved"] as? Int ?? 0)")
                print("\n📈 Growth Rates:")
                print("   - Weekly Growth: \(String(format: "%.1f%%", (data["weeklySecondBrainGrowth"] as? Double ?? 0) * 100))")
                print("   - Monthly Growth: \(String(format: "%.1f%%", (data["monthlySecondBrainGrowth"] as? Double ?? 0) * 100))")
                print("   - Yearly Growth: \(String(format: "%.1f%%", (data["yearlySecondBrainGrowth"] as? Double ?? 0) * 100))")
                print("\n🎯 Engagement:")
                print("   - Video Engagement Rate: \(String(format: "%.1f%%", (data["videoEngagementRate"] as? Double ?? 0) * 100))")
                print("   - Comment Engagement Rate: \(String(format: "%.1f%%", (data["commentEngagementRate"] as? Double ?? 0) * 100))")
                print("   - Second Brain Engagement Rate: \(String(format: "%.1f%%", (data["secondBrainEngagementRate"] as? Double ?? 0) * 100))")
                
                if let user = AppUser(document: document) {
                    self.user = user
                    print("\n✅ SecondBrainViewModel: Successfully parsed user data")
                    print("   - Username: \(user.username)")
                    print("   - Total Videos: \(user.totalVideosUploaded)")
                    print("   - Total Views: \(user.totalVideoViews)")
                    print("   - Current Streak: \(user.currentStreak)")
                    print("   - Longest Streak: \(user.longestStreak)")
                } else {
                    print("\n❌ SecondBrainViewModel: Failed to parse user data")
                    print("   - Document exists but could not be parsed into AppUser")
                    self.error = "Failed to parse user data"
                }
            } else {
                print("\n❌ SecondBrainViewModel: Document does not exist")
                self.error = "User document not found"
            }
        } catch {
            print("\n❌ SecondBrainViewModel: Error loading user data")
            print("   - Error: \(error.localizedDescription)")
            print("   - Collection path: users/\(userId)")
            self.error = "Failed to load user data: \(error.localizedDescription)"
        }
        
        isLoading = false
        print("\n🏁 SecondBrainViewModel: Finished loading user data")
    }
    
    func updateStatistics() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            print("❌ SecondBrainViewModel: No user ID found")
            return
        }
        
        print("📊 SecondBrainViewModel: Starting statistics update for user: \(userId)")
        
        do {
            // Get all user's videos
            let videosSnapshot = try await db.collection("videos")
                .whereField("ownerId", isEqualTo: userId)
                .getDocuments()
            
            // Get all user's comments
            let commentsSnapshot = try await db.collection("comments")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            // Get comments received on user's videos
            let videoIds = videosSnapshot.documents.map { $0.documentID }
            let receivedCommentsSnapshot = try await db.collection("comments")
                .whereField("videoId", in: videoIds)
                .getDocuments()
                
            // Get Second Brain entries
            let secondBrainSnapshot = try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .getDocuments()
            
            // Calculate video statistics
            let totalVideos = videosSnapshot.documents.count
            let totalViews = videosSnapshot.documents.reduce(0) { $0 + (($1.data()["viewCount"] as? Int) ?? 0) }
            let totalLikes = videosSnapshot.documents.reduce(0) { $0 + (($1.data()["likeCount"] as? Int) ?? 0) }
            let totalShares = videosSnapshot.documents.reduce(0) { $0 + (($1.data()["shareCount"] as? Int) ?? 0) }
            let totalSaves = videosSnapshot.documents.reduce(0) { $0 + (($1.data()["saveCount"] as? Int) ?? 0) }
            
            // Calculate comment statistics
            let totalComments = commentsSnapshot.documents.count
            let totalSecondBrains = commentsSnapshot.documents.reduce(0) { $0 + (($1.data()["secondBrainCount"] as? Int) ?? 0) }
            let receivedSecondBrains = receivedCommentsSnapshot.documents.reduce(0) { $0 + (($1.data()["secondBrainCount"] as? Int) ?? 0) }
            
            // Calculate Second Brain statistics
            var totalQuotes = 0
            var totalTranscripts = 0
            for doc in secondBrainSnapshot.documents {
                if let quotes = doc.data()["quotes"] as? [String] {
                    totalQuotes += quotes.count
                }
                if doc.data()["transcript"] as? String != nil {
                    totalTranscripts += 1
                }
            }
            
            // Calculate engagement rates
            let videoEngagementRate = totalVideos > 0 ? Double(totalLikes + totalShares + totalSaves) / Double(totalViews) : 0.0
            let commentEngagementRate = totalComments > 0 ? Double(totalSecondBrains) / Double(totalComments) : 0.0
            let secondBrainEngagementRate = secondBrainSnapshot.documents.count > 0 ? Double(totalQuotes + totalTranscripts) / Double(secondBrainSnapshot.documents.count) : 0.0
            
            // Update user document
            let userRef = db.collection("users").document(userId)
            let updateData: [String: Sendable] = [
                // Video statistics
                "totalVideosUploaded": totalVideos,
                "totalVideoViews": totalViews,
                "totalVideoLikes": totalLikes,
                "totalVideoShares": totalShares,
                "totalVideoSaves": totalSaves,
                
                // Comment statistics
                "totalCommentsPosted": totalComments,
                "totalCommentSecondBrains": totalSecondBrains,
                "commentsReceivedSecondBrains": receivedSecondBrains,
                
                // Second Brain statistics
                "totalSecondBrainSaves": secondBrainSnapshot.documents.count,
                "totalQuotesSaved": totalQuotes,
                "totalTranscriptsSaved": totalTranscripts,
                
                // Engagement rates
                "videoEngagementRate": videoEngagementRate,
                "commentEngagementRate": commentEngagementRate,
                "secondBrainEngagementRate": secondBrainEngagementRate,
                
                "lastActiveDate": Timestamp(date: Date())
            ]
            
            try await userRef.setData(updateData, merge: true)
            print("✅ SecondBrainViewModel: Successfully updated user statistics")
            print("📊 Statistics Summary:")
            print("   - Total Second Brain Saves: \(secondBrainSnapshot.documents.count)")
            print("   - Total Quotes Saved: \(totalQuotes)")
            print("   - Total Transcripts Saved: \(totalTranscripts)")
            print("   - Second Brain Engagement Rate: \(secondBrainEngagementRate)")
            
            // Reload user data to reflect changes
            await loadUserData()
            
        } catch {
            print("❌ SecondBrainViewModel: Error updating statistics: \(error.localizedDescription)")
            self.error = "Failed to update statistics: \(error.localizedDescription)"
        }
    }
    
    func calculateGrowthRates() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        
        print("📈 SecondBrainViewModel: Calculating growth rates for user: \(userId)")
        
        let now = Date()
        let calendar = Calendar.current
        
        // Define time periods
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
        
        do {
            // Get historical data
            let weeklySnapshot = try await db.collection("userStats")
                .document(userId)
                .collection("history")
                .whereField("date", isGreaterThan: weekAgo)
                .order(by: "date", descending: false)
                .getDocuments()
            
            let monthlySnapshot = try await db.collection("userStats")
                .document(userId)
                .collection("history")
                .whereField("date", isGreaterThan: monthAgo)
                .order(by: "date", descending: false)
                .getDocuments()
            
            let yearlySnapshot = try await db.collection("userStats")
                .document(userId)
                .collection("history")
                .whereField("date", isGreaterThan: yearAgo)
                .order(by: "date", descending: false)
                .getDocuments()
            
            // Calculate growth rates
            let weeklyGrowth = calculateGrowthRate(from: weeklySnapshot.documents)
            let monthlyGrowth = calculateGrowthRate(from: monthlySnapshot.documents)
            let yearlyGrowth = calculateGrowthRate(from: yearlySnapshot.documents)
            
            // Update user document
            let userRef = db.collection("users").document(userId)
            @Sendable func updateGrowthRates() async throws {
                try await userRef.updateData([
                    "weeklySecondBrainGrowth": weeklyGrowth,
                    "monthlySecondBrainGrowth": monthlyGrowth,
                    "yearlySecondBrainGrowth": yearlyGrowth
                ] as [String: Any])
            }
            try await updateGrowthRates()
            
            print("✅ SecondBrainViewModel: Successfully updated growth rates")
            
            // Reload user data to reflect changes
            await loadUserData()
            
        } catch {
            print("❌ SecondBrainViewModel: Error calculating growth rates: \(error.localizedDescription)")
            self.error = "Failed to calculate growth rates: \(error.localizedDescription)"
        }
    }
    
    private func calculateGrowthRate(from documents: [QueryDocumentSnapshot]) -> Double {
        guard documents.count >= 2 else { return 0.0 }
        
        let firstValue = documents.first?.data()["totalSecondBrainSaves"] as? Int ?? 0
        let lastValue = documents.last?.data()["totalSecondBrainSaves"] as? Int ?? 0
        
        guard firstValue > 0 else { return 0.0 }
        
        return Double(lastValue - firstValue) / Double(firstValue)
    }
    
    func updateTopicDistribution() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            print("❌ SecondBrainViewModel: No user ID found for topic distribution update")
            return
        }
        
        print("\n🏷️ SecondBrainViewModel: Starting topic distribution update")
        print("👤 User ID: \(userId)")
        
        do {
            // Get all saved videos
            print("📚 SecondBrainViewModel: Fetching saved videos from path: savedVideos")
            let savedVideosSnapshot = try await db.collection("savedVideos")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            print("📊 Found \(savedVideosSnapshot.documents.count) saved videos")
            
            // Get video details for saved videos
            var topicCounts: [String: Int] = [:]
            var processedVideos = 0
            var videosWithTags = 0
            var totalTags = 0
            
            for savedVideo in savedVideosSnapshot.documents {
                if let videoId = savedVideo.data()["videoId"] as? String {
                    print("\n🎥 Processing video: \(videoId)")
                    let videoDoc = try await db.collection("videos").document(videoId).getDocument()
                    
                    print("📄 Video document exists: \(videoDoc.exists)")
                    if let data = videoDoc.data() {
                        print("📄 Video data fields: \(data.keys.joined(separator: ", "))")
                    }
                    
                    if let tags = videoDoc.data()?["tags"] as? [String] {
                        print("✅ Found tags: \(tags)")
                        videosWithTags += 1
                        totalTags += tags.count
                        for tag in tags {
                            topicCounts[tag, default: 0] += 1
                        }
                    } else {
                        print("⚠️ No tags found for video: \(videoId)")
                        if let autoTags = videoDoc.data()?["autoTags"] as? [String] {
                            print("🤖 Found autoTags instead: \(autoTags)")
                        }
                    }
                    processedVideos += 1
                }
            }
            
            print("\n📈 Topic Distribution Summary:")
            print("📊 Processed \(processedVideos) videos")
            print("📊 Found tags in \(videosWithTags) videos")
            print("📊 Total tags found: \(totalTags)")
            print("📊 Unique topics: \(topicCounts.count)")
            for (topic, count) in topicCounts.sorted(by: { $0.value > $1.value }) {
                print("   - \(topic): \(count) occurrences")
            }
            
            if topicCounts.isEmpty {
                print("⚠️ No topics found in any videos")
            }
            
            // Update user document
            let userRef = db.collection("users").document(userId)
            print("\n💾 Updating user document with topic distribution")
            let topicCountsCopy = topicCounts // Create a copy to avoid capturing the mutable dictionary
            @Sendable func updateTopicDistribution() async throws {
                try await userRef.updateData([
                    "topicDistribution": topicCountsCopy
                ] as [String: Any])
            }
            try await updateTopicDistribution()
            
            print("✅ Successfully updated topic distribution")
            
            // Reload user data to reflect changes
            await loadUserData()
            
        } catch {
            print("\n❌ SecondBrainViewModel: Error updating topic distribution")
            print("   - Error: \(error.localizedDescription)")
            self.error = "Failed to update topic distribution: \(error.localizedDescription)"
        }
    }
    
    func updateStreak() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        
        print("🔥 SecondBrainViewModel: Updating streak for user: \(userId)")
        
        do {
            let userRef = db.collection("users").document(userId)
            let userDoc = try await userRef.getDocument()
            
            guard let userData = userDoc.data(),
                  let lastActiveDate = (userData["lastActiveDate"] as? Timestamp)?.dateValue(),
                  let currentStreak = userData["currentStreak"] as? Int,
                  let longestStreak = userData["longestStreak"] as? Int else {
                return
            }
            
            let calendar = Calendar.current
            let now = Date()
            
            // Check if the user was active yesterday
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            let wasActiveYesterday = calendar.isDate(lastActiveDate, inSameDayAs: yesterday)
            
            // Check if the user was active today
            let isActiveToday = calendar.isDate(lastActiveDate, inSameDayAs: now)
            
            var newStreak = currentStreak
            if isActiveToday {
                // Streak continues
                newStreak = currentStreak
            } else if wasActiveYesterday {
                // New day, continue streak
                newStreak = currentStreak + 1
            } else {
                // Streak broken
                newStreak = 1
            }
            
            let newLongestStreak = max(longestStreak, newStreak)
            
            let updateData: [String: Sendable] = [
                "currentStreak": newStreak,
                "longestStreak": newLongestStreak,
                "lastActiveDate": Timestamp(date: now)
            ]
            
            try await userRef.setData(updateData, merge: true)
            print("✅ SecondBrainViewModel: Updated streak - Current: \(newStreak), Longest: \(newLongestStreak)")
            
            // Reload user data to reflect changes
            await loadUserData()
            
        } catch {
            print("❌ SecondBrainViewModel: Error updating streak: \(error.localizedDescription)")
            self.error = "Failed to update streak: \(error.localizedDescription)"
        }
    }
} 