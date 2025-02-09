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
                    // For keys that don't have AVAsyncProperty equivalents,
                    // we need to use the older API even in iOS 16+
                    var error: NSError?
                    let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVKeyValueStatus, Error>) in
                        DispatchQueue.global().async {
                            let status = self.statusOfValue(forKey: key, error: &error)
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: status)
                            }
                        }
                    }
                    if status != .loaded {
                        throw NSError(domain: "AVAsset", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load key: \(key)"])
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