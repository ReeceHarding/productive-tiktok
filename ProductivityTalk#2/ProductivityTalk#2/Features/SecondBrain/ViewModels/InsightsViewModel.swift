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
    }
    
    func fetchDailyInsight() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            print("❌ InsightsViewModel: No user ID found")
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
            
            // Select a random quote
            if let randomQuote = allQuotes.randomElement() {
                self.dailyInsight = randomQuote.quote
                print("✅ InsightsViewModel: Selected daily insight")
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
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        
        print("💾 InsightsViewModel: Saving insight from video: \(videoId)")
        
        do {
            // Get video details
            let videoDoc = try await db.collection("videos").document(videoId).getDocument()
            let videoData = videoDoc.data()
            let videoTitle = videoData?["title"] as? String
            let tags = videoData?["tags"] as? [String] ?? []
            let category = tags.first ?? "Uncategorized"
            
            // Create saved insight
            let insightId = UUID().uuidString
            let data: [String: Any] = [
                "quote": quote,
                "videoId": videoId,
                "savedAt": Timestamp(date: Date()),
                "category": category,
                "videoTitle": videoTitle ?? ""
            ]
            
            try await db.collection("users")
                .document(userId)
                .collection("savedInsights")
                .document(insightId)
                .setData(data)
            
            print("✅ InsightsViewModel: Successfully saved insight")
            await loadSavedInsights()
            
        } catch {
            print("❌ InsightsViewModel: Error saving insight: \(error.localizedDescription)")
            self.error = "Failed to save insight"
        }
    }
    
    func loadSavedInsights() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        
        isLoading = true
        print("📚 InsightsViewModel: Loading saved insights for user: \(userId)")
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("savedInsights")
                .order(by: "savedAt", descending: true)
                .getDocuments()
            
            var tags = Set<String>()
            self.savedInsights = snapshot.documents.compactMap { doc in
                guard let quote = doc.data()["quote"] as? String,
                      let videoId = doc.data()["videoId"] as? String,
                      let savedAt = (doc.data()["savedAt"] as? Timestamp)?.dateValue(),
                      let category = doc.data()["category"] as? String else {
                    return nil
                }
                
                // Add category to available tags
                tags.insert(category)
                
                return SavedInsight(
                    id: doc.documentID,
                    quote: quote,
                    videoId: videoId,
                    savedAt: savedAt,
                    category: category,
                    videoTitle: doc.data()["videoTitle"] as? String
                )
            }
            
            // Update available tags
            self.availableTags = tags
            
            print("✅ InsightsViewModel: Loaded \(self.savedInsights.count) saved insights")
            print("🏷️ InsightsViewModel: Found \(tags.count) unique tags")
        } catch {
            print("❌ InsightsViewModel: Error loading saved insights: \(error.localizedDescription)")
            self.error = "Failed to load saved insights"
        }
        
        isLoading = false
    }
    
    func deleteInsight(_ insightId: String) async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        
        print("🗑️ InsightsViewModel: Deleting insight: \(insightId)")
        
        do {
            try await db.collection("users")
                .document(userId)
                .collection("savedInsights")
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