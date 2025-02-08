import Foundation
import FirebaseFirestore
import Combine

@MainActor
class ProfileViewModel: ObservableObject {
    @Published private(set) var user: AppUser?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var showImagePicker = false
    @Published var showEditProfile = false
    
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("👤 ProfileViewModel: Initializing")
    }
    
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
    
    func updateProfile(username: String, email: String, bio: String?) async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        
        print("✏️ ProfileViewModel: Updating profile for user: \(userId)")
        
        do {
            var updateData: [String: Any] = [
                "username": username,
                "email": email
            ]
            
            if let bio = bio {
                updateData["bio"] = bio
            }
            
            try await db.collection("users").document(userId).updateData(updateData)
            print("✅ ProfileViewModel: Successfully updated profile")
            await loadUserData()
        } catch {
            print("❌ ProfileViewModel: Error updating profile: \(error.localizedDescription)")
            self.error = "Failed to update profile: \(error.localizedDescription)"
        }
    }
    
    func updateProfilePicture(imageURL: String) async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        
        print("🖼️ ProfileViewModel: Updating profile picture for user: \(userId)")
        
        do {
            try await db.collection("users").document(userId).updateData([
                "profilePicURL": imageURL
            ])
            print("✅ ProfileViewModel: Successfully updated profile picture")
            await loadUserData()
        } catch {
            print("❌ ProfileViewModel: Error updating profile picture: \(error.localizedDescription)")
            self.error = "Failed to update profile picture: \(error.localizedDescription)"
        }
    }
    
    func formatNumber(_ number: Int) -> String {
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