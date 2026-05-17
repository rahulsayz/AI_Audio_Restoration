import SwiftUI

public enum RestorationTheme {
    // Curated design tokens for a beautiful dark-mode experience
    public static let deepSpace = Color(red: 0.05, green: 0.05, blue: 0.08)
    public static let spaceCard = Color(red: 0.09, green: 0.09, blue: 0.14)
    public static let saffron = Color(red: 0.95, green: 0.65, blue: 0.15) // Culturally-aware Saffron Gold
    public static let neonTeal = Color(red: 0.0, green: 0.85, blue: 0.8)  // Modern restoration active state
    public static let glassBorder = Color.white.opacity(0.08)
    public static let subtleText = Color.secondary
}

public struct GlassCardModifier: ViewModifier {
    public init() {}
    
    public func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(RestorationTheme.spaceCard.opacity(0.4))
            )
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [RestorationTheme.glassBorder, RestorationTheme.glassBorder.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
    }
}

public struct BreathingGlowModifier: ViewModifier {
    let isActive: Bool
    let color: Color
    @State private var scale: CGFloat = 1.0
    
    public func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.35) : Color.clear, radius: isActive ? 12 : 0)
            .scaleEffect(isActive ? scale : 1.0)
            .onAppear {
                if isActive {
                    withAnimation(
                        .easeInOut(duration: 1.8)
                        .repeatForever(autoreverses: true)
                    ) {
                        scale = 1.03
                    }
                }
            }
    }
}

extension View {
    public func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }
    
    public func breathingGlow(isActive: Bool, color: Color) -> some View {
        self.modifier(BreathingGlowModifier(isActive: isActive, color: color))
    }
}

/// A beautiful animated ambient soundwave background view using gradients and soft shapes.
public struct SoundwaveBackground: View {
    @State private var isAnimating = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Dark base layer
            RestorationTheme.deepSpace
                .ignoresSafeArea()
            
            // Large ambient organic blobs representing audio wave interference
            ZStack {
                Circle()
                    .fill(RestorationTheme.saffron.opacity(0.08))
                    .frame(width: 450, height: 450)
                    .blur(radius: 80)
                    .offset(x: isAnimating ? -100 : -150, y: isAnimating ? -50 : -100)
                
                Circle()
                    .fill(RestorationTheme.neonTeal.opacity(0.07))
                    .frame(width: 500, height: 500)
                    .blur(radius: 90)
                    .offset(x: isAnimating ? 150 : 100, y: isAnimating ? 100 : 50)
                
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 400, height: 400)
                    .blur(radius: 70)
                    .offset(x: isAnimating ? -50 : 20, y: isAnimating ? -120 : -60)
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 8.0)
                    .repeatForever(autoreverses: true)
                ) {
                    isAnimating = true
                }
            }
        }
    }
}
