//
//  ContentView.swift
//  ProductivityTalk#2
//
//  Created by Reece Harding on 2/7/25.
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                TabView {
                    VideoFeedView()
                        .tabItem {
                            Label("For You", systemImage: "play.circle.fill")
                        }
                    
                    Text("Second Brain")
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
                    
                    Text("Profile")
                        .tabItem {
                            Label("Profile", systemImage: "person.circle")
                        }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: signOut) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            } else {
                SignInView()
            }
        }
    }
    
    private func signOut() {
        Task {
            do {
                try Auth.auth().signOut()
            } catch {
                print("❌ Error signing out: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
}
