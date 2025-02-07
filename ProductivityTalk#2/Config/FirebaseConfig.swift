import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

class FirebaseConfig {
    static let shared = FirebaseConfig()
    
    private init() {
        print("🔥 Firebase: Initializing configuration")
    }
    
    func configure() {
        // Configure Firebase
        FirebaseApp.configure()
        print("✅ Firebase: Successfully configured Firebase")
        
        // Enable Firestore debug logging for development
        #if DEBUG
        let db = Firestore.firestore()
        Firestore.enableLogging(true)
        print("🔍 Firebase: Enabled Firestore debug logging")
        
        // Configure cache settings
        let settings = db.settings
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: 100 * 1024 * 1024) // 100MB cache
        )
        settings.isSSLEnabled = true
        
        db.settings = settings
        print("✅ Firebase: Configured Firestore with persistence enabled")
        print("📦 Firebase: Cache size set to 100MB")
        #endif
    }
    
    // MARK: - Collection References
    
    var usersCollection: CollectionReference {
        let collection = Firestore.firestore().collection("users")
        print("📚 Firebase: Accessing users collection")
        return collection
    }
    
    var videosCollection: CollectionReference {
        let collection = Firestore.firestore().collection("videos")
        print("📚 Firebase: Accessing videos collection")
        return collection
    }
    
    func secondBrainCollection(for userId: String) -> CollectionReference {
        let collection = usersCollection.document(userId).collection("secondBrain")
        print("📚 Firebase: Accessing secondBrain collection for user: \(userId)")
        return collection
    }
    
    // MARK: - Storage References
    
    func videoStorageReference(userId: String, videoId: String) -> StorageReference {
        let ref = Storage.storage().reference().child("videos/\(userId)/\(videoId).mp4")
        print("📦 Firebase: Creating video storage reference - path: videos/\(userId)/\(videoId).mp4")
        return ref
    }
    
    func thumbnailStorageReference(userId: String, videoId: String) -> StorageReference {
        let ref = Storage.storage().reference().child("thumbnails/\(userId)/\(videoId).jpg")
        print("📦 Firebase: Creating thumbnail storage reference - path: thumbnails/\(userId)/\(videoId).jpg")
        return ref
    }
    
    func profilePictureStorageReference(userId: String) -> StorageReference {
        let ref = Storage.storage().reference().child("profile_pictures/\(userId).jpg")
        print("📦 Firebase: Creating profile picture storage reference - path: profile_pictures/\(userId).jpg")
        return ref
    }
} 