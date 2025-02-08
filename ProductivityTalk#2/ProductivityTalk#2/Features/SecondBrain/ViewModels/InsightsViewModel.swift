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
                LoggingService.debug("🔄 Processing document: \(doc.documentID)", component: "Insights")
                let data = doc.data()
                LoggingService.debug("📄 Document data: \(data)", component: "Insights")
                
                // Try to get quotes from either field
                var quotes: [String]? = data["quotes"] as? [String]
                if let quotes = quotes, !quotes.isEmpty {
                    LoggingService.debug("📝 Found quotes in 'quotes' field for document \(doc.documentID): \(quotes)", component: "Insights")
                } else if let extractedQuotes = data["extractedQuotes"] as? [String], !extractedQuotes.isEmpty {
                    LoggingService.debug("📝 Found quotes in 'extractedQuotes' field for document \(doc.documentID): \(extractedQuotes)", component: "Insights")
                    quotes = extractedQuotes
                } else {
                    LoggingService.warning("⚠️ No quotes found in document \(doc.documentID)", component: "Insights")
                }
                
                if let validQuotes = quotes, !validQuotes.isEmpty, let videoId = data["videoId"] as? String {
                    for quote in validQuotes {
                        allQuotes.append((quote: quote, videoId: videoId))
                    }
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
        LoggingService.debug("🎬 Second Brain: Starting to save insight", component: "Insights")
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            LoggingService.error("❌ Second Brain: No authenticated user", component: "Insights")
            self.error = "Please sign in to save insights"
            return
        }
        
        LoggingService.debug("👤 Second Brain: User authenticated - ID: \(userId)", component: "Insights")
        LoggingService.debug("🎥 Second Brain: Saving insight from video: \(videoId)", component: "Insights")
        
        do {
            // Get video details
            LoggingService.debug("🔍 Second Brain: Fetching video details", component: "Insights")
            let videoDoc = try await db.collection("videos").document(videoId).getDocument()
            guard let videoData = videoDoc.data() else {
                LoggingService.error("❌ Second Brain: No video data found for ID: \(videoId)", component: "Insights")
                self.error = "Video not found"
                return
            }
            
            LoggingService.debug("📄 Second Brain: Video data retrieved", component: "Insights")
            let videoTitle = videoData["title"] as? String
            let tags = videoData["tags"] as? [String] ?? []
            let transcript = videoData["transcript"] as? String
            
            if transcript == nil {
                LoggingService.warning("⚠️ Second Brain: No transcript found for video", component: "Insights")
            }
            
            // Create second brain entry with all required fields
            let entryId = UUID().uuidString
            LoggingService.debug("🆕 Second Brain: Creating new entry with ID: \(entryId)", component: "Insights")
            
            let data: [String: Any] = [
                "userId": userId,
                "videoId": videoId,
                "quotes": [quote],
                "savedAt": Timestamp(date: Date()),
                "videoTitle": videoTitle ?? "",
                "category": tags.first ?? "Uncategorized",
                "transcript": transcript ?? "",
                "videoThumbnailURL": videoData["thumbnailURL"] as? String ?? ""
            ]
            
            LoggingService.debug("📝 Second Brain: Prepared document data:", component: "Insights")
            LoggingService.debug("   - User ID: \(userId)", component: "Insights")
            LoggingService.debug("   - Video ID: \(videoId)", component: "Insights")
            LoggingService.debug("   - Quote Length: \(quote.count) characters", component: "Insights")
            LoggingService.debug("   - Video Title: \(videoTitle ?? "Not Set")", component: "Insights")
            LoggingService.debug("   - Category: \(tags.first ?? "Uncategorized")", component: "Insights")
            LoggingService.debug("   - Has Transcript: \(transcript != nil)", component: "Insights")
            
            // Save to Firestore
            try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .document(entryId)
                .setData(data)
            
            LoggingService.success("✅ Second Brain: Successfully saved insight", component: "Insights")
            
            // Update user's statistics
            try await updateUserStatistics(userId: userId)
            LoggingService.debug("📊 Second Brain: Updated user statistics", component: "Insights")
            
            // Update Second Brain statistics
            await secondBrainViewModel.updateStatistics()
            LoggingService.debug("📊 Second Brain: Updated global statistics", component: "Insights")
            
            // Reload insights
            await loadSavedInsights()
            LoggingService.debug("🔄 Second Brain: Reloaded insights list", component: "Insights")
            
        } catch {
            LoggingService.error("❌ Second Brain: Error saving insight: \(error.localizedDescription)", component: "Insights")
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
            
            print("\n📊 InsightsViewModel: Query results:")
            print("   - Total documents found: \(snapshot.documents.count)")
            
            var newInsights: [SavedInsight] = []
            var totalQuotes = 0
            var categoryCounts: [String: Int] = [:]
            
            for doc in snapshot.documents {
                let data = doc.data()
                
                // Try to get quotes from either field
                var quotes: [String]? = data["quotes"] as? [String]
                if let quotes = quotes, !quotes.isEmpty {
                    LoggingService.debug("📝 Found quotes in 'quotes' field for document \(doc.documentID): \(quotes)", component: "Insights")
                } else if let extractedQuotes = data["extractedQuotes"] as? [String], !extractedQuotes.isEmpty {
                    LoggingService.debug("📝 Found quotes in 'extractedQuotes' field for document \(doc.documentID): \(extractedQuotes)", component: "Insights")
                    quotes = extractedQuotes
                } else {
                    LoggingService.warning("⚠️ No quotes found in document \(doc.documentID)", component: "Insights")
                }
                
                guard let validQuotes = quotes, !validQuotes.isEmpty,
                      let videoId = data["videoId"] as? String else {
                    LoggingService.warning("⚠️ Missing required fields in saved insight document \(doc.documentID)", component: "Insights")
                    continue
                }
                
                let savedAtTimestamp = data["savedAt"] as? Timestamp
                let savedAt = savedAtTimestamp?.dateValue() ?? Date()
                let category = data["category"] as? String ?? "Uncategorized"
                let videoTitle = data["videoTitle"] as? String
                
                newInsights.append(SavedInsight(id: doc.documentID, quotes: validQuotes, videoId: videoId, savedAt: savedAt, category: category, videoTitle: videoTitle))
                totalQuotes += validQuotes.count
                categoryCounts[category, default: 0] += 1
            }
            
            self.savedInsights = newInsights
            self.availableTags = Set(categoryCounts.keys)
            
            print("\n📊 Processing Summary:")
            print("   - Total documents: \(snapshot.documents.count)")
            print("   - Total quotes across all documents: \(totalQuotes)")
            print("   - Average quotes per document: \(totalQuotes > 0 ? Double(totalQuotes) / Double(snapshot.documents.count) : 0)")
            print("\n📑 Category Distribution:")
            for (category, count) in categoryCounts.sorted(by: { $0.value > $1.value }) {
                print("   - \(category): \(count) documents (\(String(format: "%.1f%%", Double(count) / Double(totalQuotes) * 100))")
            }
            
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