import Foundation
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

@MainActor
class ProfileViewModel: ObservableObject {
    @Published private(set) var user: AppUser?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var showEditProfile = false
    @Published var selectedItem: PhotosPickerItem? {
        didSet { Task { await loadTransferrable(from: selectedItem) } }
    }
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    init() {
        print("👤 ProfileViewModel: Initializing")
    }
    
    func clearError() {
        self.error = nil
    }
    
    @MainActor
    func loadUserData() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            LoggingService.error("No user ID found in UserDefaults", component: "Profile")
            self.error = "User not logged in"
            return
        }
        
        // Don't reload if already loading
        guard !isLoading else {
            LoggingService.debug("Already loading user data, skipping", component: "Profile")
            return
        }
        
        isLoading = true
        LoggingService.debug("Loading user data for ID: \(userId)", component: "Profile")
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if !document.exists {
                LoggingService.error("User document does not exist for ID: \(userId)", component: "Profile")
                self.error = "User profile not found"
                self.user = nil
                isLoading = false
                return
            }
            
            guard let data = document.data() else {
                LoggingService.error("Document exists but has no data for ID: \(userId)", component: "Profile")
                self.error = "User profile is empty"
                self.user = nil
                isLoading = false
                return
            }
            
            if let appUser = AppUser(document: document) {
                self.user = appUser
                self.error = nil
                LoggingService.success("Successfully loaded user data for ID: \(userId)", component: "Profile")
            } else {
                LoggingService.error("Failed to parse user data for ID: \(userId)", component: "Profile")
                self.error = "Could not load user profile"
                self.user = nil
            }
        } catch {
            LoggingService.error("Error loading user data: \(error.localizedDescription)", component: "Profile")
            self.error = "Failed to load profile: \(error.localizedDescription)"
            self.user = nil
        }
        
        isLoading = false
    }
    
    @MainActor
    func updateProfile(username: String, bio: String?) async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            self.error = "User not logged in"
            return
        }
        
        print("✏️ ProfileViewModel: Updating profile for user: \(userId)")
        
        do {
            let updateData: [String: Any] = [
                "username": username,
                "bio": bio as Any
            ]
            
            try await db.collection("users").document(userId).updateData(updateData)
            print("✅ ProfileViewModel: Successfully updated profile")
            await loadUserData()
        } catch {
            print("❌ ProfileViewModel: Error updating profile: \(error.localizedDescription)")
            self.error = "Failed to update profile: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func loadTransferrable(from imageSelection: PhotosPickerItem?) async {
        guard let imageSelection else { return }
        
        do {
            if let data = try await imageSelection.loadTransferable(type: Data.self) {
                await uploadProfileImage(data)
            }
        } catch {
            print("❌ ProfileViewModel: Failed to load image data: \(error.localizedDescription)")
            self.error = "Failed to load image"
        }
    }
    
    @MainActor
    private func uploadProfileImage(_ imageData: Data) async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            self.error = "User not logged in"
            return
        }
        
        print("🖼️ ProfileViewModel: Uploading profile image for user: \(userId)")
        
        do {
            let storageRef = storage.reference().child("profile_pictures/\(userId).jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            
            try await db.collection("users").document(userId).updateData([
                "profilePicURL": downloadURL.absoluteString
            ])
            
            print("✅ ProfileViewModel: Successfully uploaded profile image")
            await loadUserData()
        } catch {
            print("❌ ProfileViewModel: Error uploading profile image: \(error.localizedDescription)")
            self.error = "Failed to upload profile image"
        }
    }
    
    @MainActor
    func signOut() async {
        print("🚪 ProfileViewModel: Attempting to sign out user")
        do {
            try await AuthenticationManager.shared.signOut()
            print("✅ ProfileViewModel: Successfully signed out user")
            self.user = nil
        } catch {
            print("❌ ProfileViewModel: Error signing out: \(error.localizedDescription)")
            self.error = "Failed to sign out: \(error.localizedDescription)"
        }
    }
} 