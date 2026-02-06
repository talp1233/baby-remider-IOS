import SwiftUI

struct LaunchScreenView: View {
    @State private var bellScale: CGFloat = 0.3
    @State private var bellOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var bellRotation: Double = -15
    @State private var pulseScale: CGFloat = 1.0

    private let loc = LocalizationManager.shared

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.60, blue: 0.10),
                    Color(red: 1.0, green: 0.45, blue: 0.05),
                    Color(red: 0.95, green: 0.30, blue: 0.10)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Pulsing circle behind icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseScale)

                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 120, height: 120)

                    // Bell icon
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(bellRotation))
                        .scaleEffect(bellScale)
                        .opacity(bellOpacity)
                }

                VStack(spacing: 8) {
                    Text("Baby Reminder")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(loc.s("appSubtitle"))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                .opacity(textOpacity)

                Spacer()

                // Loading indicator
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)

                    Text(loc.s("loadingMessage"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .opacity(textOpacity)

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            // Bell animation
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                bellScale = 1.0
                bellOpacity = 1.0
                bellRotation = 0
            }

            // Text fade in
            withAnimation(.easeIn(duration: 0.6).delay(0.4)) {
                textOpacity = 1.0
            }

            // Pulse animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
