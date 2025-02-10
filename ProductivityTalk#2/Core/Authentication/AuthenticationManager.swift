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
    private var firestore: Firestore!
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var activeListeners: [ListenerRegistration] = []
    
    deinit {
        LoggingService.authentication("Cleaning up AuthenticationManager", component: "Auth")
        authStateHandle = nil
        activeListeners.forEach { $0.remove() }
        activeListeners.removeAll()
    }
    
    private init() {
        LoggingService.authentication("Initializing AuthenticationManager", component: "Auth")
        initializeFirestore()
        setupAuthStateHandler()
    }
    
    private func initializeFirestore() {
        LoggingService.authentication("Initializing Firestore", component: "Auth")
        firestore = Firestore.firestore()
    }
    
    private func setupAuthStateHandler() {
        LoggingService.authentication("Setting up authentication state handler", component: "Auth")
        authStateHandle = auth.addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.currentUser = user
                self.isAuthenticated = user != nil
                
                if let user = user {
                    LoggingService.success("User authenticated - ID: \(user.uid)", component: "Auth")
                    UserDefaults.standard.set(user.uid, forKey: "userId")
                    await self.fetchAppUser(uid: user.uid)
                } else {
                    LoggingService.info("No authenticated user", component: "Auth")
                    UserDefaults.standard.removeObject(forKey: "userId")
                    self.appUser = nil
                }
            }
        }
    }
    
    private func fetchAppUser(uid: String) async {
        LoggingService.debug("Fetching app user data for UID: \(uid)", component: "Auth")
        do {
            // Remove any existing listener for user document
            activeListeners.forEach { $0.remove() }
            activeListeners.removeAll()
            
            let document = try await firestore.collection("users").document(uid).getDocument()
            
            if !document.exists {
                LoggingService.debug("User document does not exist, creating default document", component: "Auth")
                // Get email from Auth user
                let email = Auth.auth().currentUser?.email ?? ""
                try await createUserDocument(uid: uid, email: email, username: "User\(String(uid.prefix(4)))")
                // Fetch the newly created document
                let newDocument = try await firestore.collection("users").document(uid).getDocument()
                if let appUser = AppUser(document: newDocument) {
                    await MainActor.run {
                        self.appUser = appUser
                    }
                    LoggingService.success("Successfully created and fetched new user document", component: "Auth")
                } else {
                    LoggingService.error("Failed to parse newly created user document", component: "Auth")
                    await MainActor.run {
                        self.authError = .unknown(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse user data"]))
                    }
                }
                return
            }
            
            if let appUser = AppUser(document: document) {
                await MainActor.run {
                    self.appUser = appUser
                }
                LoggingService.success("Successfully fetched app user data", component: "Auth")
            } else {
                LoggingService.error("Failed to parse app user data", component: "Auth")
                await MainActor.run {
                    self.authError = .unknown(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse user data"]))
                }
            }
        } catch {
            LoggingService.error("Failed to fetch app user data: \(error.localizedDescription)", component: "Auth")
            await MainActor.run {
                self.authError = .unknown(error)
            }
        }
    }
    
    func signUp(email: String, password: String, username: String) async throws {
        LoggingService.authentication("Attempting to create new user with email: \(email)", component: "Auth")
        do {
            // Validate input
            guard !username.isEmpty else {
                LoggingService.failure("Username is empty", component: "Auth")
                throw AuthError.invalidCredentials
            }
            
            // Create Firebase Auth user
            let authResult = try await auth.createUser(withEmail: email, password: password)
            let uid = authResult.user.uid
            LoggingService.success("Successfully created Firebase Auth user with ID: \(uid)", component: "Auth")
            
            // Create user document in Firestore
            try await createUserDocument(uid: uid, email: email, username: username)
            LoggingService.success("Sign up completed successfully - redirecting to video feed", component: "Auth")
            
        } catch let error as NSError {
            LoggingService.error("Sign up failed with error: \(error.localizedDescription)", component: "Auth")
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
        LoggingService.authentication("Creating user document for UID: \(uid)", component: "Auth")
        let userData: [String: Any] = [
            "username": username,
            "email": email,
            "createdAt": Timestamp(date: Date()),
            "profilePicURL": "",
            "bio": "",
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
        LoggingService.success("Successfully created user document with initial statistics", component: "Auth")
    }
    
    func signIn(email: String, password: String) async throws {
        LoggingService.authentication("Attempting to sign in user with email: \(email)", component: "Auth")
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            LoggingService.success("Successfully signed in user: \(result.user.uid)", component: "Auth")
        } catch let error as NSError {
            LoggingService.error("Sign in failed with error: \(error.localizedDescription)", component: "Auth")
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
        LoggingService.authentication("Attempting to sign out user", component: "Auth")
        do {
            // Remove all Firestore listeners first
            activeListeners.forEach { $0.remove() }
            activeListeners.removeAll()
            LoggingService.success("Removed all Firestore listeners", component: "Auth")
            
            // Remove auth state listener
            if let handle = authStateHandle {
                auth.removeStateDidChangeListener(handle)
                authStateHandle = nil
                LoggingService.success("Removed auth state listener", component: "Auth")
            }
            
            // Clear local state on main actor
            await MainActor.run {
                self.appUser = nil
                self.isAuthenticated = false
                self.currentUser = nil
            }
            UserDefaults.standard.removeObject(forKey: "userId")
            LoggingService.success("Cleared local state", component: "Auth")
            
            // Sign out from Firebase Auth
            try auth.signOut()
            LoggingService.success("Successfully signed out user", component: "Auth")
            
            // Wait a bit to ensure all queries are completed
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Terminate Firestore instance
            try await firestore.terminate()
            LoggingService.success("Terminated Firestore", component: "Auth")
            
            // Wait for termination to complete
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Clear Firestore persistence
            try await firestore.clearPersistence()
            LoggingService.success("Cleared Firestore persistence", component: "Auth")
            
            // Reinitialize Firestore
            initializeFirestore()
            LoggingService.success("Reinitialized Firestore", component: "Auth")
            
            // Re-setup auth state handler for next sign in
            setupAuthStateHandler()
            LoggingService.success("Re-initialized auth state handler", component: "Auth")
        } catch {
            LoggingService.error("Failed to sign out: \(error.localizedDescription)", component: "Auth")
            throw AuthError.unknown(error)
        }
    }
    
    func resetPassword(email: String) async throws {
        LoggingService.authentication("Attempting to send password reset email to: \(email)", component: "Auth")
        do {
            try await auth.sendPasswordReset(withEmail: email)
            LoggingService.success("Successfully sent password reset email", component: "Auth")
        } catch let error as NSError {
            LoggingService.error("Password reset failed with error: \(error.localizedDescription)", component: "Auth")
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