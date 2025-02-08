import Foundation
import FirebaseAuth
import FirebaseFirestore

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
    private var activeListeners: [ListenerRegistration] = []  // Track active listeners
    
    deinit {
        print("🔐 Auth: Cleaning up AuthenticationManager")
        authStateHandle = nil
        activeListeners.forEach { $0.remove() }
        activeListeners.removeAll()
    }
    
    private init() {
        print("🔐 Auth: Initializing AuthenticationManager")
        setupAuthStateHandler()
    }
    
    private func setupAuthStateHandler() {
        print("🔐 Auth: Setting up authentication state handler")
        authStateHandle = auth.addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            self.currentUser = user
            self.isAuthenticated = user != nil
            
            if let user = user {
                print("✅ Auth: User authenticated - ID: \(user.uid)")
                UserDefaults.standard.set(user.uid, forKey: "userId")
                Task {
                    await self.fetchAppUser(uid: user.uid)
                }
            } else {
                print("ℹ️ Auth: No authenticated user")
                UserDefaults.standard.removeObject(forKey: "userId")
                self.appUser = nil
            }
        }
    }
    
    private func fetchAppUser(uid: String) async {
        print("🔍 Auth: Fetching app user data for UID: \(uid)")
        do {
            // Remove any existing listener for user document
            activeListeners.forEach { $0.remove() }
            activeListeners.removeAll()
            
            let document = try await firestore.collection("users").document(uid).getDocument()
            if let appUser = AppUser(document: document) {
                self.appUser = appUser
                print("✅ Auth: Successfully fetched app user data")
            } else {
                print("❌ Auth: Failed to parse app user data")
                self.authError = .unknown(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse user data"]))
            }
        } catch {
            print("❌ Auth: Failed to fetch app user data: \(error.localizedDescription)")
            self.authError = .unknown(error)
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
            print("✅ Auth: Sign up completed successfully - redirecting to video feed")
            
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
        print("📝 Auth: Creating user document for UID: \(uid)")
        let userData: [String: Any] = [
            "username": username,
            "email": email,
            "createdAt": Timestamp(date: Date()),
            "profilePicURL": "",
            "bio": "",
            // Initialize all required statistics
            "totalVideosUploaded": 0,
            "totalVideoViews": 0,
            "totalVideoLikes": 0,
            "totalVideoShares": 0,
            "totalVideoSaves": 0,
            "totalSecondBrainSaves": 0,
            "currentStreak": 0,
            "longestStreak": 0,
            "lastActiveDate": Timestamp(date: Date()),
            "topicDistribution": [:] as [String: Int]
        ]
        
        try await firestore.collection("users").document(uid).setData(userData)
        print("✅ Auth: Successfully created user document with initial statistics")
    }
    
    func signIn(email: String, password: String) async throws {
        print("🔐 Auth: Attempting to sign in user with email: \(email)")
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            print("✅ Auth: Successfully signed in user: \(result.user.uid)")
        } catch let error as NSError {
            print("❌ Auth: Sign in failed with error: \(error.localizedDescription)")
            switch error.code {
            case AuthErrorCode.wrongPassword.rawValue:
                throw AuthError.invalidCredentials
            case AuthErrorCode.userNotFound.rawValue:
                throw AuthError.userNotFound
            case AuthErrorCode.networkError.rawValue:
                throw AuthError.networkError
            default:
                throw AuthError.unknown(error)
            }
        }
    }
    
    func signOut() async throws {
        print("🔐 Auth: Attempting to sign out user")
        do {
            // Disable any new queries
            firestore.settings = Firestore.firestore().settings
            print("✅ Auth: Disabled new Firestore queries")
            
            // Remove all Firestore listeners first
            activeListeners.forEach { $0.remove() }
            activeListeners.removeAll()
            print("✅ Auth: Removed all Firestore listeners")
            
            // Remove auth state listener
            if let handle = authStateHandle {
                auth.removeStateDidChangeListener(handle)
                authStateHandle = nil
                print("✅ Auth: Removed auth state listener")
            }
            
            // Clear local state
            self.appUser = nil
            self.isAuthenticated = false
            self.currentUser = nil
            UserDefaults.standard.removeObject(forKey: "userId")
            print("✅ Auth: Cleared local state")
            
            // Sign out from Firebase Auth
            try auth.signOut()
            print("✅ Auth: Successfully signed out user")
            
            // Wait a bit to ensure all queries are completed
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Terminate Firestore instance
            try await firestore.terminate()
            print("✅ Auth: Terminated Firestore")
            
            // Wait for termination to complete
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Clear Firestore persistence
            try await firestore.clearPersistence()
            print("✅ Auth: Cleared Firestore persistence")
            
            // Re-setup auth state handler for next sign in
            setupAuthStateHandler()
            print("✅ Auth: Re-initialized auth state handler")
            
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
        } catch let error as NSError {
            print("❌ Auth: Password reset failed with error: \(error.localizedDescription)")
            switch error.code {
            case AuthErrorCode.invalidEmail.rawValue:
                throw AuthError.invalidEmail
            case AuthErrorCode.userNotFound.rawValue:
                throw AuthError.userNotFound
            case AuthErrorCode.networkError.rawValue:
                throw AuthError.networkError
            default:
                throw AuthError.unknown(error)
            }
        }
    }
} 