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
