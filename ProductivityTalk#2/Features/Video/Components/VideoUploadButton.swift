import SwiftUI

struct VideoUploadButton: View {
    @State private var showUploadSheet = false
    
    var body: some View {
        Button(action: { showUploadSheet = true }) {
            Label("Upload Video", systemImage: "video.badge.plus")
        }
        .sheet(isPresented: $showUploadSheet) {
            VideoUploadView()
        }
    }
}

#Preview {
    VideoUploadButton()
} 