import AVFoundation

/// Asynchronous extension for AVAsset that loads specified keys before further processing.
/// This extension ensures that properties such as "playable" and "preferredTransform" are available,
/// preventing synchronous queries on not-yet-loaded properties which can block the main thread.
extension AVAsset {
    
    /// Asynchronously loads the given keys and throws an error if any key fails to load.
    /// - Parameter keys: An array of key strings that need to be loaded.
    func loadValuesAsync(keys: [String]) async throws {
        print("⏳ [AVAsset+Async] Starting to load keys: \(keys)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.loadValuesAsynchronously(forKeys: keys) {
                for key in keys {
                    var error: NSError?
                    let status = self.statusOfValue(forKey: key, error: &error)
                    if status != .loaded {
                        let err = error ?? NSError(domain: "AVAssetErrorDomain", code: -1, 
                            userInfo: [NSLocalizedDescriptionKey: "Failed to load key: \(key)"])
                        print("🔴 [AVAsset+Async] Error loading key '\(key)': \(err.localizedDescription)")
                        continuation.resume(throwing: err)
                        return
                    } else {
                        print("🟢 [AVAsset+Async] Key '\(key)' loaded successfully.")
                    }
                }
                print("✅ [AVAsset+Async] All keys loaded successfully.")
                continuation.resume()
            }
        }
    }
} 