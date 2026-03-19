import SwiftUI

struct SplashView: View {
    @State private var iconScale: CGFloat = 0.7
    @State private var iconOpacity: Double = 0
    @State private var ring1Scale: CGFloat = 0.4
    @State private var ring2Scale: CGFloat = 0.4
    @State private var ring3Scale: CGFloat = 0.4
    @State private var ring1Opacity: Double = 0
    @State private var ring2Opacity: Double = 0
    @State private var ring3Opacity: Double = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    // Pulsing rings
                    Circle()
                        .stroke(Theme.accent.opacity(0.15), lineWidth: 1.5)
                        .frame(width: 200, height: 200)
                        .scaleEffect(ring3Scale)
                        .opacity(ring3Opacity)
                    Circle()
                        .stroke(Theme.accent.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 160, height: 160)
                        .scaleEffect(ring2Scale)
                        .opacity(ring2Opacity)
                    Circle()
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(ring1Scale)
                        .opacity(ring1Opacity)

                    // Icon card
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.13, blue: 0.28),
                                    Color(red: 0.10, green: 0.08, blue: 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, Theme.accent.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .offset(x: 3)
                        )
                        .shadow(color: Theme.accent.opacity(0.5), radius: 20, x: 0, y: 8)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                VStack(spacing: 6) {
                    Text("Stremio")
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Client")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
                .opacity(textOpacity)
            }
        }
        .onAppear { animate() }
    }

    private func animate() {
        // Icon pops in
        withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        // Rings ripple outward with staggered delays
        withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
            ring1Scale = 1.0
            ring1Opacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.28)) {
            ring2Scale = 1.0
            ring2Opacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.8).delay(0.42)) {
            ring3Scale = 1.0
            ring3Opacity = 1.0
        }
        // Text fades in
        withAnimation(.easeIn(duration: 0.4).delay(0.3)) {
            textOpacity = 1.0
        }
    }
}
