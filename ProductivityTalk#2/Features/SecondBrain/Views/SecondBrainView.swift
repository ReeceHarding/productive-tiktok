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
            VStack(spacing: 24) {
                // Header with gradient background
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [.blue.opacity(0.8), .purple.opacity(0.6)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                        
                        if let user = viewModel.user {
                            Text("Welcome back, \(user.username)!")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.white)
                            
                            Text("Your Second Brain is growing stronger every day")
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 32)
                }
                .frame(maxWidth: .infinity)
                
                if viewModel.isLoading {
                    LoadingAnimation(message: "Loading your second brain...")
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let user = viewModel.user {
                    // Statistics Grid
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        StatisticCard(
                            title: "Videos",
                            value: "\(user.totalVideosUploaded)",
                            subtitle: "Total Uploads",
                            icon: "video.fill",
                            color: .blue
                        )
                        
                        StatisticCard(
                            title: "Views",
                            value: formatNumber(user.totalVideoViews),
                            subtitle: "Total Views",
                            icon: "eye.fill",
                            color: .green
                        )
                        
                        StatisticCard(
                            title: "Engagement",
                            value: String(format: "%.1f%%", user.videoEngagementRate * 100),
                            subtitle: "Video Engagement Rate",
                            icon: "chart.line.uptrend.xyaxis",
                            color: .orange
                        )
                        
                        StatisticCard(
                            title: "Second Brain",
                            value: "\(user.totalSecondBrainSaves)",
                            subtitle: "Total Saves",
                            icon: "brain.head.profile",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)
                    
                    // Growth Section with card style
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.blue)
                            Text("Growth")
                                .font(.title2)
                                .bold()
                        }
                        .padding(.horizontal)
                        
                        Chart {
                            BarMark(
                                x: .value("Period", "Weekly"),
                                y: .value("Growth", user.weeklySecondBrainGrowth * 100)
                            )
                            .foregroundStyle(Color.blue.gradient)
                            
                            BarMark(
                                x: .value("Period", "Monthly"),
                                y: .value("Growth", user.monthlySecondBrainGrowth * 100)
                            )
                            .foregroundStyle(Color.green.gradient)
                            
                            BarMark(
                                x: .value("Period", "Yearly"),
                                y: .value("Growth", user.yearlySecondBrainGrowth * 100)
                            )
                            .foregroundStyle(Color.purple.gradient)
                        }
                        .frame(height: 200)
                        .padding()
                    }
                    .background(colorScheme == .dark ? Color(.systemGray6) : .white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                    .padding(.horizontal)
                    
                    // Streak Section with improved visuals
                    HStack(spacing: 40) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                
                                Text("\(user.currentStreak)")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                            Text("Current Streak")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                
                                Text("\(user.longestStreak)")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.purple)
                            }
                            Text("Longest Streak")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(colorScheme == .dark ? Color(.systemGray6) : .white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                    .padding(.horizontal)
                    
                    // Topics Section with improved visuals
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundColor(.orange)
                            Text("Topics")
                                .font(.title2)
                                .bold()
                        }
                        .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                let sortedTopics = Array(user.topicDistribution.sorted { $0.value > $1.value })
                                
                                if sortedTopics.isEmpty {
                                    Text("No topics yet")
                                        .foregroundColor(.secondary)
                                        .padding()
                                } else {
                                    ForEach(sortedTopics, id: \.key) { topic, count in
                                        TopicBadge(topic: topic, count: count)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 20)
                    .background(colorScheme == .dark ? Color(.systemGray6) : .white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                    .padding(.horizontal)
                }
                
                if let error = viewModel.error {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .padding(.bottom, 20)
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color(.systemGray6))
        .task {
            await viewModel.loadUserData()
            await viewModel.updateStatistics()
            await viewModel.calculateGrowthRates()
            await viewModel.updateTopicDistribution()
            await viewModel.updateStreak()
        }
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
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Spacer()
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color(.systemGray6) : .white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

struct TopicBadge: View {
    let topic: String
    let count: Int
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 6) {
            Text(topic)
                .font(.subheadline)
                .bold()
            
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(.systemGray6) : .white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    NavigationView {
        SecondBrainView()
    }
} 