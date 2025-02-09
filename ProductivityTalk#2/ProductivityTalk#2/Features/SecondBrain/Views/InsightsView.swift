import SwiftUI
import UIKit

struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    @StateObject private var secondBrainViewModel = SecondBrainViewModel()
    @State private var selectedCategory: String = "All"
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.3),
                    Color.purple.opacity(0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Insight of the Day
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Insight of the Day")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("A key insight to ponder")
                            .foregroundColor(.gray)
                        
                        if let insight = viewModel.dailyInsight {
                            Text(insight)
                                .font(.title3)
                                .italic()
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .systemBackground))
                                .cornerRadius(12)
                                .shadow(radius: 2)
                        } else if viewModel.isLoading {
                            LoadingAnimation(message: "Loading insight...")
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("No insights available yet")
                                .foregroundColor(.gray)
                                .padding()
                        }
                        
                        HStack {
                            Button("Dismiss") {
                                // Fetch a new insight
                                Task {
                                    await viewModel.fetchDailyInsight()
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            if let insight = viewModel.dailyInsight {
                                Button("Save for Later") {
                                    // Save the insight
                                    Task {
                                        await viewModel.saveInsight(insight, from: "daily_insight")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(16)
                    
                    // Quick Stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Stats")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Your learning progress")
                            .foregroundColor(.gray)
                        
                        VStack(spacing: 16) {
                            HStack {
                                Text("Total Insights")
                                Spacer()
                                Text("\(viewModel.savedInsights.count)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            
                            HStack {
                                Text("This Week")
                                Spacer()
                                Text("\(viewModel.savedInsights.filter { Calendar.current.isDate($0.savedAt, equalTo: Date(), toGranularity: .weekOfYear) }.count)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            
                            HStack {
                                Text("Learning Streak")
                                Spacer()
                                if let user = secondBrainViewModel.user {
                                    Text("\(user.currentStreak) days")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                } else {
                                    Text("0 days")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                }
                            }
                        }
                        .padding()
                    }
                    .padding()
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(12)
                    
                    // Category Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            Button("All") {
                                selectedCategory = "All"
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedCategory == "All" ? .blue : .gray)
                            
                            ForEach(Array(viewModel.availableTags).sorted(), id: \.self) { category in
                                Button(category) {
                                    selectedCategory = category
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedCategory == category ? .blue : .gray)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Saved Insights
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Saved Insights")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Your personal collection of valuable content")
                            .foregroundColor(.gray)
                        
                        if viewModel.isLoading {
                            LoadingAnimation(message: "Loading saved insights...")
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if viewModel.savedInsights.isEmpty {
                            Text("No saved insights yet")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.savedInsights.filter {
                                    selectedCategory == "All" || $0.category == selectedCategory
                                }) { insight in
                                    InsightCard(insight: insight) {
                                        Task {
                                            await viewModel.deleteInsight(insight.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .padding()
            }
        }
        .task {
            await viewModel.fetchDailyInsight()
            await viewModel.loadSavedInsights()
            await secondBrainViewModel.loadUserData()
        }
        .refreshable {
            await viewModel.fetchDailyInsight()
            await viewModel.loadSavedInsights()
            await secondBrainViewModel.loadUserData()
        }
    }
}

struct InsightCard: View {
    let insight: InsightsViewModel.SavedInsight
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Display first quote if available
            if !insight.quotes.isEmpty {
                Text(insight.quotes[0])
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(12)
                
                if insight.quotes.count > 1 {
                    Text("+\(insight.quotes.count - 1) more quotes")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    if let title = insight.videoTitle {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Text(insight.category)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text(insight.savedAt.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            HStack {
                NavigationLink("View Details") {
                    InsightDetailView(insight: insight)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct InsightDetailView: View {
    let insight: InsightsViewModel.SavedInsight
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let title = insight.videoTitle {
                    Text(title)
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quotes")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    ForEach(insight.quotes, id: \.self) { quote in
                        Text(quote)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .systemBackground))
                            .cornerRadius(12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Category:")
                            .fontWeight(.medium)
                        Text(insight.category)
                    }
                    
                    HStack {
                        Text("Saved on:")
                            .fontWeight(.medium)
                        Text(insight.savedAt.formatted())
                    }
                    
                    HStack {
                        Text("Total Quotes:")
                            .fontWeight(.medium)
                        Text("\(insight.quotes.count)")
                    }
                }
                .foregroundColor(.gray)
            }
            .padding()
        }
        .navigationTitle("Insight Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        InsightsView()
    }
} 