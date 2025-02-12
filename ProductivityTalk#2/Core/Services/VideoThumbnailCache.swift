import SwiftUI
import Combine

/// A simple in-memory and disk-based cache for video thumbnails.
/// Integrates a blur-up technique by returning a low-resolution image first, then the full-res once loaded.
/// In a production environment, this can be extended with better eviction policies & offline storage.
actor VideoThumbnailCache {
    
    static let shared = VideoThumbnailCache()
    
    private var memoryCache: [URL: UIImage] = [:]
    private var subscriptions: [URL: AnyCancellable] = [:]
    
    private init() {}
    
    /// Loads a thumbnail with a blur-up approach:
    /// 1) Returns a blurred placeholder (if available)
    /// 2) Fetches or loads the higher-res version
    /// 3) Caches the result in memory
    func loadThumbnail(from url: URL, completion: @escaping (UIImage?) -> Void) {
        // If in memory, return immediately
        if let cached = memoryCache[url] {
            completion(cached)
            return
        }
        
        // Provide a blurred placeholder if a smaller version is available on disk
        Task.detached {
            let placeholder = await self.generateBlurPlaceholder(for: url)
            await MainActor.run {
                completion(placeholder)
            }
        }
        
        // Fetch final image
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        let publisher = URLSession.shared.dataTaskPublisher(for: request)
            .map { UIImage(data: $0.data) }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
        
        let cancellable = publisher.sink { [weak self] image in
            guard let self = self, let thumbnail = image else {
                completion(nil)
                return
            }
            Task { await self.storeInCache(thumbnail, for: url) }
            completion(thumbnail)
        }
        
        subscriptions[url] = cancellable
    }
    
    /// Cancel any thumbnail loading for a particular URL
    func cancelLoad(for url: URL) {
        subscriptions[url]?.cancel()
        subscriptions.removeValue(forKey: url)
    }
    
    private func generateBlurPlaceholder(for url: URL) -> UIImage? {
        // In real usage, we might store a small or blurred version of the final image on disk.
        // For demonstration, we just return a generic colored placeholder.
        let size = CGSize(width: 60, height: 60)
        UIGraphicsBeginImageContext(size)
        UIColor.systemGray.withAlphaComponent(0.4).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    private func storeInCache(_ image: UIImage, for url: URL) {
        memoryCache[url] = image
    }
}