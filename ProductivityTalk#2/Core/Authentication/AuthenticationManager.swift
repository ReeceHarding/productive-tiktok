import Foundation
import FirebaseAuth
import FirebaseFirestore

// Import AppUser from the same target
import struct ProductivityTalk_2.AppUser

enum AuthError: Error {
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case invalidCredentials
    case userNotFound
    case networkError
    case unknown(Error)
    
    var description: String {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address"
        case .weakPassword:
            return "Password must be at least 6 characters long"
        case .emailAlreadyInUse:
            return "This email is already registered"
        case .invalidCredentials:
            return "Invalid email or password"
        case .userNotFound:
            return "No account found with this email"
        case .networkError:
            return "Network error. Please check your connection"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published private(set) var currentUser: FirebaseAuth.User?
    @Published private(set) var appUser: AppUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var authError: AuthError?
    
    private let auth = Auth.auth()
    private let firestore = Firestore.firestore()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    private init() {
        print("🔐 Auth: Initializing AuthenticationManager")
        setupAuthStateHandler()
    }
    
    private func setupAuthStateHandler() {
        authStateHandle = auth.addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            self.currentUser = user
            self.isAuthenticated = user != nil
            
            if let user = user {
                print("🔐 Auth: Authentication state changed - User: \(user.uid)")
                UserDefaults.standard.set(user.uid, forKey: "userId")
                Task {
                    await self.fetchAppUser(uid: user.uid)
                }
            } else {
                print("🔐 Auth: User signed out")
                UserDefaults.standard.removeObject(forKey: "userId")
                self.appUser = .none
            }
        }
    }
    
    private func fetchAppUser(uid: String) async {
        print("🔐 Auth: Fetching app user data for UID: \(uid)")
        do {
            let document = try await firestore.collection("users").document(uid).getDocument()
            if let appUser = AppUser(document: document) {
                self.appUser = appUser
                print("✅ Auth: Successfully fetched app user data")
            } else {
                print("❌ Auth: Failed to parse app user data")
            }
        } catch {
            print("❌ Auth: Failed to fetch app user data: \(error.localizedDescription)")
        }
    }
    
    func signUp(email: String, password: String, username: String) async throws {
        print("🔐 Auth: Attempting to create new user with email: \(email)")
        do {
            // Validate input
            guard !username.isEmpty else {
                print("❌ Auth: Username is empty")
                throw AuthError.invalidCredentials
            }
            
            // Create Firebase Auth user
            let authResult = try await auth.createUser(withEmail: email, password: password)
            let uid = authResult.user.uid
            print("✅ Auth: Successfully created Firebase Auth user with ID: \(uid)")
            
            // Create user document in Firestore
            try await createUserDocument(uid: uid, email: email, username: username)
            print("✅ Auth: Successfully created user document in Firestore")
            
            // Send email verification
            try await authResult.user.sendEmailVerification()
            print("✅ Auth: Sent email verification")
            
        } catch let error as NSError {
            print("❌ Auth: Sign up failed with error: \(error.localizedDescription)")
            switch error.code {
            case AuthErrorCode.invalidEmail.rawValue:
                throw AuthError.invalidEmail
            case AuthErrorCode.weakPassword.rawValue:
                throw AuthError.weakPassword
            case AuthErrorCode.emailAlreadyInUse.rawValue:
                throw AuthError.emailAlreadyInUse
            default:
                throw AuthError.unknown(error)
            }
        }
    }
    
    private func createUserDocument(uid: String, email: String, username: String) async throws {
        print("🔐 Auth: Creating user document for UID: \(uid)")
        let userData: [String: Any] = [
            "username": username,
            "email": email,
            "createdAt": Timestamp(date: Date()),
            "profilePicURL": "",
            "bio": ""
        ]
        
        try await firestore.collection("users").document(uid).setData(userData)
    }
    
    func signIn(email: String, password: String) async throws {
        print("🔐 Auth: Attempting to sign in user with email: \(email)")
        do {
            try await auth.signIn(withEmail: email, password: password)
            print("✅ Auth: Successfully signed in user")
        } catch let error as NSError {
            print("❌ Auth: Sign in failed with error: \(error.localizedDescription)")
            switch error.code {
            case AuthErrorCode.wrongPassword.rawValue:
                throw AuthError.invalidCredentials
            case AuthErrorCode.userNotFound.rawValue:
                throw AuthError.userNotFound
            default:
                throw AuthError.unknown(error)
            }
        }
    }
    
    func signOut() throws {
        print("🔐 Auth: Attempting to sign out user")
        do {
            try auth.signOut()
            print("✅ Auth: Successfully signed out user")
        } catch {
            print("❌ Auth: Sign out failed with error: \(error.localizedDescription)")
            throw AuthError.unknown(error)
        }
    }
    
    func resetPassword(email: String) async throws {
        print("🔐 Auth: Attempting to send password reset email to: \(email)")
        do {
            try await auth.sendPasswordReset(withEmail: email)
            print("✅ Auth: Successfully sent password reset email")
        } catch {
            print("❌ Auth: Password reset failed with error: \(error.localizedDescription)")
            throw AuthError.unknown(error)
        }
    }
} 