import SwiftUI
import UIKit

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var scale: CGFloat
    var rotation: Double
    var color: Color
    var particleType: ParticleType
    var delay: Double
    
    enum ParticleType: String, CaseIterable {
        case sparkle = "✨"
        case star = "⭐️"
        case heart = "❤️"
        case brain = "🧠"
        case boom = "💥"
        case confetti = "🎊"
    }
}

struct ConfettiView: View {
    let position: CGPoint
    @State private var particles: [Particle] = []
    @State private var isAnimating = false
    @State private var secondaryBurst = false
    
    let colors: [Color] = [.blue, .red, .green, .yellow, .purple, .orange, .pink]
    
    var body: some View {
        TimelineView(.animation) { _ in
            ZStack {
                // Primary burst
                ForEach(particles) { particle in
                    Text(particle.particleType.rawValue)
                        .foregroundColor(particle.color)
                        .scaleEffect(isAnimating ? particle.scale : 0)
                        .rotationEffect(.degrees(isAnimating ? particle.rotation * 2 : 0))
                        .offset(
                            x: isAnimating ? Double.random(in: -150...150) : 0,
                            y: isAnimating ? Double.random(in: -150...150) : 0
                        )
                        .opacity(isAnimating ? 0 : 1)
                        .position(particle.position)
                        .animation(
                            .easeOut(duration: 1.5)
                            .delay(particle.delay),
                            value: isAnimating
                        )
                }
                
                // Secondary burst
                ForEach(particles) { particle in
                    Text(particle.particleType.rawValue)
                        .foregroundColor(particle.color)
                        .scaleEffect(secondaryBurst ? particle.scale * 0.5 : 0)
                        .rotationEffect(.degrees(secondaryBurst ? -particle.rotation : 0))
                        .offset(
                            x: secondaryBurst ? Double.random(in: -100...100) : 0,
                            y: secondaryBurst ? Double.random(in: -100...100) : 0
                        )
                        .opacity(secondaryBurst ? 0 : 1)
                        .position(particle.position)
                        .animation(
                            .easeOut(duration: 1.0)
                            .delay(particle.delay + 0.1),
                            value: secondaryBurst
                        )
                }
            }
        }
        .onAppear {
            createParticles()
            
            // Trigger haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            
            // First burst
            withAnimation {
                isAnimating = true
            }
            
            // Secondary burst with slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let secondaryGenerator = UIImpactFeedbackGenerator(style: .light)
                secondaryGenerator.impactOccurred()
                withAnimation {
                    secondaryBurst = true
                }
            }
        }
    }
    
    private func createParticles() {
        particles = (0..<60).map { index in
            Particle(
                position: position,
                scale: CGFloat.random(in: 0.4...1.2),
                rotation: Double.random(in: 0...720),
                color: colors.randomElement() ?? .blue,
                particleType: Particle.ParticleType.allCases.randomElement() ?? .sparkle,
                delay: Double.random(in: 0...0.3)
            )
        }
    }
} 