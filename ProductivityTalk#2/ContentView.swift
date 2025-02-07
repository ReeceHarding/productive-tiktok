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
                NavigationView {
                    VStack {
                        Text("Welcome! You're signed in.")
                            .font(.title)
                            .padding()
                        
                        // Add your main app content here
                        
                        Spacer()
                    }
                    .navigationTitle("Home")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            VideoUploadButton()
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: signOut) {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
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
