//
//  ProductivityTalk_2App.swift
//  ProductivityTalk#2
//
//  Created by Reece Harding on 2/7/25.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("📱 App: Application did finish launching")
        FirebaseConfig.shared.configure()
        return true
    }
}

@main
struct ProductivityTalk_2App: App {
    // Register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    init() {
        print("🚀 App: Initializing ProductivityTalk#2")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
