import SwiftUI

/// Extension on View to provide a modifier that makes the view fill the full available screen
/// except for the bottom safe area inset (typically occupied by the TabView or menu).
/// 
/// This modifier uses GeometryReader to dynamically compute the available width and height,
/// subtracting the bottom safe area inset. Extensive logging is provided via LoggingService
/// to trace the dimensions and computed frame values.
/// 
/// Usage:
///     SomeView()
///         .fullScreenContent()
public extension View {
    func fullScreenContent() -> some View {
        GeometryReader { geometry in
            self
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height - geometry.safeAreaInsets.bottom
                )
                .background(Color.clear) // Maintain background transparency
                .onAppear {
                    #if DEBUG
                    print("FullScreenContent Modifier: geometry.size.width = \(geometry.size.width)")
                    print("FullScreenContent Modifier: geometry.size.height = \(geometry.size.height)")
                    print("FullScreenContent Modifier: geometry.safeAreaInsets.bottom = \(geometry.safeAreaInsets.bottom)")
                    print("FullScreenContent Modifier: adjustedHeight = \(geometry.size.height - geometry.safeAreaInsets.bottom)")
                    #endif
                }
        }
    }
} 