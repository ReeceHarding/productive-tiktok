import Foundation
import AVFoundation

/// Shared resource loader delegate for optimized video loading across the app
class VideoResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = VideoResourceLoaderDelegate()
    
    private override init() {
        super.init()
        LoggingService.debug("VideoResourceLoaderDelegate initialized", component: "ResourceLoader")
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                       shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        LoggingService.debug("Resource loading request received", component: "ResourceLoader")
        LoggingService.debug("Request URL: \(String(describing: loadingRequest.request.url))", component: "ResourceLoader")
        LoggingService.debug("Request type: \(loadingRequest.request.httpMethod ?? "unknown")", component: "ResourceLoader")
        
        // Accept all loading requests for now
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                       didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        LoggingService.debug("Resource loading request cancelled", component: "ResourceLoader")
        LoggingService.debug("Cancelled request URL: \(String(describing: loadingRequest.request.url))", component: "ResourceLoader")
    }
} 