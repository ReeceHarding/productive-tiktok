@preconcurrency
import AVFoundation

/// Asynchronous extension for AVAsset that loads specified keys before further processing.
/// This extension ensures that properties such as "playable" and "preferredTransform" are available,
/// preventing synchronous queries on not-yet-loaded properties which can block the main thread.
@available(iOS 15.0, *)
extension AVAsset {
    
    /// Loads the specified keys asynchronously and returns when they are ready to use
    /// - Parameter keys: The keys to load
    /// - Returns: Void if successful, throws an error if loading fails
    func loadValuesAsync(forKeys keys: [String]) async throws {
        if #available(iOS 16.0, *) {
            // Use new API for iOS 16+
            for key in keys {
                switch key {
                case "duration":
                    _ = try await load(.duration)
                case "tracks":
                    _ = try await load(.tracks)
                case "playable":
                    _ = try await load(.isPlayable)
                case "preferredTransform":
                    _ = try await load(.preferredTransform)
                default:
                    // For any other keys, use synchronous loading since they don't have AVAsyncProperty equivalents
                    var error: NSError?
                    let status = statusOfValue(forKey: key, error: &error)
                    if status != .loaded {
                        if let error = error {
                            throw error
                        } else {
                            throw NSError(domain: "AVAsset", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load key: \(key)"])
                        }
                    }
                }
            }
        } else {
            // Fallback for iOS 15
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                loadValuesAsynchronously(forKeys: keys) { [weak self] in
                    guard let self = self else {
                        continuation.resume(throwing: NSError(domain: "AVAsset", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self was deallocated"]))
                        return
                    }
                    
                    var error: NSError?
                    for key in keys {
                        let status = self.statusOfValue(forKey: key, error: &error)
                        if status != .loaded {
                            if let error = error {
                                continuation.resume(throwing: error)
                                return
                            } else {
                                continuation.resume(throwing: NSError(domain: "AVAsset", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load key: \(key)"]))
                                return
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
} 