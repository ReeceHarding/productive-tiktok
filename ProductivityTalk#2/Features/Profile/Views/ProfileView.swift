import SwiftUI
import PhotosUI
import UIKit

// MARK: - Profile View
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showSignOutAlert = false
    @State private var isRefreshing = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var authManager = AuthenticationManager.shared
    
    // Haptic feedback generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    var body: some View {
        NavigationView {
            Group {
                if !authManager.isAuthenticated {
                    UnauthenticatedProfileView(showSignInView: showSignInView)
                } else {
                    AuthenticatedProfileView(
                        viewModel: viewModel,
                        isRefreshing: $isRefreshing,
                        showSignOutAlert: $showSignOutAlert
                    )
                }
            }
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            signOutAlert
        }
        .onAppear {
            LoggingService.debug("ProfileView appeared, isAuthenticated: \(authManager.isAuthenticated)", component: "Profile")
            if authManager.isAuthenticated {
                Task {
                    await viewModel.loadUserData()
                }
            }
        }
    }
    
    private func showSignInView() {
        impactGenerator.impactOccurred(intensity: 0.5)
        // Handle navigation to sign in
    }
    
    private var signOutAlert: some View {
        Group {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task {
                    do {
                        try await AuthenticationManager.shared.signOut()
                    } catch {
                        LoggingService.error("Error signing out: \(error)", component: "Profile")
                    }
                }
            }
        }
    }
}

// MARK: - Unauthenticated Profile View
private struct UnauthenticatedProfileView: View {
    let showSignInView: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Please sign in to view your profile")
                .font(.headline)
                .foregroundColor(.secondary)
            
            NavigationLink(destination: SignInView()) {
                Text("Sign In")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Authenticated Profile View
private struct AuthenticatedProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var isRefreshing: Bool
    @Binding var showSignOutAlert: Bool
    
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            if viewModel.isLoading && viewModel.user == nil {
                SharedLoadingView("Loading profile...")
            } else {
                mainContent
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                signOutButton
            }
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.blue.opacity(0.3),
                Color.purple.opacity(0.3)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var mainContent: some View {
        ScrollView {
            SharedRefreshControl(isRefreshing: $isRefreshing) {
                Task {
                    await viewModel.loadUserData()
                    isRefreshing = false
                }
            }
            
            VStack(spacing: 24) {
                ProfileHeaderView(viewModel: viewModel)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground).opacity(0.8))
                            .shadow(radius: 5)
                    )
                    .padding()
                
                if let user = viewModel.user {
                    statisticsGrid(for: user)
                }
            }
        }
        .refreshable {
            isRefreshing = true
            await viewModel.loadUserData()
            isRefreshing = false
        }
    }
    
    private func statisticsGrid(for user: AppUser) -> some View {
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
    
    private var signOutButton: some View {
        Button(action: {
            impactGenerator.impactOccurred(intensity: 0.6)
            showSignOutAlert = true
        }) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .foregroundColor(.primary)
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