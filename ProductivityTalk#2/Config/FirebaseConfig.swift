import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

class FirebaseConfig {
    static let shared = FirebaseConfig()
    
    private init() {
        LoggingService.firebase("Initializing Firebase configuration", component: "Config")
    }
    
    func configure() {
        LoggingService.integration("Starting Firebase configuration", component: "Config")
        
        // Configure Firebase
        FirebaseApp.configure()
        LoggingService.success("Firebase core configuration successful", component: "Config")
        
        // Enable Firestore debug logging for development
        #if DEBUG
        let db = Firestore.firestore()
        Firestore.enableLogging(true)
        LoggingService.debug("Enabled Firestore debug logging", component: "Config")
        
        // Configure cache settings
        let settings = db.settings
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: 100 * 1024 * 1024) // 100MB cache
        )
        settings.isSSLEnabled = true
        
        db.settings = settings
        LoggingService.success("Configured Firestore with persistence (100MB cache)", component: "Config")
        #endif
        
        LoggingService.success("Firebase configuration completed successfully", component: "Config")
    }
    
    // MARK: - Collection References
    
    var usersCollection: CollectionReference {
        let collection = Firestore.firestore().collection("users")
        LoggingService.firebase("Accessing users collection", component: "Config")
        return collection
    }
    
    var videosCollection: CollectionReference {
        let collection = Firestore.firestore().collection("videos")
        LoggingService.firebase("Accessing videos collection", component: "Config")
        return collection
    }
    
    func secondBrainCollection(for userId: String) -> CollectionReference {
        let collection = usersCollection.document(userId).collection("secondBrain")
        LoggingService.firebase("Accessing secondBrain collection for user: \(userId)", component: "Config")
        return collection
    }
    
    // MARK: - Storage References
    
    func videoStorageReference(userId: String, videoId: String) -> StorageReference {
        let ref = Storage.storage().reference().child("videos/\(userId)/\(videoId).mp4")
        LoggingService.storage("Creating video storage reference - path: videos/\(userId)/\(videoId).mp4", component: "Config")
        return ref
    }
    
    func thumbnailStorageReference(userId: String, videoId: String) -> StorageReference {
        let ref = Storage.storage().reference().child("thumbnails/\(userId)/\(videoId).jpg")
        LoggingService.storage("Creating thumbnail storage reference - path: thumbnails/\(userId)/\(videoId).jpg", component: "Config")
        return ref
    }
    
    func profilePictureStorageReference(userId: String) -> StorageReference {
        let ref = Storage.storage().reference().child("profile_pictures/\(userId).jpg")
        LoggingService.storage("Creating profile picture storage reference - path: profile_pictures/\(userId).jpg", component: "Config")
        return ref
    }
    
    // MARK: - Error Handling
    
    func handleFirebaseError(_ error: Error, component: String) {
        LoggingService.error("Firebase error: \(error.localizedDescription)", component: component)
        if let nsError = error as NSError? {
            LoggingService.debug("Error details - Domain: \(nsError.domain), Code: \(nsError.code)", component: component)
        }
    }
} 