import SwiftUI
import FirebaseFirestore
import UIKit
import CoreMedia
import AVFoundation

class VideoCollectionViewCell: UICollectionViewCell {
    var hostingController: UIHostingController<VideoPlayerView>?
    
    override func prepareForReuse() {
        super.prepareForReuse()
        hostingController?.view.removeFromSuperview()
        hostingController = nil
    }
}

struct VerticalFeedViewController: UIViewControllerRepresentable {
    @Binding var currentIndex: Int
    let videos: [Video]
    let geometry: GeometryProxy
    let viewModel: VideoFeedViewModel
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UICollectionViewController {
        // Create layout
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        
        // Create collection view controller
        let controller = UICollectionViewController(collectionViewLayout: layout)
        controller.collectionView.backgroundColor = .black
        controller.collectionView.isPagingEnabled = true
        controller.collectionView.showsVerticalScrollIndicator = false
        controller.collectionView.showsHorizontalScrollIndicator = false
        controller.collectionView.delegate = context.coordinator
        controller.collectionView.dataSource = context.coordinator
        
        // Register cell
        controller.collectionView.register(VideoCollectionViewCell.self, forCellWithReuseIdentifier: "Cell")
        
        return controller
    }
    
    func updateUIViewController(_ controller: UICollectionViewController, context: Context) {
        // Update collection view if needed
        controller.collectionView.reloadData()
    }
    
    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
        var parent: VerticalFeedViewController
        
        init(_ verticalFeedViewController: VerticalFeedViewController) {
            self.parent = verticalFeedViewController
        }
        
        // MARK: - UICollectionViewDataSource
        
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            return parent.videos.count
        }
        
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! VideoCollectionViewCell
            
            // Remove old hosting controller if exists
            if let oldController = cell.hostingController {
                oldController.view.removeFromSuperview()
            }
            
            // Create new hosting controller with explicit type
            let videoPlayerView = VideoPlayerView(video: parent.videos[indexPath.item])
            let wrappedView = videoPlayerView
                .frame(width: parent.geometry.size.width, height: parent.geometry.size.height)
            let hostingController = UIHostingController<VideoPlayerView>(rootView: videoPlayerView)
            
            // Add as child view controller
            if let parentVC = collectionView.findViewController() {
                parentVC.addChild(hostingController)
                cell.contentView.addSubview(hostingController.view)
                hostingController.view.frame = cell.contentView.bounds
                hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                hostingController.didMove(toParent: parentVC)
            }
            
            cell.hostingController = hostingController
            return cell
        }
        
        // MARK: - UICollectionViewDelegateFlowLayout
        
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            return CGSize(width: parent.geometry.size.width, height: parent.geometry.size.height)
        }
        
        // MARK: - UICollectionViewDelegate
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            // Stop current video when scrolling starts
            let currentIndex = Int(scrollView.contentOffset.y / parent.geometry.size.height)
            guard let collectionView = scrollView as? UICollectionView else { return }
            if let cell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? VideoCollectionViewCell,
               let videoView = cell.hostingController?.rootView as? VideoPlayerView {
                videoView.viewModel.pause()
            }
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                handleScrollStop(scrollView)
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            handleScrollStop(scrollView)
        }
        
        private func handleScrollStop(_ scrollView: UIScrollView) {
            let index = Int(scrollView.contentOffset.y / parent.geometry.size.height)
            if parent.currentIndex != index {
                parent.currentIndex = index
                
                // Play current video
                guard let collectionView = scrollView as? UICollectionView else { return }
                if let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? VideoCollectionViewCell,
                   let videoView = cell.hostingController?.rootView as? VideoPlayerView {
                    videoView.viewModel.play()
                }
                
                // Preload next two videos
                if index < parent.videos.count - 1 {
                    let nextVideo = parent.videos[index + 1]
                    if let cell = collectionView.cellForItem(at: IndexPath(item: index + 1, section: 0)) as? VideoCollectionViewCell,
                       let videoView = cell.hostingController?.rootView as? VideoPlayerView {
                        videoView.viewModel.preloadVideo(nextVideo)
                    }
                }
                if index < parent.videos.count - 2 {
                    let nextNextVideo = parent.videos[index + 2]
                    if let cell = collectionView.cellForItem(at: IndexPath(item: index + 2, section: 0)) as? VideoCollectionViewCell,
                       let videoView = cell.hostingController?.rootView as? VideoPlayerView {
                        videoView.viewModel.preloadVideo(nextNextVideo)
                    }
                }
            }
        }
    }
}

extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}

struct VideoFeedView: View {
    @StateObject var viewModel = VideoFeedViewModel()
    @State private var currentIndex = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isLoading {
                LoadingAnimation(message: "Loading videos...")
                    .foregroundColor(.white)
            } else if let error = viewModel.error {
                Text(error.localizedDescription)
                    .foregroundColor(.white)
            } else if viewModel.videos.isEmpty {
                Text("No videos available")
                    .foregroundColor(.white)
            } else {
                // Use TabView with paging for vertical scrolling
                TabView(selection: $currentIndex) {
                    ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                        VideoPlayerView(video: video)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: currentIndex) { oldValue, newValue in
                    // Load more videos if we're near the end
                    if newValue >= viewModel.videos.count - 2 {
                        Task {
                            await viewModel.fetchNextBatch()
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.fetchVideos()
            }
        }
    }
}

#Preview {
    VideoFeedView()
} 