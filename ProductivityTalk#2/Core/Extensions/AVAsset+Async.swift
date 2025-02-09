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
                default:
                    // For other keys, fall back to the old API
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        loadValuesAsynchronously(forKeys: [key]) { [weak self] in
                            guard let self = self else {
                                continuation.resume(throwing: NSError(domain: "AVAsset", code: -1))
                                return
                            }
                            var error: NSError?
                            let status = self.statusOfValue(forKey: key, error: &error)
                            if status == .failed {
                                continuation.resume(throwing: error ?? NSError(domain: "AVAsset", code: -1))
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        } else {
            // Fallback for older iOS versions
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.loadValuesAsynchronously(forKeys: keys) { [weak self] in
                    guard let self = self else {
                        continuation.resume(throwing: NSError(domain: "AVAsset", code: -1, userInfo: [NSLocalizedDescriptionKey: "Asset was deallocated"]))
                        return
                    }
                    
                    var error: NSError?
                    for key in keys {
                        let status = self.statusOfValue(forKey: key, error: &error)
                        if status == .failed {
                            continuation.resume(throwing: error ?? NSError(domain: "AVAsset", code: -1))
                            return
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
} 