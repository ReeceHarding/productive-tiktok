import SwiftUI
import FirebaseFirestore

// Re-export Firebase types needed by the Video feature
@_exported import class FirebaseFirestore.DocumentSnapshot
@_exported import class FirebaseFirestore.Timestamp

// No typealiases needed since we're in the same module 