import SwiftUI

struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 48, height: 5)
                            .padding(.top, 8)

                        Text("Done in 5")
                            .font(.system(size: 36, weight: .black))
                            .foregroundStyle(.white)

                        Text("One contract. Five minutes. No excuses.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }

                    OnboardingPreviewCard(
                        title: "1. Name the task",
                        subtitle: "Write exactly what you’re about to do, then start the contract.",
                        accent: .cyan,
                        content: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("What are you working on?")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))

                                Text("Finish App Store screenshots")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))

                                Text("Start 5-Minute Contract")
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
                        title: "2. Stay in it",
                        subtitle: "The contract runs for five minutes. If camera accountability is on, stay in frame while the app is open.",
                        accent: .orange,
                        content: {
                            VStack(spacing: 14) {
                                HStack {
                                    Text("04:12")
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Camera")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(.green)
                                                .frame(width: 10, height: 10)
                                            Text("Present")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }

                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 150)
                                    .overlay {
                                        VStack(spacing: 10) {
                                            Image(systemName: "person.crop.rectangle")
                                                .font(.system(size: 38))
                                                .foregroundStyle(.white.opacity(0.8))
                                            Text("Keep your attention on the task until the timer ends.")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.7))
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 20)
                                        }
                                    }
                            }
                        }
                    )

                    OnboardingPreviewCard(
                        title: "3. Finish or fail",
                        subtitle: "You do not need a warning every time. This is the rule: quitting early counts as a failure and resets your streak.",
                        accent: .red,
                        content: {
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    OutcomeChip(label: "Done", color: .green)
                                    OutcomeChip(label: "Quit = Failure", color: .red)
                                }

                                HStack(spacing: 12) {
                                    MetricPill(title: "Streak", value: "7")
                                    MetricPill(title: "Failures", value: "1")
                                    MetricPill(title: "Today", value: "4")
                                }
                            }
                        }
                    )

                    VStack(spacing: 14) {
                        OnboardingRow(
                            icon: "questionmark.circle",
                            title: "Need a reminder later?",
                            detail: "Open this guide anytime from the question mark on the home screen."
                        )
                        OnboardingRow(
                            icon: "iphone",
                            title: "No account required",
                            detail: "Your tasks, streak, and recent contracts stay on this device."
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
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }

            content
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.05))
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

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct OutcomeChip: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.24))
            .clipShape(Capsule())
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
