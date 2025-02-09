import SwiftUI

struct LoadingAnimation: View {
    @State private var yOffset: CGFloat = 0
    @State private var isAnimating = false
    let message: String?
    
    init(message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.primary)
                .offset(y: yOffset)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                    ) {
                        yOffset = -20
                    }
                }
            
            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    LoadingAnimation(message: "Loading...")
} 