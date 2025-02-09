import SwiftUI

public struct ScaleButtonStyle: ButtonStyle {
    public init() {} // Public initializer to allow access from other modules
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
} 