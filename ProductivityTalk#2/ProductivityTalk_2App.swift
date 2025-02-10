//
//  ProductivityTalk_2App.swift
//  ProductivityTalk#2
//
//  Created by Reece Harding on 2/7/25.
//

import SwiftUI
import FirebaseCore
import UIKit
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        LoggingService.info("Application launching", component: "AppDelegate")
        
        // Configure Firebase
        FirebaseConfig.shared.configure()
        LoggingService.success("Application launch completed", component: "AppDelegate")
        
        return true
    }
    
    func application(_ app: UIApplication,
                    open url: URL,
                    options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        LoggingService.debug("Handling URL: \(url.absoluteString)", component: "AppDelegate")
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct ProductivityTalk_2App: App {
    // Register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    init() {
        LoggingService.info("Initializing ProductivityTalk#2", component: "App")
        
        #if DEBUG
        LoggingService.debug("Running in DEBUG configuration", component: "App")
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    LoggingService.success("Main ContentView appeared", component: "App")
                }
        }
    }
}
