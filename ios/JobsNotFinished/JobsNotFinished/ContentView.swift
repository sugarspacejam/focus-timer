import SwiftUI
import AVFoundation
import Vision

private let defaultAwayUtterances = [
    "Get back to your task.",
    "You're away. Get back in frame.",
    "Stay on task or this block fails.",
    "Done in 5 only works if you stay with the task."
]

struct ContentView: View {
    private enum FocusedField {
        case newTaskName
        case searchText
    }

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = FocusStore()
    @StateObject private var cameraManager = CameraManager()
    @State private var newTaskName = ""
    @State private var searchText = ""
    @State private var pendingAction: PendingAction?
    @State private var isQuitConfirmationPresented = false
    @State private var editingTask: FocusTask?
    @State private var isDetailsPresented = false
    @FocusState private var focusedField: FocusedField?

    private let motivationalMessages = [
        "Great things come from hard work and perseverance. No excuses.",
        "I can't relate to lazy people. We don't speak the same language.",
        "Discipline equals freedom.",
        "The moment you give up is the moment you let someone else win.",
        "Rest at the end, not in the middle.",
        "Pick one task. Stay with it. Get it done."
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerSection
                        statsSection
                        addTaskSection
                        tasksSection
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $editingTask) { task in
            EditTaskView(task: task) { updatedName in
                store.renameTask(taskID: task.id, to: updatedName)
            }
        }
        .sheet(isPresented: $isDetailsPresented) {
            SettingsView(
                awaySpeechSection: awaySpeechSection,
                settingsSection: settingsSection
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.isTimerPresentationActive },
            set: { _ in }
        )) {
            TimerModalView(
                activeTimerSection: activeTimerSection,
                cameraSection: cameraSection
            )
            .interactiveDismissDisabled(true)
        }
        .alert(item: $pendingAction) { action in
            switch action {
            case .resetStats:
                return Alert(
                    title: Text("Reset statistics?"),
                    message: Text("Tasks will remain, but all stats will be reset."),
                    primaryButton: .destructive(Text("Reset")) {
                        store.resetStats()
                    },
                    secondaryButton: .cancel()
                )
            case .clearAll:
                return Alert(
                    title: Text("Delete everything?"),
                    message: Text("This removes all tasks, stats, and history. This cannot be undone."),
                    primaryButton: .destructive(Text("Delete all")) {
                        store.clearAll()
                        cameraManager.stopSession()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .task {
            store.resumeTimerIfNeeded()
            cameraManager.setAwayThresholdAction {
                if store.isTimerActive && !store.timerCompleted {
                    store.stopTimer(asFailure: true)
                }
            }
            cameraManager.updateAwayUtterances(store.awayUtterances)
            if store.isCameraEnabled && store.isTimerActive {
                await cameraManager.ensurePermissionAndStart()
            }
        }
        .onChange(of: store.isTimerActive) { _, isActive in
            if isActive {
                if store.isCameraEnabled {
                    Task {
                        await cameraManager.ensurePermissionAndStart()
                    }
                }
            } else {
                cameraManager.stopSession()
            }
        }
        .onChange(of: store.isCameraEnabled) { _, isEnabled in
            if isEnabled && store.isTimerActive {
                Task {
                    await cameraManager.ensurePermissionAndStart()
                }
            }
            if !isEnabled {
                cameraManager.stopSession()
            }
        }
        .onChange(of: store.timerCompleted) { _, isCompleted in
            if isCompleted {
                cameraManager.stopSession()
            } else if store.isCameraEnabled && store.isTimerActive {
                Task {
                    await cameraManager.ensurePermissionAndStart()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && store.isTimerActive && !store.timerCompleted {
                store.stopTimer(asFailure: true)
                cameraManager.stopSession()
            }
        }
        .onChange(of: store.awayUtterances) { _, utterances in
            cameraManager.updateAwayUtterances(utterances)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Done in 5")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(motivationalMessages[store.motivationalMessageIndex % motivationalMessages.count])
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Button {
                    focusedField = nil
                    isDetailsPresented = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open details")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(title: "Today", value: "\(store.stats.todayBlocks)")
            StatCard(title: "Streak", value: "\(store.stats.streak)")
            StatCard(title: "Rate", value: "\(store.completionRate)%")
            StatCard(title: "Quits", value: "\(store.stats.failedBlocks)")
        }
    }

    private var addTaskSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start a Task")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            TextField("What are you working on?", text: $newTaskName)
                .focused($focusedField, equals: .newTaskName)
                .textInputAutocapitalization(.sentences)
                .padding()
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)

            Button("Start 5-Minute Block") {
                focusedField = nil
                let trimmedName = newTaskName.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.startTimerForTaskNamed(trimmedName) {
                    newTaskName = ""
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Save Task Without Starting") {
                focusedField = nil
                let trimmedName = newTaskName.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.addTask(named: trimmedName) {
                    newTaskName = ""
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Text("Type one task and either start immediately or save it for later.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var activeTimerSection: some View {
        VStack(spacing: 18) {
            Text(store.activeTaskName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 14)
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: store.progress)
                    .stroke(
                        AngularGradient(colors: [Color.cyan, Color.orange], center: .center),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)

                VStack(spacing: 8) {
                    Text(store.formattedRemaining)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(store.timerCompleted ? "Block complete" : "Stay locked in")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if store.timerCompleted {
                VStack(spacing: 12) {
                    Text("5-minute block complete")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    Text("Take another block or go back to your task list.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))

                    Button("Start Another 5-Minute Block") {
                        store.restartCompletedTimer()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Return to Task List") {
                        store.returnToTasks()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                HStack(spacing: 12) {
                    Button("Quit Block") {
                        isQuitConfirmationPresented = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .alert("Quit this block?", isPresented: $isQuitConfirmationPresented) {
            Button("Keep Going", role: .cancel) {}
            Button("Yes, Quit", role: .destructive) {
                store.stopTimer(asFailure: true)
                cameraManager.stopSession()
            }
        } message: {
            Text("Quitting counts as a failed block.")
        }
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { store.isCameraEnabled },
                set: { store.isCameraEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stay on Task")
                        .foregroundStyle(.white)
                    Text("Uses your camera to keep you on-task during a block. If you're away too long, the block fails.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .tint(.cyan)

            if store.isCameraEnabled {
                Group {
                    if cameraManager.authorizationStatus == .denied || cameraManager.authorizationStatus == .restricted {
                        Text("Camera access is blocked. Enable it in Settings.")
                            .foregroundStyle(.orange)
                    } else if store.isTimerActive {
                        HStack {
                            Text(cameraManager.presenceTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(cameraManager.presenceColor)
                            Spacer()
                            if cameraManager.secondsAway > 0 {
                                Text("Away \(cameraManager.secondsAway)s")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text("Everything stays on this iPhone. Nothing is sent to any server. If you're away for 6 seconds, the block fails.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        Text("Turn this on when you want extra pressure to stay seated and finish the block. Everything stays on this iPhone.")
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            TextField("Search tasks", text: $searchText)
                .focused($focusedField, equals: .searchText)
                .textInputAutocapitalization(.never)
                .padding()
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)

            if filteredTasks.isEmpty {
                Text(activeTasks.isEmpty ? "Add your first task to begin." : "No active tasks match your search.")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredTasks) { task in
                        TaskCard(
                            task: task,
                            statLine: store.statLine(for: task),
                            minuteLine: store.minuteLine(for: task),
                            isActive: store.activeTaskID == task.id,
                            isDisabled: store.isTimerActive && store.activeTaskID != task.id,
                            onStart: {
                                focusedField = nil
                                store.startTimer(for: task.id)
                            },
                            onDelete: {
                                store.deleteTask(taskID: task.id)
                            },
                            onEdit: {
                                editingTask = task
                            }
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Settings")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                Button("Reset Stats") {
                    pendingAction = .resetStats
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Delete All Data") {
                    pendingAction = .clearAll
                }
                .buttonStyle(DestructiveButtonStyle())
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.bottom, 40)
    }

    private var awaySpeechSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stay on Task Voice")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("Edit what Done in 5 says when you're away. These lines repeat while Stay on Task is active.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            VStack(spacing: 10) {
                ForEach(Array(store.awayUtterances.enumerated()), id: \ .offset) { index, line in
                    TextField("Prompt \(index + 1)", text: Binding(
                        get: { line },
                        set: { updatedValue in
                            store.updateAwayUtterance(at: index, to: updatedValue)
                        }
                    ), axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                }
            }

            Button("Reset Voice Lines") {
                store.resetAwayUtterances()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var filteredTasks: [FocusTask] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            return activeTasks
        }
        return activeTasks.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    private var activeTasks: [FocusTask] {
        store.tasks.filter { $0.isFinished == false }
    }
}

private struct TimerModalView<ActiveTimerContent: View, CameraContent: View>: View {
    let activeTimerSection: ActiveTimerContent
    let cameraSection: CameraContent

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        activeTimerSection
                        cameraSection
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
        }
    }
}

private enum PendingAction: Identifiable {
    case resetStats
    case clearAll

    var id: String {
        switch self {
        case .resetStats:
            return "resetStats"
        case .clearAll:
            return "clearAll"
        }
    }
}

private struct FocusTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var isFinished: Bool
}

private struct CompletedTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var completedAt: Date
    var totalMinutes: Int
}

private struct TaskStat: Codable, Equatable {
    var completed: Int
    var failed: Int
}

private struct FocusStats: Codable, Equatable {
    var todayBlocks: Int
    var totalBlocks: Int
    var completedBlocks: Int
    var failedBlocks: Int
    var streak: Int
    var lastDate: String
    var taskStats: [UUID: TaskStat]
    var taskTimeSpent: [UUID: Int]
    var completedTasks: Int
    var completedTasksList: [CompletedTask]

    static func initial() -> FocusStats {
        FocusStats(
            todayBlocks: 0,
            totalBlocks: 0,
            completedBlocks: 0,
            failedBlocks: 0,
            streak: 0,
            lastDate: DateFormatter.focusDay.string(from: Date()),
            taskStats: [:],
            taskTimeSpent: [:],
            completedTasks: 0,
            completedTasksList: []
        )
    }
}

private struct PersistedState: Codable {
    var tasks: [FocusTask]
    var stats: FocusStats
    var activeTaskID: UUID?
    var timerStartDate: Date?
    var timerCompleted: Bool
    var isCameraEnabled: Bool
    var awayUtterances: [String]
}

private final class FocusStore: ObservableObject {
    @Published var tasks: [FocusTask]
    @Published var stats: FocusStats
    @Published var activeTaskID: UUID?
    @Published var timerStartDate: Date?
    @Published var remainingSeconds: Int
    @Published var timerCompleted: Bool
    @Published var motivationalMessageIndex: Int
    @Published var isCameraEnabled: Bool
    @Published var awayUtterances: [String]

    private let persistenceKey = "focus.store.v3"
    private let timerDuration = 5 * 60
    private var timer: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            tasks = state.tasks
            stats = state.stats
            activeTaskID = state.activeTaskID
            timerStartDate = state.timerStartDate
            timerCompleted = state.timerCompleted
            isCameraEnabled = state.isCameraEnabled
            awayUtterances = state.awayUtterances.isEmpty ? defaultAwayUtterances : state.awayUtterances
        } else {
            tasks = []
            stats = FocusStats.initial()
            activeTaskID = nil
            timerStartDate = nil
            timerCompleted = false
            isCameraEnabled = true
            awayUtterances = defaultAwayUtterances
        }

        remainingSeconds = timerDuration
        motivationalMessageIndex = Int.random(in: 0..<6)
        migrateDayIfNeeded()
        syncRemainingSeconds()
    }

    var isTimerActive: Bool {
        activeTaskID != nil
    }

    var isTimerPresentationActive: Bool {
        activeTaskID != nil || timerCompleted
    }

    var activeTaskName: String {
        guard let activeTask = activeTask else {
            return ""
        }
        return activeTask.name
    }

    var activeTask: FocusTask? {
        guard let activeTaskID else {
            return nil
        }
        return tasks.first(where: { $0.id == activeTaskID })
    }

    var completionRate: Int {
        if stats.totalBlocks == 0 {
            return 0
        }
        return Int((Double(stats.completedBlocks) / Double(stats.totalBlocks) * 100).rounded())
    }

    var progress: Double {
        Double(remainingSeconds) / Double(timerDuration)
    }

    var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func resumeTimerIfNeeded() {
        guard activeTaskID != nil else {
            return
        }
        syncRemainingSeconds()
        if remainingSeconds == 0 && !timerCompleted {
            completeTimer()
            return
        }
        if !timerCompleted {
            startHeartbeat()
        }
    }

    func addTask(named name: String) -> Bool {
        if name.count < 2 {
            return false
        }
        if tasks.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame && $0.isFinished == false }) {
            return false
        }
        tasks.append(FocusTask(id: UUID(), name: name, createdAt: Date(), isFinished: false))
        persist()
        return true
    }

    func startTimerForTaskNamed(_ name: String) -> Bool {
        if name.count < 2 {
            return false
        }
        if let existingTask = tasks.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame && $0.isFinished == false }) {
            startTimer(for: existingTask.id)
            return true
        }
        let newTask = FocusTask(id: UUID(), name: name, createdAt: Date(), isFinished: false)
        tasks.append(newTask)
        persist()
        startTimer(for: newTask.id)
        return true
    }

    func renameTask(taskID: UUID, to name: String) {
        if name.count < 2 {
            return
        }
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        if tasks.contains(where: { $0.id != taskID && $0.name.compare(name, options: .caseInsensitive) == .orderedSame && $0.isFinished == false }) {
            return
        }
        tasks[index].name = name
        persist()
    }

    func deleteTask(taskID: UUID) {
        if isTimerActive {
            return
        }
        tasks.removeAll { $0.id == taskID }
        stats.taskStats[taskID] = nil
        stats.taskTimeSpent[taskID] = nil
        persist()
    }

    func startTimer(for taskID: UUID) {
        activeTaskID = taskID
        timerStartDate = Date()
        remainingSeconds = timerDuration
        timerCompleted = false
        motivationalMessageIndex += 1
        persist()
        startHeartbeat()
    }

    func restartCompletedTimer() {
        guard let activeTaskID else {
            return
        }
        startTimer(for: activeTaskID)
    }

    func stopTimer(asFailure: Bool) {
        stopHeartbeat()
        if asFailure, let activeTaskID {
            stats.totalBlocks += 1
            stats.failedBlocks += 1
            stats.streak = 0
            var taskStat = stats.taskStats[activeTaskID] ?? TaskStat(completed: 0, failed: 0)
            taskStat.failed += 1
            stats.taskStats[activeTaskID] = taskStat
        }
        activeTaskID = nil
        timerStartDate = nil
        timerCompleted = false
        remainingSeconds = timerDuration
        persist()
    }

    func returnToTasks() {
        stopHeartbeat()
        activeTaskID = nil
        timerStartDate = nil
        timerCompleted = false
        remainingSeconds = timerDuration
        persist()
    }

    func completeTimer() {
        guard let activeTaskID else {
            return
        }
        stopHeartbeat()
        timerCompleted = true
        remainingSeconds = 0

        stats.todayBlocks += 1
        stats.totalBlocks += 1
        stats.completedBlocks += 1
        stats.streak += 1

        var taskStat = stats.taskStats[activeTaskID] ?? TaskStat(completed: 0, failed: 0)
        taskStat.completed += 1
        stats.taskStats[activeTaskID] = taskStat
        stats.taskTimeSpent[activeTaskID, default: 0] += 5
        persist()
    }

    func markActiveTaskFinished() {
        guard timerCompleted, let activeTask else {
            return
        }
        guard let index = tasks.firstIndex(where: { $0.id == activeTask.id }) else {
            return
        }
        let totalMinutes = stats.taskTimeSpent[activeTask.id, default: 0]
        stats.completedTasksList.append(
            CompletedTask(id: UUID(), name: activeTask.name, completedAt: Date(), totalMinutes: totalMinutes)
        )
        stats.completedTasks += 1
        tasks[index].isFinished = true
        returnToTasks()
        persist()
    }

    func clearFinishedTaskHistory() {
        stats.completedTasksList = []
        persist()
    }

    func resetStats() {
        stats = FocusStats.initial()
        persist()
    }

    func clearAll() {
        stopHeartbeat()
        tasks = []
        stats = FocusStats.initial()
        activeTaskID = nil
        timerStartDate = nil
        timerCompleted = false
        remainingSeconds = timerDuration
        awayUtterances = defaultAwayUtterances
        persist()
    }

    func updateAwayUtterance(at index: Int, to text: String) {
        if awayUtterances.indices.contains(index) == false {
            return
        }
        awayUtterances[index] = text
        persist()
    }

    func resetAwayUtterances() {
        awayUtterances = defaultAwayUtterances
        persist()
    }

    func statLine(for task: FocusTask) -> String {
        let taskStat = stats.taskStats[task.id] ?? TaskStat(completed: 0, failed: 0)
        return "✓ \(taskStat.completed) | ✗ \(taskStat.failed)"
    }

    func minuteLine(for task: FocusTask) -> String {
        let minutes = stats.taskTimeSpent[task.id, default: 0]
        return minutes > 0 ? "\(minutes) min spent" : ""
    }

    private func startHeartbeat() {
        stopHeartbeat()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            self.syncRemainingSeconds()
            if self.remainingSeconds == 0 {
                self.completeTimer()
            }
        }
    }

    private func stopHeartbeat() {
        timer?.invalidate()
        timer = nil
    }

    private func syncRemainingSeconds() {
        guard let timerStartDate, !timerCompleted else {
            remainingSeconds = timerCompleted ? 0 : timerDuration
            return
        }
        let elapsed = Int(Date().timeIntervalSince(timerStartDate))
        remainingSeconds = max(timerDuration - elapsed, 0)
    }

    private func migrateDayIfNeeded() {
        let today = DateFormatter.focusDay.string(from: Date())
        if stats.lastDate != today {
            stats.todayBlocks = 0
            stats.lastDate = today
            persist()
        }
    }

    private func persist() {
        let state = PersistedState(
            tasks: tasks,
            stats: stats,
            activeTaskID: activeTaskID,
            timerStartDate: timerStartDate,
            timerCompleted: timerCompleted,
            isCameraEnabled: isCameraEnabled,
            awayUtterances: awayUtterances
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
}

private final class CameraManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var presenceState: PresenceState = .idle
    @Published private(set) var secondsAway: Int = 0
    let session = AVCaptureSession()

    private var isConfigured = false
    private let videoOutput = AVCaptureVideoDataOutput()
    private let visionQueue = DispatchQueue(label: "CameraManager.vision")
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var awayStartedAt: Date?
    private var didTriggerAwayFailure = false
    private var onAwayThresholdExceeded: (() -> Void)?
    private let awayThresholdSeconds = 6
    private let requiredMissCount = 8
    private let awaySpeechRepeatInterval: TimeInterval = 4
    private var consecutiveMissCount = 0
    private var lastAwaySpeechAt: Date?
    private var awayUtterances = defaultAwayUtterances
    private var awayUtteranceIndex = 0
    private var isMonitoringActive = false

    enum PresenceState {
        case idle
        case present
        case away
        case noPermission
        case error
    }

    var presenceTitle: String {
        switch presenceState {
        case .idle:
            return "Stay on Task ready"
        case .present:
            return "Presence detected"
        case .away:
            return "You're away"
        case .noPermission:
            return "Camera permission required"
        case .error:
            return "Stay on Task error"
        }
    }

    var presenceColor: Color {
        switch presenceState {
        case .idle:
            return .white.opacity(0.7)
        case .present:
            return .green
        case .away:
            return .orange
        case .noPermission:
            return .red
        case .error:
            return .red
        }
    }

    override init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        super.init()
    }

    func setAwayThresholdAction(_ action: @escaping () -> Void) {
        onAwayThresholdExceeded = action
    }

    func updateAwayUtterances(_ utterances: [String]) {
        if utterances.isEmpty {
            awayUtterances = defaultAwayUtterances
            return
        }
        awayUtterances = utterances
    }

    @MainActor
    func ensurePermissionAndStart() async {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authorizationStatus == .authorized {
            configureIfNeeded()
            startSession()
            return
        }

        if authorizationStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
            if granted {
                configureIfNeeded()
                startSession()
            } else {
                presenceState = .noPermission
            }
            return
        }

        presenceState = .noPermission
    }

    func stopSession() {
        isMonitoringActive = false
        if session.isRunning {
            session.stopRunning()
        }
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async {
            self.awayStartedAt = nil
            self.secondsAway = 0
            self.didTriggerAwayFailure = false
            self.consecutiveMissCount = 0
            self.lastAwaySpeechAt = nil
            self.presenceState = .idle
        }
    }

    @MainActor
    private func configureIfNeeded() {
        if isConfigured {
            return
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.sessionPreset = .medium
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        session.commitConfiguration()
        isConfigured = true
    }

    private func startSession() {
        if session.isRunning {
            return
        }
        isMonitoringActive = true
        DispatchQueue.main.async {
            self.didTriggerAwayFailure = false
            self.awayStartedAt = nil
            self.secondsAway = 0
            self.consecutiveMissCount = 0
            self.lastAwaySpeechAt = nil
            self.presenceState = .idle
        }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    private func handleDetection(hasPerson: Bool) {
        DispatchQueue.main.async {
            if self.isMonitoringActive == false {
                return
            }
            if hasPerson {
                self.consecutiveMissCount = 0
                self.awayStartedAt = nil
                self.secondsAway = 0
                self.didTriggerAwayFailure = false
                self.lastAwaySpeechAt = nil
                self.presenceState = .present
                return
            }

            self.consecutiveMissCount += 1
            if self.consecutiveMissCount < self.requiredMissCount {
                if self.presenceState == .idle {
                    self.presenceState = .idle
                } else {
                    self.presenceState = .present
                }
                return
            }

            self.presenceState = .away
            if self.awayStartedAt == nil {
                self.awayStartedAt = Date()
                self.speakAwayAlertIfNeeded(force: true)
            }
            guard let awayStartedAt = self.awayStartedAt else {
                self.secondsAway = 0
                return
            }
            self.secondsAway = Int(Date().timeIntervalSince(awayStartedAt))
            self.speakAwayAlertIfNeeded(force: false)

            if self.secondsAway >= self.awayThresholdSeconds && !self.didTriggerAwayFailure {
                self.didTriggerAwayFailure = true
                self.onAwayThresholdExceeded?()
            }
        }
    }

    private func speakAwayAlertIfNeeded(force: Bool) {
        if isMonitoringActive == false {
            return
        }
        let now = Date()
        if !force {
            if let lastAwaySpeechAt, now.timeIntervalSince(lastAwaySpeechAt) < awaySpeechRepeatInterval {
                return
            }
            if speechSynthesizer.isSpeaking {
                return
            }
        }

        if awayUtterances.isEmpty {
            return
        }

        let utterance = AVSpeechUtterance(string: awayUtterances[awayUtteranceIndex % awayUtterances.count])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        awayUtteranceIndex += 1
        lastAwaySpeechAt = now
        speechSynthesizer.speak(utterance)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if isMonitoringActive == false {
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            DispatchQueue.main.async {
                self.presenceState = .error
            }
            return
        }

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
            let faceRequest = VNDetectFaceRectanglesRequest()
            let upperBodyRequest = VNDetectHumanRectanglesRequest()
            upperBodyRequest.upperBodyOnly = true
            try handler.perform([faceRequest, upperBodyRequest])

            let hasFace = !(faceRequest.results ?? []).isEmpty
            let hasUpperBody = !(upperBodyRequest.results ?? []).isEmpty
            self.handleDetection(hasPerson: hasFace || hasUpperBody)
        } catch {
            DispatchQueue.main.async {
                self.presenceState = .error
            }
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Preview layer is required")
        }
        return layer
    }
}

private struct TaskCard: View {
    let task: FocusTask
    let statLine: String
    let minuteLine: String
    let isActive: Bool
    let isDisabled: Bool
    let onStart: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(statLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    if !minuteLine.isEmpty {
                        Text(minuteLine)
                            .font(.caption)
                            .foregroundStyle(.cyan)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Button(isActive ? "In Progress" : "Start 5-Minute Block") {
                onStart()
            }
            .disabled(isDisabled || isActive)
            .modifier(TaskCardButtonStyleModifier(isActive: isActive))
        }
        .padding()
        .background(isActive ? Color.cyan.opacity(0.16) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .opacity(isDisabled ? 0.45 : 1)
    }
}

private struct EditTaskView: View {
    let task: FocusTask
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task name", text: $name)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedName.count >= 2 {
                            onSave(trimmedName)
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

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

private struct SettingsView<AwaySpeechContent: View, SettingsContent: View>: View {
    let awaySpeechSection: AwaySpeechContent
    let settingsSection: SettingsContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        awaySpeechSection
                        settingsSection
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.cyan.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(configuration.isPressed ? 0.7 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct TaskCardButtonStyleModifier: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.buttonStyle(SecondaryButtonStyle())
        } else {
            content.buttonStyle(PrimaryButtonStyle())
        }
    }
}

private extension DateFormatter {
    static let focusDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
