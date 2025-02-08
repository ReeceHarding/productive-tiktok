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
                LoadingView()
            } else if authManager.isAuthenticated {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .onAppear {
            // Check authentication state when view appears
            checkAuthState()
        }
    }
    
    private func checkAuthState() {
        // Add a small delay to allow Firebase to initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
        }
    }
}

// MARK: - Loading View
private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            Text("Loading...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @State private var showSignOutAlert = false
    @State private var isSigningOut = false
    @State private var signOutError: String?
    
    var body: some View {
        TabView {
            VideoFeedView()
                .tabItem {
                    Label("For You", systemImage: "play.circle.fill")
                }
            
            NavigationView {
                InsightsView()
            }
            .tabItem {
                Label("Second Brain", systemImage: "brain.head.profile")
            }
            
            VideoUploadView()
                .tabItem {
                    Label("Upload", systemImage: "video.badge.plus")
                }
            
            Text("Calendar")
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
            
            NavigationView {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
        }
        .overlay {
            if isSigningOut {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .overlay {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("Signing out...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showSignOutAlert = true }) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(isSigningOut)
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
        print("🚪 MainTabView: Starting sign out process")
        Task {
            do {
                try await AuthenticationManager.shared.signOut()
                print("✅ MainTabView: Successfully signed out")
            } catch {
                print("❌ MainTabView: Sign out error: \(error.localizedDescription)")
                signOutError = error.localizedDescription
            }
            isSigningOut = false
        }
    }
}

#Preview {
    ContentView()
}
