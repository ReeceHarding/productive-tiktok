import SwiftUI
import UIKit

struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    @StateObject private var secondBrainViewModel = SecondBrainViewModel()
    @State private var selectedCategory: String = "All"
    @State private var searchText = ""
    @State private var showingSearchView = false
    @State private var showingSortOptions = false
    @State private var sortOption: SortOption = .newest
    @State private var showingFilters = false
    
    private var filteredInsights: [InsightsViewModel.SavedInsight] {
        viewModel.savedInsights.filter {
            let categoryMatch = selectedCategory == "All" || $0.category == selectedCategory
            let searchMatch = searchText.isEmpty || 
                $0.quotes.joined(separator: " ").localizedCaseInsensitiveContains(searchText) ||
                ($0.videoTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
            return categoryMatch && searchMatch
        }.sorted { first, second in
            switch sortOption {
            case .newest:
                return first.savedAt > second.savedAt
            case .oldest:
                return first.savedAt < second.savedAt
            case .category:
                return first.category < second.category
            }
        }
    }
    
    var body: some View {
        NavigationView {
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
                        // Daily Insight Card
                        DailyInsightCard(
                            insight: viewModel.dailyInsight,
                            isLoading: viewModel.isLoading,
                            onDismiss: {
                                Task {
                                    await viewModel.fetchDailyInsight()
                                }
                            },
                            onSave: { insight in
                                Task {
                                    await viewModel.saveInsight(insight, from: "daily_insight")
                                }
                            }
                        )
                        
                        // Quick Stats Grid
                        StatsGridView(
                            totalInsights: viewModel.savedInsights.count,
                            weeklyInsights: viewModel.savedInsights.filter { 
                                Calendar.current.isDate($0.savedAt, equalTo: Date(), toGranularity: .weekOfYear)
                            }.count,
                            learningStreak: secondBrainViewModel.user?.currentStreak ?? 0
                        )
                        
                        // Category Filter
                        CategoryFilterView(
                            selectedCategory: $selectedCategory,
                            categories: Array(viewModel.availableTags)
                        )
                        
                        // Saved Insights List
                        SavedInsightsList(
                            insights: filteredInsights,
                            isLoading: viewModel.isLoading,
                            onDelete: { insightId in
                                Task {
                                    await viewModel.deleteInsight(insightId)
                                }
                            }
                        )
                    }
                    .padding()
                }
                .refreshable {
                    await viewModel.fetchDailyInsight()
                    await viewModel.loadSavedInsights()
                    await secondBrainViewModel.loadUserData()
                }
                .searchable(text: $searchText, prompt: "Search insights...")
                .navigationTitle("Second Brain")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Picker("Sort by", selection: $sortOption) {
                                ForEach(SortOption.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.fetchDailyInsight()
            await viewModel.loadSavedInsights()
            await secondBrainViewModel.loadUserData()
        }
    }
}

// MARK: - Supporting Views

struct DailyInsightCard: View {
    let insight: String?
    let isLoading: Bool
    let onDismiss: () -> Void
    let onSave: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Daily Insight", systemImage: "lightbulb.fill")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.white)
                }
            }
            
            if let insight = insight {
                Text(insight)
                    .font(.title3)
                    .italic()
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                
                Button(action: { onSave(insight) }) {
                    Label("Save to Second Brain", systemImage: "brain.head.profile")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            } else if isLoading {
                LoadingAnimation(message: "Loading insight...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text("No insights available yet")
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
    }
}

struct StatsGridView: View {
    let totalInsights: Int
    let weeklyInsights: Int
    let learningStreak: Int
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "Total Insights", value: "\(totalInsights)", icon: "brain.head.profile.fill")
            StatCard(title: "This Week", value: "\(weeklyInsights)", icon: "calendar.badge.clock")
            StatCard(title: "Learning Streak", value: "\(learningStreak) days", icon: "flame.fill")
            StatCard(title: "Categories", value: "View All", icon: "tag.fill")
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.8))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct CategoryFilterView: View {
    @Binding var selectedCategory: String
    let categories: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                CategoryButton(title: "All", isSelected: selectedCategory == "All") {
                    selectedCategory = "All"
                }
                
                ForEach(categories.sorted(), id: \.self) { category in
                    CategoryButton(title: category, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

struct SavedInsightsList: View {
    let insights: [InsightsViewModel.SavedInsight]
    let isLoading: Bool
    let onDelete: (String) -> Void
    
    var body: some View {
        if isLoading {
            LoadingAnimation(message: "Loading insights...")
                .frame(maxWidth: .infinity)
                .padding()
        } else if insights.isEmpty {
            Text("No insights saved yet")
                .foregroundColor(.secondary)
                .padding()
        } else {
            LazyVStack(spacing: 16) {
                ForEach(insights) { insight in
                    if !insight.quotes.isEmpty {
                        InsightCard(insight: insight, onDelete: onDelete)
                    }
                }
            }
        }
    }
}

struct InsightCard: View {
    let insight: InsightsViewModel.SavedInsight
    let onDelete: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(insight.quotes, id: \.self) { quote in
                Text(quote)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            if let title = insight.videoTitle {
                Label(title, systemImage: "video.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label(insight.category, systemImage: "tag.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Button(role: .destructive, action: { onDelete(insight.id) }) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.8))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Models

struct InsightDetailView: View {
    let insight: InsightsViewModel.SavedInsight
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Video title section
                    if let title = insight.videoTitle {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("From Video")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(title)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                    
                    // Quotes section
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Quotes", systemImage: "text.quote")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        ForEach(insight.quotes, id: \.self) { quote in
                            Text(quote)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.blue.opacity(0.1),
                                            Color.purple.opacity(0.1)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(12)
                        }
                    }
                    
                    // Metadata section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Details", systemImage: "info.circle")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        DetailRow(icon: "tag", title: "Category", value: insight.category)
                        DetailRow(icon: "calendar", title: "Saved on", value: insight.savedAt.formatted())
                        DetailRow(icon: "number", title: "Total Quotes", value: "\(insight.quotes.count)")
                    }
                }
                .padding()
            }
            .navigationTitle("Insight Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.secondary)
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
        }
        .font(.subheadline)
    }
}

enum SortOption: String, CaseIterable, Identifiable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case category = "By Category"
    
    var id: String { self.rawValue }
}

// MARK: - Preview
#Preview {
    NavigationView {
        InsightsView()
    }
} 