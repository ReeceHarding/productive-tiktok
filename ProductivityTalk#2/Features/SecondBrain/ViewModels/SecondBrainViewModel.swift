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
        print("\n📥 SecondBrainViewModel: Starting user data load for user \(userId)")
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let appUser = AppUser(document: document) {
                self.user = appUser
                self.error = nil
                print("✅ SecondBrainViewModel: Successfully loaded user doc for \(userId)")
            } else {
                print("❌ SecondBrainViewModel: Document for \(userId) not parseable as AppUser")
                self.error = "User document missing or incomplete"
                self.user = nil
            }
        } catch {
            print("❌ SecondBrainViewModel: Error loading user data: \(error.localizedDescription)")
            self.error = "Failed to load user data: \(error.localizedDescription)"
            self.user = nil
        }
        isLoading = false
        print("🏁 SecondBrainViewModel: Finished loadUserData")
    }
    
    func updateStatistics() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            print("❌ SecondBrainViewModel.updateStatistics: No user ID found in user defaults")
            return
        }
        
        print("\n📊 SecondBrainViewModel.updateStatistics: Starting statistics update for user: \(userId)")
        
        do {
            // Get all videos that user owns
            let videosSnapshot = try await db.collection("videos")
                .whereField("ownerId", isEqualTo: userId)
                .getDocuments()
            
            // Calculate aggregated fields
            let totalVideos = videosSnapshot.documents.count
            let totalLikes = videosSnapshot.documents.reduce(0) {
                $0 + ( ($1.data()["likeCount"] as? Int) ?? 0 )
            }
            let totalShares = videosSnapshot.documents.reduce(0) {
                $0 + ( ($1.data()["shareCount"] as? Int) ?? 0 )
            }
            let totalSaves = videosSnapshot.documents.reduce(0) {
                $0 + ( ($1.data()["saveCount"] as? Int) ?? 0 )
            }
            
            // For comments, we do not have a direct measure except in each 'video' doc
            let totalComments = videosSnapshot.documents.reduce(0) {
                $0 + ( ($1.data()["commentCount"] as? Int) ?? 0 )
            }
            
            // For 'brainCount', i.e. how many times a video was added to secondBrain
            let totalBrainSaves = videosSnapshot.documents.reduce(0) {
                $0 + ( ($1.data()["brainCount"] as? Int) ?? 0 )
            }
            
            // Engagement Rates - now calculated per video instead of views
            let videoEngagementRate: Double = (totalVideos > 0)
              ? Double(totalLikes + totalShares + totalSaves) / Double(totalVideos)
              : 0.0
            let commentEngagementRate: Double = (totalComments > 0)
              ? Double(totalBrainSaves) / Double(totalComments)
              : 0.0
            
            // We'll store these in the user doc
            let userRef = db.collection("users").document(userId)
            try await userRef.setData([
                "totalVideosUploaded": totalVideos,
                "totalVideoLikes": totalLikes,
                "totalVideoShares": totalShares,
                "totalVideoSaves": totalSaves,
                "totalCommentsPosted": totalComments, // Not perfect but an approximation
                "totalSecondBrainSaves": totalBrainSaves,
                "videoEngagementRate": videoEngagementRate,
                "commentEngagementRate": commentEngagementRate,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            
            print("✅ SecondBrainViewModel.updateStatistics: Updated user doc with aggregated stats")
            
            // Reload user
            await loadUserData()
            
        } catch {
            print("❌ SecondBrainViewModel.updateStatistics: Error updating statistics: \(error.localizedDescription)")
            self.error = "Failed to update user stats: \(error.localizedDescription)"
        }
    }
    
    func calculateGrowthRates() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        print("📈 SecondBrainViewModel.calculateGrowthRates: For user \(userId)")
        // This example does not track historical stats in detail. We'll just no-op for now.
        // If you want full historical growth, store daily snapshots in a 'userStats' subcollection.
        // Then replicate your approach (like we do in the sample).
        // We'll keep the function for demonstration.
        print("Skipping detailed growth rate due to lack of historical snapshot logic. No-op.")
    }
    
    func updateTopicDistribution() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            print("❌ SecondBrainViewModel.updateTopicDistribution: No userId found in defaults")
            return
        }
        print("\n🏷️ SecondBrainViewModel.updateTopicDistribution: Starting for user \(userId)")
        
        do {
            // 1) Read user's secondBrain subcollection for all entries
            let secondBrainSnapshot = try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .getDocuments()
            
            print("🔍 Fetched \(secondBrainSnapshot.documents.count) secondBrain documents for user \(userId)")
            
            // 2) For each secondBrain entry, gather the videoId, fetch 'videos/{videoId}', read 'tags'
            var topicCounts: [String: Int] = [:]
            var processedCount = 0
            
            for doc in secondBrainSnapshot.documents {
                let data = doc.data()
                guard let videoId = data["videoId"] as? String else {
                    print("⚠️ secondBrain doc missing videoId, docID = \(doc.documentID)")
                    continue
                }
                
                let videoDoc = try await db.collection("videos").document(videoId).getDocument()
                guard videoDoc.exists, let videoData = videoDoc.data() else {
                    print("⚠️ No 'videos/\(videoId)' data found or doc doesn't exist, skipping")
                    continue
                }
                
                if let videoTags = videoData["tags"] as? [String] {
                    for tag in videoTags {
                        topicCounts[tag, default: 0] += 1
                    }
                } else {
                    print("ℹ️ Video \(videoId) has no 'tags' array, skipping it")
                }
                processedCount += 1
            }
            
            print("✅ Processed \(processedCount) secondBrain entries. Built topicCounts with \(topicCounts.count) unique tags")
            
            // 3) Save in the user doc
            let userRef = db.collection("users").document(userId)
            try await userRef.setData([
                "topicDistribution": topicCounts,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            
            print("✅ SecondBrainViewModel.updateTopicDistribution: updated topicDistribution for user \(userId)")
            
            // Reload user doc so UI can reflect new distribution
            await loadUserData()
            
        } catch {
            print("❌ SecondBrainViewModel.updateTopicDistribution: Error: \(error.localizedDescription)")
            self.error = "Failed to update topic distribution: \(error.localizedDescription)"
        }
    }
    
    func updateStreak() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        print("🔥 SecondBrainViewModel.updateStreak: Updating streak for user: \(userId)")
        
        do {
            let userRef = db.collection("users").document(userId)
            let userDoc = try await userRef.getDocument()
            guard let userData = userDoc.data() else { return }
            
            let lastActiveDate = (userData["lastActiveDate"] as? Timestamp)?.dateValue() ?? Date()
            let currentStreak = userData["currentStreak"] as? Int ?? 0
            let longestStreak = userData["longestStreak"] as? Int ?? 0
            
            let now = Date()
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            
            let wasActiveYesterday = calendar.isDate(lastActiveDate, inSameDayAs: yesterday)
            let isActiveToday = calendar.isDate(lastActiveDate, inSameDayAs: now)
            
            var newStreak = currentStreak
            if isActiveToday {
                newStreak = currentStreak
            } else if wasActiveYesterday {
                newStreak = currentStreak + 1
            } else {
                newStreak = 1
            }
            
            let newLongestStreak = max(longestStreak, newStreak)
            
            try await userRef.setData([
                "currentStreak": newStreak,
                "longestStreak": newLongestStreak,
                "lastActiveDate": Timestamp(date: now)
            ], merge: true)
            
            print("✅ SecondBrainViewModel.updateStreak: Streak updated to \(newStreak), longest \(newLongestStreak)")
            // Reload
            await loadUserData()
            
        } catch {
            print("❌ SecondBrainViewModel.updateStreak: Error: \(error.localizedDescription)")
            self.error = "Failed to update streak: \(error.localizedDescription)"
        }
    }
} 