import Foundation
import Network

/// A minimal network monitor that detects interface type and relative speed classification.
/// In a real app, you might expand this to do bandwidth checks or use NWPathMonitor more extensively.
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published private(set) var currentConnectionQuality: ConnectionQuality = .unknown
    
    private let monitor = NWPathMonitor()
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                if path.isExpensive {
                    self.currentConnectionQuality = .cellular
                } else {
                    self.currentConnectionQuality = .wifi
                }
            } else {
                self.currentConnectionQuality = .offline
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitorQueue")
        monitor.start(queue: queue)
    }
    
    enum ConnectionQuality {
        case offline
        case cellular
        case wifi
        case unknown
    }
}