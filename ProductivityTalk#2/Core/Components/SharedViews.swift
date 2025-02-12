import SwiftUI

/// A set of shared views for loading, refresh controls, and statistic cards.

// MARK: - Shared Loading View
public struct SharedLoadingView: View {
    let message: String

    public init(_ message: String = "Loading...") {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Replace the ProgressView with the custom LoadingAnimation
            LoadingAnimation(message: message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.8))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared Refresh Control
public struct SharedRefreshControl: View {
    @Binding var isRefreshing: Bool
    let action: () async -> Void

    public init(isRefreshing: Binding<Bool>, action: @escaping () async -> Void) {
        self._isRefreshing = isRefreshing
        self.action = action
    }

    public var body: some View {
        GeometryReader { geometry in
            if geometry.frame(in: .global).minY > 50 {
                Spacer()
                    .onAppear {
                        isRefreshing = true
                        Task {
                            await action()
                        }
                    }
            }
            
            HStack {
                Spacer()
                if isRefreshing {
                    // Replace default spinner with LoadingAnimation
                    LoadingAnimation(message: nil)
                        .frame(width: 32, height: 32)
                }
                Spacer()
            }
        }
        .padding(.top, -50)
    }
}

// MARK: - Shared Statistic Card
public struct SharedStatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    public init(title: String, value: String, icon: String, color: Color) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.systemBackground).opacity(0.8))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}