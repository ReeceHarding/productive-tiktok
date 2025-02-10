//
//  ContentView.swift
//  ProductivityTalk#2
//
//  Created by Reece Harding on 2/7/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                SharedLoadingView("Initializing...")
            } else if authManager.isAuthenticated {
                MainTabView()
            } else {
                SignUpView()
            }
        }
        .onAppear {
            LoggingService.debug("ContentView appeared, checking auth state", component: "Navigation")
            checkAuthState()
        }
    }
    
    private func checkAuthState() {
        LoggingService.debug("Starting auth state check", component: "Navigation")
        // Check if there's a current user immediately
        if Auth.auth().currentUser == nil {
            LoggingService.debug("No current user found, showing sign in", component: "Navigation")
            isLoading = false
            return
        }
        
        // Add a small delay to allow Firebase to initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            LoggingService.debug("Auth state check completed, isAuthenticated: \(self.authManager.isAuthenticated)", component: "Navigation")
            isLoading = false
        }
    }
}

// MARK: - Loading View
private struct LoadingView: View {
    let message: String
    
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
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.5)
                
                Text(message)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @ObservedObject private var authManager = AuthenticationManager.shared
    @State private var showSignOutAlert = false
    @State private var isSigningOut = false
    @State private var signOutError: String?
    
    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                SignInView()
            } else {
                TabView {
                    VideoFeedView()
                        .tabItem {
                            VStack {
                                Image(systemName: "play.circle.fill")
                                Text("For You")
                            }
                        }
                    
                    NavigationView {
                        InsightsView()
                    }
                    .tabItem {
                        VStack {
                            Image(systemName: "brain.head.profile")
                            Text("Second Brain")
                        }
                    }
                    
                    VideoUploadView()
                        .tabItem {
                            VStack {
                                Image(systemName: "video.badge.plus")
                                Text("Upload")
                            }
                        }
                    
                    Text("Calendar")
                        .tabItem {
                            VStack {
                                Image(systemName: "calendar")
                                Text("Calendar")
                            }
                        }
                    
                    NavigationView {
                        ProfileView()
                    }
                    .tabItem {
                        VStack {
                            Image(systemName: "person.circle")
                            Text("Profile")
                        }
                    }
                }
                .tint(.blue)
                .onAppear {
                    // Customize TabView appearance
                    let appearance = UITabBarAppearance()
                    appearance.configureWithOpaqueBackground()
                    appearance.backgroundColor = .systemBackground
                    
                    // Use this appearance for both normal and scrolling
                    UITabBar.appearance().standardAppearance = appearance
                    UITabBar.appearance().scrollEdgeAppearance = appearance
                }
                .overlay {
                    if isSigningOut {
                        Color.black.opacity(0.3)
                            .edgesIgnoringSafeArea(.all)
                            .overlay {
                                SharedLoadingView("Signing out...")
                            }
                    }
                }
            }
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOut()
            }
            .disabled(isSigningOut)
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Sign Out Error", isPresented: .init(
            get: { signOutError != nil },
            set: { if !$0 { signOutError = nil } }
        )) {
            Button("OK", role: .cancel) {
                signOutError = nil
            }
        } message: {
            if let error = signOutError {
                Text(error)
            }
        }
    }
    
    private func signOut() {
        isSigningOut = true
        LoggingService.debug("MainTabView: Starting sign out process", component: "Navigation")
        Task {
            do {
                try await AuthenticationManager.shared.signOut()
                LoggingService.success("MainTabView: Successfully signed out", component: "Navigation")
            } catch {
                LoggingService.error("MainTabView: Sign out error: \(error.localizedDescription)", component: "Navigation")
                signOutError = error.localizedDescription
            }
            isSigningOut = false
        }
    }
}

#Preview {
    ContentView()
}
