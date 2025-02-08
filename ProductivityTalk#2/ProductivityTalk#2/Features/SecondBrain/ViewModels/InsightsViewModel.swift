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
    
    struct SavedInsight: Identifiable {
        let id: String
        let quote: String
        let videoId: String
        let savedAt: Date
        let category: String
        var videoTitle: String?
    }
    
    init() {
        print("💡 InsightsViewModel: Initializing")
        loadCachedDailyInsight()
    }
    
    private func loadCachedDailyInsight() {
        if let lastUpdate = UserDefaults.standard.object(forKey: lastInsightUpdateKey) as? Date,
           Calendar.current.isDateInToday(lastUpdate),
           let cachedInsight = UserDefaults.standard.string(forKey: cachedDailyInsightKey) {
            print("📖 InsightsViewModel: Loading cached daily insight from today")
            self.dailyInsight = cachedInsight
        } else {
            print("🔄 InsightsViewModel: No valid cached insight found, will fetch new one")
            Task {
                await fetchDailyInsight()
            }
        }
    }
    
    func fetchDailyInsight() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ InsightsViewModel: No user ID found")
            self.error = "Please sign in to view insights"
            return
        }
        
        // Check if we already have a daily insight from today
        if let lastUpdate = UserDefaults.standard.object(forKey: lastInsightUpdateKey) as? Date,
           Calendar.current.isDateInToday(lastUpdate) {
            print("✨ InsightsViewModel: Already have today's insight")
            return
        }
        
        isLoading = true
        print("🎯 InsightsViewModel: Fetching daily insight for user: \(userId)")
        
        do {
            // Get all second brain entries
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("secondBrain")
                .getDocuments()
            
            print("📚 InsightsViewModel: Found \(snapshot.documents.count) second brain entries")
            
            // Collect all quotes
            var allQuotes: [(quote: String, videoId: String)] = []
            for doc in snapshot.documents {
                if let quotes = doc.data()["quotes"] as? [String],
                   let videoId = doc.data()["videoId"] as? String {
                    quotes.forEach { quote in
                        allQuotes.append((quote: quote, videoId: videoId))
                    }
                }
            }
            
            print("📝 InsightsViewModel: Collected \(allQuotes.count) total quotes")
            
            // Select a random quote
            if let randomQuote = allQuotes.randomElement() {
                self.dailyInsight = randomQuote.quote
                
                // Cache the new daily insight
                UserDefaults.standard.set(Date(), forKey: lastInsightUpdateKey)
                UserDefaults.standard.set(randomQuote.quote, forKey: cachedDailyInsightKey)
                
                print("✅ InsightsViewModel: Selected and cached new daily insight")
            } else {
                print("❌ InsightsViewModel: No quotes available")
                self.error = "No insights available yet"
            }
        } catch {
            print("❌ InsightsViewModel: Error fetching daily insight: \(error.localizedDescription)")
            self.error = "Failed to fetch daily insight"
        }
        
        isLoading = false
    }
    
    func saveInsight(_ quote: String, from videoId: String) async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            print("❌ InsightsViewModel: No user ID found")
            return
        }
        
        print("💾 InsightsViewModel: Saving insight from video: \(videoId)")
        
        do {
            // Get video details
            let videoDoc = try await db.collection("videos").document(videoId).getDocument()
            let videoData = videoDoc.data()
            let videoTitle = videoData?["title"] as? String
            let tags = videoData?["tags"] as? [String] ?? []
            
            // Create second brain entry
            let entryId = UUID().uuidString
            let data: [String: Any] = [
                "userId": userId,
                "videoId": videoId,
                "quotes": [quote],  // Store as array of quotes
                "savedAt": Timestamp(date: Date()),
                "videoTitle": videoTitle ?? "",
                "category": tags.first ?? "Uncategorized",
                "transcript": videoData?["transcript"] as? String ?? ""  // Include transcript if available
            ]
            
            try await db.collection("users")
                .document(userId)
                .collection("secondBrain")  // Changed from savedInsights to secondBrain
                .document(entryId)
                .setData(data)
            
            print("✅ InsightsViewModel: Successfully saved insight to Second Brain")
            await loadSavedInsights()
            
        } catch {
            print("❌ InsightsViewModel: Error saving insight: \(error.localizedDescription)")
            self.error = "Failed to save insight"
        }
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
                      let videoId = doc.data()["videoId"] as? String,
                      let savedAt = (doc.data()["savedAt"] as? Timestamp)?.dateValue() else {
                    print("⚠️ InsightsViewModel: Document \(doc.documentID) missing required fields")
                    print("   - Has quotes: \(doc.data()["quotes"] != nil)")
                    print("   - Has videoId: \(doc.data()["videoId"] != nil)")
                    print("   - Has savedAt: \(doc.data()["savedAt"] != nil)")
                    skippedCount += 1
                    return nil
                }
                
                guard let quote = quotes.first else {
                    print("⚠️ InsightsViewModel: Document \(doc.documentID) has empty quotes array")
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
                print("   - Saved at: \(savedAt)")
                
                return SavedInsight(
                    id: doc.documentID,
                    quote: quote,
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
            await loadSavedInsights()
            
        } catch {
            print("❌ InsightsViewModel: Error deleting insight: \(error.localizedDescription)")
            self.error = "Failed to delete insight"
        }
    }
} 