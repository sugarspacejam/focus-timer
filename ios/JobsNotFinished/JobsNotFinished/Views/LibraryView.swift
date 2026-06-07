import SwiftUI

enum TaskLibraryFilter: String, CaseIterable, Identifiable {
    case pinned
    case recent
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pinned: return "Pinned"
        case .recent: return "Recent"
        case .all: return "All"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: FocusStore
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var filter: TaskLibraryFilter = .pinned
    @State private var searchText = ""
    @State private var editingTask: FocusTask?
    @State private var pinnedTaskIDs: Set<UUID> = []
    @AppStorage("pinnedTaskIDs") private var pinnedTaskIDsStorage: String = "[]"
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    private var primaryTextColor: Color {
        isLight ? .black : .white
    }
    
    private var secondaryTextColor: Color {
        isLight ? .black.opacity(0.6) : .white.opacity(0.6)
    }
    
    private var subtleFillColor: Color {
        isLight ? .black.opacity(0.05) : .white.opacity(0.08)
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: isLight
                    ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.99)]
                    : [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 12) {
                HStack {
                    Text("Block Library")
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                    
                    Spacer()
                    
                    Text("\(filteredTasks.count) blocks")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fire Power")
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                        Text("\(store.stats.totalFirePower)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(primaryTextColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Momentum")
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                        Text("\(store.stats.currentMomentumStreak)x")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(store.flameTier)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.flameColor)
                    }
                }
                .padding(12)
                .background(subtleFillColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                
                TextField("Find a block…", text: $searchText)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(subtleFillColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(primaryTextColor)
                
                HStack(spacing: 10) {
                    ForEach(TaskLibraryFilter.allCases) { option in
                        Button(option.title) {
                            filter = option
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == option ? Color.black : primaryTextColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(filter == option ? Color.cyan : subtleFillColor)
                        .clipShape(Capsule())
                    }
                }
                
                ScrollView(showsIndicators: false) {
                    if filteredTasks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 48))
                                .foregroundStyle(secondaryTextColor)
                            
                            Text("No tasks in library")
                                .font(.headline)
                                .foregroundStyle(primaryTextColor)
                            
                            Text("Add a task from the Home tab to get started.")
                                .font(.caption)
                                .foregroundStyle(secondaryTextColor)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredTasks) { task in
                                LibraryTaskRow(
                                    task: task,
                                    isPinned: pinnedTaskIDs.contains(task.id),
                                    onStart: { startTask(task.id) },
                                    onEdit: { editingTask = task },
                                    onDelete: { deleteTask(task.id) },
                                    onTogglePin: { togglePin(task.id) }
                                )
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task) { newName in
                editTaskName(task.id, newName: newName)
            }
        }
        .onAppear {
            loadPinnedTaskIDs()
        }
    }
    
    private var filteredTasks: [FocusTask] {
        let tasks = store.taskState.tasks.filter { !$0.isFinished }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var base: [FocusTask]
        switch filter {
        case .pinned:
            let pinned = tasks.filter { pinnedTaskIDs.contains($0.id) }
            base = pinned.isEmpty ? tasks : pinned
        case .recent:
            base = tasks.sorted { $0.createdAt > $1.createdAt }
        case .all:
            base = tasks
        }
        
        let sorted = base.sorted { $0.createdAt > $1.createdAt }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
    
    private func startTask(_ id: UUID) {
        do {
            try store.startTimer(for: id)
        } catch {
            print("Failed to start timer: \(error)")
        }
    }
    
    private func deleteTask(_ id: UUID) {
        Task {
            try? store.deleteTask(taskID: id)
            pinnedTaskIDs.remove(id)
            persistPinnedTaskIDs()
        }
    }
    
    private func togglePin(_ id: UUID) {
        if pinnedTaskIDs.contains(id) {
            pinnedTaskIDs.remove(id)
        } else {
            pinnedTaskIDs.insert(id)
        }
        persistPinnedTaskIDs()
    }
    
    private func loadPinnedTaskIDs() {
        guard let data = pinnedTaskIDsStorage.data(using: .utf8) else {
            pinnedTaskIDs = []
            return
        }
        if let strings = try? JSONDecoder().decode([String].self, from: data) {
            pinnedTaskIDs = Set(strings.compactMap(UUID.init(uuidString:)))
        } else {
            pinnedTaskIDs = []
        }
    }
    
    private func persistPinnedTaskIDs() {
        let strings = pinnedTaskIDs.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(strings), let str = String(data: data, encoding: .utf8) {
            pinnedTaskIDsStorage = str
        }
    }
    
    private func editTaskName(_ id: UUID, newName: String) {
        Task {
            try? store.renameTask(taskID: id, to: newName)
        }
    }
}

private struct LibraryTaskRow: View {
    private let taskNameMinimumScaleFactor: CGFloat = 0.82
    
    let task: FocusTask
    let isPinned: Bool
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.headline)
                        .foregroundStyle(colorScheme == .light ? Color.black : Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(taskNameMinimumScaleFactor)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                    
                    Text(isPinned ? "Pinned" : "")
                        .font(.caption)
                        .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
                }
                
                Spacer()
                
                Button("Start") {
                    onStart()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
            }
            
            HStack(spacing: 10) {
                Button(isPinned ? "Unpin" : "Pin") {
                    onTogglePin()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.8) : Color.white.opacity(0.8))
                
                Spacer()
                
                Button("Edit") {
                    onEdit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.8) : Color.white.opacity(0.8))
                
                Button("Delete") {
                    onDelete()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(colorScheme == .light ? Color.white.opacity(0.85) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct EditTaskSheet: View {
    let task: FocusTask
    let onSave: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Block name", text: $name)
            }
            .navigationTitle("Edit Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.count >= Constants.UI.minimumTaskNameLength {
                            onSave(trimmed)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                name = task.name
            }
        }
    }
}
