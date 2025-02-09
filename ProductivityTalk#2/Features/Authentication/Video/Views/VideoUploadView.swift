import SwiftUI
import PhotosUI
import AVKit

@MainActor
struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @State private var isUploadEmpty: Bool = true
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
                    ScrollView {
                        VStack(spacing: 20) {
                            // Upload Button
                            PhotosPicker(
                                selection: $viewModel.selectedItems,
                                maxSelectionCount: 10,
                                matching: .videos,
                                photoLibrary: .shared()
                            ) {
                                VStack(spacing: 12) {
                                    Image(systemName: "video.badge.plus")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue)
                                    
                                    Text(isUploadEmpty ? "Click to Upload Videos" : "Add More Videos")
                                        .font(.headline)
                                    
                                    if isUploadEmpty {
                                        Text("Select one or more videos")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: isUploadEmpty ? 200 : 100)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                                        .foregroundColor(.blue.opacity(0.3))
                                )
                                .padding(.horizontal, 20)
                            }
                            .onAppear {
                                Task {
                                    isUploadEmpty = await viewModel.uploadStates.isEmpty
                                }
                            }
                            .onChange(of: viewModel.uploadStates) { _, newValue in
                                isUploadEmpty = newValue.isEmpty
                            }
                            
                            // Upload Progress List
                            if !viewModel.uploadStates.isEmpty {
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
                        }
                        .padding(.vertical)
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