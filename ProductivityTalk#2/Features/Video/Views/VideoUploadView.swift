import SwiftUI
import PhotosUI
import AVKit

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.3),
                        Color.purple.opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Always show the upload button
                    PhotosPicker(
                        selection: $viewModel.selectedItems,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 12) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            
                            Text(viewModel.uploadStates.isEmpty ? "Click to Upload Videos" : "Add More Videos")
                                .font(.headline)
                            
                            if viewModel.uploadStates.isEmpty {
                                Text("Select one or more videos")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: viewModel.uploadStates.isEmpty ? 200 : 100)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                                .foregroundColor(.blue.opacity(0.3))
                        )
                        .padding(.horizontal, 20)
                    }
                    .onChange(of: viewModel.selectedItems) { oldValue, newValue in
                        if !newValue.isEmpty {
                            Task { @MainActor in
                                await viewModel.loadVideos()
                            }
                        }
                    }
                    
                    if !viewModel.uploadStates.isEmpty {
                        // Upload Progress
                        ScrollView {
                            VStack(spacing: 16) {
                                ForEach(Array(viewModel.uploadStates.keys), id: \.self) { id in
                                    if let state = viewModel.uploadStates[id] {
                                        HStack(spacing: 16) {
                                            // Thumbnail or placeholder
                                            if let thumbnail = state.thumbnailImage {
                                                Image(uiImage: thumbnail)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 60, height: 60)
                                                    .cornerRadius(8)
                                            } else {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.gray.opacity(0.3))
                                                        .frame(width: 60, height: 60)
                                                    
                                                    Image(systemName: "video.fill")
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Video \(id.prefix(8))")
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                
                                                // Progress or Checkmark with percentage
                                                if state.isComplete {
                                                    Label("Complete", systemImage: "checkmark.circle.fill")
                                                        .foregroundColor(.green)
                                                        .font(.subheadline)
                                                } else {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        ProgressView(value: state.progress)
                                                            .progressViewStyle(LinearProgressViewStyle())
                                                            .tint(.blue)
                                                        
                                                        Text("\(Int(state.progress * 100))% uploaded")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                }
            }
            .navigationTitle("Upload Videos")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
    }
}

#Preview {
    VideoUploadView()
} 