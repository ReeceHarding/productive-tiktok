import AVFoundation

/// Asynchronous extension for AVAsset that loads specified keys before further processing.
/// This extension ensures that properties such as "playable" and "preferredTransform" are available,
/// preventing synchronous queries on not-yet-loaded properties which can block the main thread.
@available(iOS 15.0, *)
extension AVAsset {
    
    /// Loads the specified keys asynchronously and returns when they are ready to use
    /// - Parameter keys: The keys to load
    /// - Returns: Void if successful, throws an error if loading fails
    func loadValuesAsync(keys: [String]) async throws {
        print("Loading keys asynchronously: \(keys)")
        
        return try await withCheckedThrowingContinuation { continuation in
            print("Using continuation-based approach for key loading")
            
            self.loadValuesAsynchronously(forKeys: keys) { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "AVAssetError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self was deallocated"]))
                    return
                }
                
                var error: NSError?
                for key in keys {
                    let status = self.statusOfValue(forKey: key, error: &error)
                    print("Status for key \(key): \(status.rawValue)")
                    
                    if status == .failed {
                        print("Failed to load key: \(key), error: \(String(describing: error))")
                        continuation.resume(throwing: error ?? NSError(domain: "AVAssetError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load key: \(key)"]))
                        return
                    }
                    if status != .loaded {
                        print("Unexpected status for key: \(key), status: \(status)")
                        continuation.resume(throwing: NSError(domain: "AVAssetError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected status for key: \(key)"]))
                        return
                    }
                    print("Successfully loaded key: \(key)")
                }
                
                print("Successfully loaded all keys")
                continuation.resume(returning: ())
            }
        }
    }
} 