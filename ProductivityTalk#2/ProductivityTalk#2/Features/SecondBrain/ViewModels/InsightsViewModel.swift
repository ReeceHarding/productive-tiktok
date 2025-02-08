import Foundation
import FirebaseFirestore
import Combine

@MainActor
class InsightsViewModel: ObservableObject {
    @Published private(set) var dailyInsight: String?
    @Published private(set) var savedInsights: [SavedInsight] = []
    @Published private(set) var availableTags: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private let lastInsightUpdateKey = "lastDailyInsightUpdate"
    private let cachedDailyInsightKey = "cachedDailyInsight"
    private let secondBrainViewModel = SecondBrainViewModel()
    
    struct SavedInsight: Identifiable {
        let id: String
        let quotes: [String]
        let videoId: String
        let savedAt: Date
        let category: String
        var videoTitle: String?
    }
    
    init() {
        print("💡 InsightsViewModel: Initializing")
        print("🔍 InsightsViewModel: Checking for cached daily insight")
        loadCachedDailyInsight()
    }
    
    private func loadCachedDailyInsight() {
        print("📖 InsightsViewModel: Starting cached insight load")
        if let lastUpdate = UserDefaults.standard.object(forKey: lastInsightUpdateKey) as? Date {
            print("📅 InsightsViewModel: Last update found: \(lastUpdate)")
            if Calendar.current.isDateInToday(lastUpdate) {
                print("✅ InsightsViewModel: Last update was today")
                if let cachedInsight = UserDefaults.standard.string(forKey: cachedDailyInsightKey) {
                    print("📖 InsightsViewModel: Loading cached daily insight: \(cachedInsight)")
                    self.dailyInsight = cachedInsight
                } else {
                    print("⚠️ InsightsViewModel: No cached insight found despite having today's update")
                }
            } else {
                print("🔄 InsightsViewModel: Last update was not today, fetching new insight")
                Task {
                    await fetchDailyInsight()
                }
            }
        } else {
            print("🆕 InsightsViewModel: No last update found, fetching new insight")
            Task {
                await fetchDailyInsight()
            }
        }
    }
    
    func fetchDailyInsight() async {
        print("\n🎯 InsightsViewModel: Starting daily insight fetch")
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ InsightsViewModel: No user ID found - Authentication required")
            self.error = "Please sign in to view insights"
            return
        }
        print("👤 InsightsViewModel: User authenticated - ID: \(userId)")
        
        // Check if we already have a daily insight from today
        if let lastUpdate = UserDefaults.standard.object(forKey: lastInsightUpdateKey) as? Date {
            print("📅 InsightsViewModel: Found last update: \(lastUpdate)")
            if Calendar.current.isDateInToday(lastUpdate) {
                print("✨ InsightsViewModel: Already have today's insight, skipping fetch")
                return
            }
        }
        
        isLoading = true
        print("🔍 InsightsViewModel: Fetching daily insight for user: \(userId)")
        
        do {
            print("📚 InsightsViewModel: Querying Firestore path: users/\(userId)/secondBrain")
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .getDocuments()
            
            print("📊 InsightsViewModel: Query results:")
            print("   - Total documents: \(snapshot.documents.count)")
            
            // Collect all quotes
            var allQuotes: [(quote: String, videoId: String)] = []
            for doc in snapshot.documents {
                print("\n🔄 Processing document: \(doc.documentID)")
                let data = doc.data()
                print("📄 Document data: \(data)")
                
                if let quotes = data["quotes"] as? [String] {
                    print("📝 Found quotes array with \(quotes.count) quotes")
                    if let videoId = data["videoId"] as? String {
                        quotes.forEach { quote in
                            print("➕ Adding quote: \(quote)")
                            allQuotes.append((quote: quote, videoId: videoId))
                        }
                    } else {
                        print("⚠️ Missing videoId for document \(doc.documentID)")
                    }
                } else {
                    print("⚠️ No quotes array found in document \(doc.documentID)")
                }
            }
            
            print("\n📝 InsightsViewModel: Collection Summary")
            print("   - Total quotes collected: \(allQuotes.count)")
            
            // Select a random quote
            if let randomQuote = allQuotes.randomElement() {
                print("✅ Selected random quote: \(randomQuote.quote)")
                self.dailyInsight = randomQuote.quote
                
                // Cache the new daily insight
                UserDefaults.standard.set(Date(), forKey: lastInsightUpdateKey)
                UserDefaults.standard.set(randomQuote.quote, forKey: cachedDailyInsightKey)
                
                print("💾 InsightsViewModel: Cached new daily insight")
            } else {
                print("❌ InsightsViewModel: No quotes available to select from")
                self.error = "No insights available yet"
            }
        } catch {
            print("\n❌ InsightsViewModel: Error fetching daily insight")
            print("   - Error: \(error.localizedDescription)")
            print("   - Collection path: users/\(userId)/secondBrain")
            self.error = "Failed to fetch daily insight: \(error.localizedDescription)"
        }
        
        isLoading = false
        print("\n🏁 InsightsViewModel: Finished daily insight fetch")
    }
    
    func saveInsight(_ quote: String, from videoId: String) async {
        print("\n💾 InsightsViewModel: Starting to save insight")
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ InsightsViewModel: No user ID found - Authentication required")
            self.error = "Please sign in to save insights"
            return
        }
        
        print("👤 InsightsViewModel: User authenticated - ID: \(userId)")
        print("🎥 InsightsViewModel: Saving insight from video: \(videoId)")
        
        do {
            // Get video details
            print("🔍 InsightsViewModel: Fetching video details")
            let videoDoc = try await db.collection("videos").document(videoId).getDocument()
            guard let videoData = videoDoc.data() else {
                print("❌ InsightsViewModel: No video data found for ID: \(videoId)")
                self.error = "Video not found"
                return
            }
            
            print("📄 InsightsViewModel: Video data retrieved")
            let videoTitle = videoData["title"] as? String
            let tags = videoData["tags"] as? [String] ?? []
            let transcript = videoData["transcript"] as? String
            
            if transcript == nil {
                print("⚠️ InsightsViewModel: No transcript found for video")
            }
            
            // Create second brain entry with all required fields
            let entryId = UUID().uuidString
            print("🆕 InsightsViewModel: Creating new SecondBrain entry with ID: \(entryId)")
            
            let data: [String: Any] = [
                "userId": userId,
                "videoId": videoId,
                "quotes": [quote],
                "savedAt": Timestamp(date: Date()),
                "videoTitle": videoTitle ?? "",
                "category": tags.first ?? "Uncategorized",
                "transcript": transcript ?? "",  // Ensure transcript is never nil
                "videoThumbnailURL": videoData["thumbnailURL"] as? String ?? ""
            ]
            
            print("📝 InsightsViewModel: Prepared document data:")
            print("   - User ID: \(userId)")
            print("   - Video ID: \(videoId)")
            print("   - Quote Length: \(quote.count) characters")
            print("   - Video Title: \(videoTitle ?? "Not Set")")
            print("   - Category: \(tags.first ?? "Uncategorized")")
            print("   - Has Transcript: \(transcript != nil)")
            
            // Save to Firestore
            try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .document(entryId)
                .setData(data)
            
            print("✅ InsightsViewModel: Successfully saved insight to Second Brain")
            
            // Update user's statistics
            try await updateUserStatistics(userId: userId)
            
            // Update Second Brain statistics
            await secondBrainViewModel.updateStatistics()
            
            // Reload insights
            await loadSavedInsights()
            
        } catch {
            print("❌ InsightsViewModel: Error saving insight")
            print("   - Error: \(error.localizedDescription)")
            self.error = "Failed to save insight: \(error.localizedDescription)"
        }
    }
    
    private func updateUserStatistics(userId: String) async throws {
        print("📊 InsightsViewModel: Updating user statistics")
        let userRef = db.collection("users").document(userId)
        
        // Get current statistics
        let userDoc = try await userRef.getDocument()
        let currentSaves = (userDoc.data()?["totalSecondBrainSaves"] as? Int) ?? 0
        let currentQuotes = (userDoc.data()?["totalQuotesSaved"] as? Int) ?? 0
        let currentTranscripts = (userDoc.data()?["totalTranscriptsSaved"] as? Int) ?? 0
        
        // Get all saved insights to calculate accurate statistics
        let insightsSnapshot = try await userRef.collection("secondBrain").getDocuments()
        var totalQuotes = 0
        var totalTranscripts = 0
        
        for doc in insightsSnapshot.documents {
            if let quotes = doc.data()["quotes"] as? [String] {
                totalQuotes += quotes.count
            }
            if doc.data()["transcript"] as? String != nil {
                totalTranscripts += 1
            }
        }
        
        // Update statistics
        let newQuotesCount = currentQuotes + 1
        let newTranscriptsCount = currentTranscripts + 1
        let updateData: [String: Any] = [
            "totalSecondBrainSaves": currentSaves + 1,
            "totalQuotesSaved": newQuotesCount,
            "totalTranscriptsSaved": newTranscriptsCount,
            "lastActiveDate": Timestamp(date: Date()),
            "lastUpdated": Timestamp()
        ]
        try await userRef.updateData(updateData)
        
        print("✅ InsightsViewModel: Successfully updated user statistics")
        print("   - Total Second Brain Saves: \(currentSaves + 1)")
        print("   - Total Quotes Saved: \(newQuotesCount)")
        print("   - Total Transcripts Saved: \(newTranscriptsCount)")
    }
    
    func loadSavedInsights() async {
        print("\n📚 InsightsViewModel: Starting to load saved insights...")
        
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ InsightsViewModel: No user ID found - Authentication required")
            self.error = "Please sign in to view insights"
            return
        }
        print("👤 InsightsViewModel: User authenticated - ID: \(userId)")
        
        isLoading = true
        print("🔍 InsightsViewModel: Querying Firestore path: users/\(userId)/secondBrain")
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .order(by: "savedAt", descending: true)
                .getDocuments()
            
            print("📊 InsightsViewModel: Query results:")
            print("   - Total documents: \(snapshot.documents.count)")
            
            var tags = Set<String>()
            var processedCount = 0
            var skippedCount = 0
            
            self.savedInsights = snapshot.documents.compactMap { doc in
                print("\n🔄 Processing document: \(doc.documentID)")
                
                guard let quotes = doc.data()["quotes"] as? [String],
                      !quotes.isEmpty,
                      let videoId = doc.data()["videoId"] as? String,
                      let savedAt = (doc.data()["savedAt"] as? Timestamp)?.dateValue() else {
                    print("⚠️ InsightsViewModel: Document \(doc.documentID) missing required fields")
                    print("   - Has quotes: \(doc.data()["quotes"] != nil)")
                    print("   - Quotes count: \((doc.data()["quotes"] as? [String])?.count ?? 0)")
                    print("   - Has videoId: \(doc.data()["videoId"] != nil)")
                    print("   - Has savedAt: \(doc.data()["savedAt"] != nil)")
                    skippedCount += 1
                    return nil
                }
                
                let category = doc.data()["category"] as? String ?? "Uncategorized"
                tags.insert(category)
                
                processedCount += 1
                print("✅ Document processed successfully:")
                print("   - Video ID: \(videoId)")
                print("   - Category: \(category)")
                print("   - Quotes count: \(quotes.count)")
                print("   - First quote: \(quotes[0])")
                print("   - Saved at: \(savedAt)")
                
                return SavedInsight(
                    id: doc.documentID,
                    quotes: quotes,
                    videoId: videoId,
                    savedAt: savedAt,
                    category: category,
                    videoTitle: doc.data()["videoTitle"] as? String
                )
            }
            
            self.availableTags = tags
            
            print("\n📊 InsightsViewModel: Processing Summary")
            print("   - Total documents: \(snapshot.documents.count)")
            print("   - Successfully processed: \(processedCount)")
            print("   - Skipped/Invalid: \(skippedCount)")
            print("   - Unique categories: \(tags.count)")
            print("   Categories: \(tags.joined(separator: ", "))")
            
        } catch {
            print("\n❌ InsightsViewModel: Error loading insights")
            print("   - Error: \(error.localizedDescription)")
            print("   - Collection path: users/\(userId)/secondBrain")
            self.error = "Failed to load saved insights"
        }
        
        isLoading = false
        print("\n🏁 InsightsViewModel: Finished loading insights")
    }
    
    func deleteInsight(_ insightId: String) async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ InsightsViewModel: No user ID found")
            self.error = "Please sign in to delete insights"
            return
        }
        
        print("🗑️ InsightsViewModel: Deleting insight: \(insightId)")
        
        do {
            try await db.collection("users")
                .document(userId)
                .collection("secondBrain")  // Changed from savedInsights to secondBrain
                .document(insightId)
                .delete()
            
            print("✅ InsightsViewModel: Successfully deleted insight")
            
            // Update Second Brain statistics
            await secondBrainViewModel.updateStatistics()
            
            await loadSavedInsights()
            
        } catch {
            print("❌ InsightsViewModel: Error deleting insight: \(error.localizedDescription)")
            self.error = "Failed to delete insight"
        }
    }
} 