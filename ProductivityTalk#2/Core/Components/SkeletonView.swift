import SwiftUI

/// A simple skeleton loading view that can be used in place of actual content
/// while the data or video is loading.
struct SkeletonView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .shimmering()
            .frame(height: 200) // Example fixed height
    }
}

extension View {
    /// Simple shimmer effect
    func shimmering() -> some View {
        self
            .overlay(
                ShimmerOverlay()
                    .mask(self)
            )
    }
}

struct ShimmerOverlay: View {
    @State private var move = false
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(0.1),
                Color.white.opacity(0.4),
                Color.white.opacity(0.1)
            ]),
            startPoint: .topLeading,
            endPoint: .topTrailing
        )
        .rotationEffect(.degrees(20))
        .offset(x: move ? 200 : -200)
        .onAppear {
            withAnimation(
                Animation.linear(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                move.toggle()
            }
        }
    }
}