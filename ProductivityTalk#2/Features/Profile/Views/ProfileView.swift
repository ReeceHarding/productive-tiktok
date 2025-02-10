import SwiftUI
import PhotosUI

// MARK: - Profile View
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showSignOutAlert = false
    @State private var isRefreshing = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    // Haptic feedback generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private let gridColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
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
                
                if viewModel.isLoading && viewModel.user == nil {
                    SharedLoadingView("Loading profile...")
                } else {
                    ScrollView {
                        SharedRefreshControl(isRefreshing: $isRefreshing) {
                            Task {
                                await viewModel.loadUserData()
                                isRefreshing = false
                            }
                        }
                        
                        VStack(spacing: 24) {
                            // Profile Header
                            ProfileHeaderView(viewModel: viewModel)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color(.systemBackground).opacity(0.8))
                                        .shadow(radius: 5)
                                )
                                .padding()
                            
                            // Statistics Grid
                            if let user = viewModel.user {
                                LazyVGrid(columns: gridColumns, spacing: 16) {
                                    SharedStatisticCard(
                                        title: "Videos",
                                        value: "\(user.totalVideosUploaded)",
                                        icon: "video.fill",
                                        color: .blue
                                    )
                                    
                                    SharedStatisticCard(
                                        title: "Views",
                                        value: formatNumber(user.totalVideoViews),
                                        icon: "eye.fill",
                                        color: .green
                                    )
                                    
                                    SharedStatisticCard(
                                        title: "Second Brain",
                                        value: "\(user.totalSecondBrainSaves)",
                                        icon: "brain.head.profile",
                                        color: .purple
                                    )
                                    
                                    SharedStatisticCard(
                                        title: "Engagement",
                                        value: String(format: "%.1f%%", user.videoEngagementRate * 100),
                                        icon: "chart.line.uptrend.xyaxis",
                                        color: .orange
                                    )
                                }
                                .padding(.horizontal)
                                .transition(.opacity)
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.loadUserData()
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        impactGenerator.impactOccurred(intensity: 0.6)
                        showSignOutAlert = true
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("Sign out of your account")
                }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) {
                    notificationGenerator.notificationOccurred(.warning)
                }
                Button("Sign Out", role: .destructive) {
                    notificationGenerator.notificationOccurred(.success)
                    Task {
                        await viewModel.signOut()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .sheet(isPresented: $viewModel.showEditProfile) {
                EditProfileView(viewModel: viewModel)
            }
            .task {
                notificationGenerator.prepare()
                impactGenerator.prepare()
                await viewModel.loadUserData()
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    notificationGenerator.notificationOccurred(.error)
                    viewModel.clearError()
                }
            } message: {
                if let error = viewModel.error {
                    Text(error)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    notificationGenerator.prepare()
                    impactGenerator.prepare()
                }
            }
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

// MARK: - Profile Header View
struct ProfileHeaderView: View {
    @ObservedObject var viewModel: ProfileViewModel
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Picture
            PhotosPicker(selection: $viewModel.selectedItem,
                        matching: .images) {
                Group {
                    if let profilePicURL = viewModel.user?.profilePicURL,
                       let url = URL(string: profilePicURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        } placeholder: {
                            ProgressView()
                                .scaleEffect(1.5)
                        }
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                .shadow(radius: 3)
            }
            .accessibilityLabel("Profile picture. Tap to change")
            
            // User Info
            VStack(spacing: 8) {
                Text(viewModel.user?.username ?? "Username")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let bio = viewModel.user?.bio {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Button(action: {
                    impactGenerator.impactOccurred(intensity: 0.5)
                    viewModel.showEditProfile = true
                }) {
                    Label("Edit Profile", systemImage: "pencil")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    ProfileView()
} 