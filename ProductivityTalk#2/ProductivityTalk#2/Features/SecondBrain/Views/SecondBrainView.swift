import SwiftUI
import Charts

struct SecondBrainView: View {
    @StateObject private var viewModel = SecondBrainViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    private let gridColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let user = viewModel.user {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        // Video Statistics
                        StatisticCard(
                            title: "Videos",
                            value: "\(user.totalVideosUploaded)",
                            subtitle: "Total Uploads",
                            icon: "video.fill"
                        )
                        
                        StatisticCard(
                            title: "Views",
                            value: formatNumber(user.totalVideoViews),
                            subtitle: "Total Views",
                            icon: "eye.fill"
                        )
                        
                        StatisticCard(
                            title: "Engagement",
                            value: String(format: "%.1f%%", user.videoEngagementRate * 100),
                            subtitle: "Video Engagement Rate",
                            icon: "chart.line.uptrend.xyaxis"
                        )
                        
                        StatisticCard(
                            title: "Second Brain",
                            value: "\(user.totalSecondBrainSaves)",
                            subtitle: "Total Saves",
                            icon: "brain.head.profile"
                        )
                    }
                    .padding(.horizontal)
                    
                    // Growth Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Growth")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal)
                        
                        Chart {
                            BarMark(
                                x: .value("Period", "Weekly"),
                                y: .value("Growth", user.weeklySecondBrainGrowth * 100)
                            )
                            .foregroundStyle(Color.blue)
                            
                            BarMark(
                                x: .value("Period", "Monthly"),
                                y: .value("Growth", user.monthlySecondBrainGrowth * 100)
                            )
                            .foregroundStyle(Color.green)
                            
                            BarMark(
                                x: .value("Period", "Yearly"),
                                y: .value("Growth", user.yearlySecondBrainGrowth * 100)
                            )
                            .foregroundStyle(Color.purple)
                        }
                        .frame(height: 200)
                        .padding()
                    }
                    
                    // Streak Section
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(user.currentStreak)")
                                .font(.system(size: 36, weight: .bold))
                            Text("Current Streak")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack {
                            Text("\(user.longestStreak)")
                                .font(.system(size: 36, weight: .bold))
                            Text("Longest Streak")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Topic Distribution
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Topics")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(user.topicDistribution.sorted { $0.value > $1.value }), id: \.key) { topic, count in
                                    TopicBadge(topic: topic, count: count)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                if let error = viewModel.error {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
            }
        }
        .navigationTitle("Second Brain")
        .task {
            await viewModel.loadUserData()
            await viewModel.updateStatistics()
            await viewModel.calculateGrowthRates()
            await viewModel.updateTopicDistribution()
            await viewModel.updateStreak()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let user = viewModel.user {
                Text("Welcome back, \(user.username)!")
                    .font(.title2)
                    .bold()
                
                Text("Your Second Brain is growing stronger every day")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        
        if number >= 1_000_000 {
            formatter.positiveSuffix = "M"
            return formatter.string(from: NSNumber(value: Double(number) / 1_000_000)) ?? "\(number)"
        } else if number >= 1_000 {
            formatter.positiveSuffix = "K"
            return formatter.string(from: NSNumber(value: Double(number) / 1_000)) ?? "\(number)"
        }
        
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text(title)
                    .font(.headline)
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
        .cornerRadius(12)
    }
}

struct TopicBadge: View {
    let topic: String
    let count: Int
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            Text(topic)
                .font(.caption)
                .bold()
            
            Text("\(count)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
        .cornerRadius(16)
    }
}

#Preview {
    NavigationView {
        SecondBrainView()
    }
} 