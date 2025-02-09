import SwiftUI
import Charts

struct SecondBrainView: View {
    @StateObject private var viewModel = SecondBrainViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    private let gridColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    // Define consistent card style
    private var cardBackground: some View {
        Color(uiColor: .systemBackground)
            .opacity(0.8)
            .cornerRadius(20)
            .shadow(radius: 5)
    }
    
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
                VStack(spacing: 24) {
                    // Header with gradient background
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(radius: 2)
                        
                        if let user = viewModel.user {
                            Text("Welcome back, \(user.username)!")
                                .font(.title2)
                                .bold()
                            
                            Text("Your Second Brain is growing stronger every day")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal)
                    .background(cardBackground)
                    .padding()
                
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
                        
                        // Growth Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
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
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.8), .blue],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                
                                BarMark(
                                    x: .value("Period", "Monthly"),
                                    y: .value("Growth", user.monthlySecondBrainGrowth * 100)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.8), .purple],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                
                                BarMark(
                                    x: .value("Period", "Yearly"),
                                    y: .value("Growth", user.yearlySecondBrainGrowth * 100)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.8), .purple],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                            }
                            .frame(height: 200)
                            .padding()
                        }
                        .padding()
                        .background(cardBackground)
                        .padding(.horizontal)
                        
                        // Streak Section
                        HStack(spacing: 40) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue.opacity(0.2), .blue.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 80, height: 80)
                                    
                                    Text("\(user.currentStreak)")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                                Text("Current Streak")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.purple.opacity(0.2), .purple.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 80, height: 80)
                                    
                                    Text("\(user.longestStreak)")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.purple, .blue],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                                Text("Longest Streak")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                        .background(cardBackground)
                        .padding(.horizontal)
                        
                        // Topics Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "tag")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
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
                        .background(cardBackground)
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
        }
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
    
    private var cardBackground: some View {
        Color(uiColor: .systemBackground)
            .opacity(0.8)
            .cornerRadius(20)
            .shadow(radius: 5)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Spacer()
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }
}

struct TopicBadge: View {
    let topic: String
    let count: Int
    
    private var cardBackground: some View {
        Color(uiColor: .systemBackground)
            .opacity(0.8)
            .cornerRadius(20)
            .shadow(radius: 5)
    }
    
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
        .background(cardBackground)
    }
}

#Preview {
    NavigationView {
        SecondBrainView()
    }
} 