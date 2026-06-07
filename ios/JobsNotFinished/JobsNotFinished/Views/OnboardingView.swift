import SwiftUI

struct OnboardingView: View {
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isLightTheme: Bool {
        colorScheme == .light
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isLightTheme
                    ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.99)]
                    : [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Capsule()
                            .fill(isLightTheme ? Color.black.opacity(0.18) : Color.white.opacity(0.18))
                            .frame(width: 48, height: 5)
                            .padding(.top, 8)

                        Text("Done in 5")
                            .font(.system(size: 36, weight: .black))
                            .foregroundStyle(isLightTheme ? Color.black : Color.white)

                        Text("Finish the one thing you said you would.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(isLightTheme ? Color.black.opacity(0.75) : Color.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }

                    OnboardingPreviewCard(
                        title: "1. Name the task",
                        subtitle: "Write exactly what you’re about to do, then start the block.",
                        accent: .cyan,
                        content: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("What are you working on?")
                                    .font(.caption)
                                    .foregroundStyle(isLightTheme ? Color.black.opacity(0.6) : Color.white.opacity(0.6))

                                Text("Finish App Store screenshots")
                                    .font(.headline)
                                    .foregroundStyle(isLightTheme ? Color.black : Color.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(isLightTheme ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))

                                Text("Start 5-Minute Block")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.cyan)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    )

                    OnboardingPreviewCard(
                        title: "2. Stay present",
                        subtitle: "The block runs for five minutes. Camera monitors presence status while open.",
                        accent: .orange,
                        content: {
                            VStack(spacing: 14) {
                                HStack {
                                    Text("04:12")
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .foregroundStyle(isLightTheme ? Color.black : Color.white)

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Camera")
                                            .font(.caption)
                                            .foregroundStyle(isLightTheme ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(.green)
                                                .frame(width: 10, height: 10)
                                            Text("Present")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(isLightTheme ? Color.black : Color.white)
                                        }
                                    }
                                }

                                HStack(spacing: 10) {
                                    Image(systemName: "camera.badge.ellipsis")
                                        .font(.headline)
                                        .foregroundStyle(.orange)
                                    Text("Presence status only — no live camera preview is shown.")
                                        .font(.caption)
                                        .foregroundStyle(isLightTheme ? Color.black.opacity(0.72) : Color.white.opacity(0.72))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(isLightTheme ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    )

                    OnboardingPreviewCard(
                        title: "3. Build your flame",
                        subtitle: "Complete blocks to earn Fire Power. Build momentum streaks to earn more.",
                        accent: .orange,
                        content: {
                            VStack(spacing: 12) {
                                HStack(spacing: 10) {
                                    VStack(spacing: 4) {
                                        Text("Fire Power")
                                            .font(.caption2)
                                            .foregroundStyle(isLightTheme ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
                                        Text("47")
                                            .font(.title2.weight(.bold))
                                            .foregroundStyle(isLightTheme ? Color.black : Color.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isLightTheme ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    
                                    VStack(spacing: 4) {
                                        Text("Momentum")
                                            .font(.caption2)
                                            .foregroundStyle(isLightTheme ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
                                        Text("3x")
                                            .font(.title2.weight(.bold))
                                            .foregroundStyle(.orange)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isLightTheme ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "flame.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        Text("Orange Flame")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isLightTheme ? Color.black : Color.white)
                                    }
                                    Text("Next tier: Red Flame at 50 Fire Power")
                                        .font(.caption2)
                                        .foregroundStyle(isLightTheme ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isLightTheme ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    )

                    VStack(spacing: 14) {
                        OnboardingRow(
                            icon: "questionmark.circle",
                            title: "Need a reminder later?",
                            detail: "Open this guide anytime from Settings."
                        )
                        OnboardingRow(
                            icon: "iphone",
                            title: "No account required",
                            detail: "Your blocks, streak, and recent sessions stay on this device."
                        )
                    }

                    Button("Got it") {
                        onDismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(24)
            }
        }
    }
}

private struct OnboardingPreviewCard<Content: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(title: String, subtitle: String, accent: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(colorScheme == .light ? Color.black : Color.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.68) : Color.white.opacity(0.68))
            }

            content
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(colorScheme == .light ? Color.white.opacity(0.85) : Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(accent.opacity(0.45), lineWidth: 1)
                        )
                )
        }
    }
}

private struct OnboardingRow: View {
    let icon: String
    let title: String
    let detail: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(colorScheme == .light ? Color.black : Color.white)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(16)
        .background(colorScheme == .light ? Color.white.opacity(0.85) : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(colorScheme == .light ? Color.black : Color.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.62) : Color.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(colorScheme == .light ? Color.white.opacity(0.85) : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
