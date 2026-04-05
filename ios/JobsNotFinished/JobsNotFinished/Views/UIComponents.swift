import SwiftUI

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TaskRow: View {
    let task: FocusTask
    let onStart: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editingName = ""

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Task name", text: $editingName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .onSubmit {
                        onRename(editingName)
                        isEditing = false
                    }
            } else {
                Text(task.name)
                    .foregroundStyle(.white)

                Spacer()

                Button("Start") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button("Edit") {
                    editingName = task.name
                    isEditing = true
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.5))

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.cyan)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct UpgradeView: View {
    @ObservedObject var purchaseManager: PurchaseManager
    @Binding var pendingUpgradeAction: PendingUpgradeAction?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            Text("Upgrade to Pro")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.white)

                            Text("Unlock unlimited contracts and strict voice mode")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 16) {
                            FeatureRow(icon: "infinity", title: "Unlimited Contracts", description: "No more daily limits")
                            FeatureRow(icon: "speaker.wave.3", title: "Strict Voice Mode", description: "Sharper accountability messages")
                            FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Stats", description: "Detailed productivity insights")
                            FeatureRow(icon: "gear", title: "Custom Settings", description: "Personalize your experience")
                        }

                        VStack(spacing: 12) {
                            Button("Purchase Pro - $4.99") {
                                Task {
                                    do {
                                        try await purchaseManager.purchase()
                                        dismiss()
                                    } catch {
                                        print("Purchase failed: \(error)")
                                    }
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())

                            Button("Restore Purchase") {
                                Task {
                                    do {
                                        try await purchaseManager.restore()
                                        dismiss()
                                    } catch {
                                        print("Restore failed: \(error)")
                                    }
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())

                            Button("Cancel") {
                                dismiss()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarHidden(true)
        }
        .interactiveDismissDisabled()
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
