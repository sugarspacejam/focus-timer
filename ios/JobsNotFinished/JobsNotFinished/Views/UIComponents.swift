import SwiftUI

struct StatCard: View {
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(colorScheme == .light ? Color.black : Color.white)

            Text(title)
                .font(.caption)
                .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.65) : Color.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(colorScheme == .light ? Color.white.opacity(0.85) : Color.white.opacity(0.07))
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Task name", text: $editingName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(colorScheme == .light ? Color.black : Color.white)
                    .onSubmit {
                        onRename(editingName)
                        isEditing = false
                    }
            } else {
                Text(task.name)
                    .foregroundStyle(colorScheme == .light ? Color.black : Color.white)

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
        .background(colorScheme == .light ? Color.white.opacity(0.85) : Color.white.opacity(0.05))
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
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(colorScheme == .light ? Color.black : Color.white)
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            .background(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
