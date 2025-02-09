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
            print("❌ ProfileViewModel: No user ID found")
            self.error = "User not logged in"
            return
        }
        
        isLoading = true
        print("📥 ProfileViewModel: Loading user data for ID: \(userId)")
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let user = AppUser(document: document) {
                self.user = user
                print("✅ ProfileViewModel: Successfully loaded user data")
            } else {
                print("❌ ProfileViewModel: Failed to parse user data")
                self.error = "Failed to load user data"
            }
        } catch {
            print("❌ ProfileViewModel: Error loading user data: \(error.localizedDescription)")
            self.error = "Failed to load user data: \(error.localizedDescription)"
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