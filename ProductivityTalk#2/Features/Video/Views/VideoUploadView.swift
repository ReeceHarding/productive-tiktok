import SwiftUI
import PhotosUI
import AVKit

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Video Details")) {
                    if let thumbnail = viewModel.thumbnailImage {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 200)
                            .clipped()
                    }
                    
                    let isVideoSelected = viewModel.selectedItem != nil
                    
                    PhotosPicker(
                        selection: $viewModel.selectedItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            isVideoSelected ? "Change Video" : "Select Video",
                            systemImage: "video.badge.plus"
                        )
                    }
                    .onChange(of: viewModel.selectedItem) { oldValue, newValue in
                        Task { @MainActor in
                            await viewModel.loadVideo()
                        }
                    }
                    
                    TextField("Title", text: $viewModel.title)
                        .textContentType(.none)
                    
                    TextField("Tags (comma separated)", text: $viewModel.tagsInput)
                        .textContentType(.none)
                    
                    TextField("Description", text: $viewModel.description, axis: .vertical)
                        .textContentType(.none)
                        .lineLimit(4...6)
                }
                
                Section {
                    Button(action: upload) {
                        if viewModel.isUploading {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Uploading... \(Int(viewModel.uploadProgress * 100))%")
                            }
                        } else {
                            Text("Upload Video")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.canUpload || viewModel.isUploading)
                }
            }
            .navigationTitle("Upload Video")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isUploading)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
    }
    
    private func upload() {
        Task { @MainActor in
            await viewModel.uploadVideo()
            if !viewModel.showError {
                dismiss()
            }
        }
    }
}

#Preview {
    VideoUploadView()
} 