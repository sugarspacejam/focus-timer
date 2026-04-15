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

struct HomeContentView: View {
    private enum FocusedField: Hashable {
        case quickStart
        case librarySearch
        case awayTimeout
        case awayVoiceLines
    }

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var store = FocusStore()
    @StateObject private var cameraManager = CameraManager()

    @FocusState private var focusedField: FocusedField?

    @State private var quickStartText = ""
    @State private var isLibraryPresented = false
    @State private var isOnboardingPresented = false
    @State private var librarySearchText = ""
    @State private var libraryFilter: TaskLibraryFilter = .pinned
    @State private var isQuitConfirmationPresented = false
    @State private var isSettingsPresented = false
    @State private var editingTask: FocusTask?
    @State private var hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    @State private var quickStartValidationMessage: String?
    @State private var supportiveUtterancesText = ""
    @State private var awayFailureSecondsText = ""

    @State private var pinnedTaskIDs: Set<UUID> = []
    @AppStorage("pinnedTaskIDs") private var pinnedTaskIDsStorage: String = "[]"

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        stats
                        quickStart
                        recentTasks
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $isSettingsPresented) {
                SettingsScreen(settingsContent: settingsContent)
            }
        }
        .sheet(isPresented: $isLibraryPresented) {
            TaskLibrarySheet(
                tasks: store.taskState.tasks.filter { !$0.isFinished },
                pinnedTaskIDs: $pinnedTaskIDs,
                filter: $libraryFilter,
                searchText: $librarySearchText,
                onStart: { id in
                    runStartAction(.taskID(id))
                },
                onEdit: { task in
                    editingTask = task
                },
                onDelete: { id in
                    do {
                        try store.deleteTask(taskID: id)
                        pinnedTaskIDs.remove(id)
                        persistPinnedTaskIDs()
                    } catch {
                        print("Failed to delete task: \(error)")
                    }
                },
                onTogglePin: { id in
                    if pinnedTaskIDs.contains(id) {
                        pinnedTaskIDs.remove(id)
                    } else {
                        pinnedTaskIDs.insert(id)
                    }
                    persistPinnedTaskIDs()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                hasSeenOnboarding = true
                isOnboardingPresented = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task) { newName in
                do {
                    try store.renameTask(taskID: task.id, to: newName)
                } catch {
                    print("Failed to rename task: \(error)")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissSettingsKeyboardAndSave()
                }
            }
        }
        .onAppear {
            if !hasSeenOnboarding {
                isOnboardingPresented = true
            }
        }
        .onChange(of: hasSeenOnboarding) { _, seen in
            if seen == false {
                isOnboardingPresented = true
            }
        }
        .onChange(of: store.userState.supportiveUtterances) { _, utterances in
            let updatedText = utterances.joined(separator: "\n")
            if supportiveUtterancesText != updatedText {
                supportiveUtterancesText = updatedText
            }
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
        .task {
            loadPinnedTaskIDs()
            supportiveUtterancesText = store.userState.supportiveUtterances.joined(separator: "\n")
            awayFailureSecondsText = String(store.awayFailureSeconds)

            do {
                try await store.prepareNotifications()
            } catch {
                print("Failed to prepare notifications: \(error)")
            }

            store.resumeTimerIfNeeded()

            cameraManager.updateAwayFailureSeconds(store.awayFailureSeconds)
            cameraManager.setAwayThresholdAction {
                if store.canUseEnforcement && store.isTimerActive && !store.timerState.isCompleted {
                    store.stopTimer(asFailure: true)
                }
            }

            cameraManager.updateAwayUtterances(store.awayUtterances)

            if store.taskState.isCameraEnabled && store.isTimerActive && !store.timerState.isCompleted {
                await cameraManager.ensurePermissionAndStart()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                store.prepareForBackground()
                cameraManager.stopSession()
            }
            if phase == .active {
                store.resumeTimerIfNeeded()
                if store.taskState.isCameraEnabled && store.isTimerActive && !store.timerState.isCompleted {
                    Task {
                        await cameraManager.ensurePermissionAndStart()
                    }
                }
            }
        }
        .onChange(of: store.isTimerActive) { _, isActive in
            if isActive {
                if store.taskState.isCameraEnabled && !store.timerState.isCompleted {
                    Task {
                        await cameraManager.ensurePermissionAndStart()
                    }
                }
            } else {
                cameraManager.stopSession()
            }
        }
        .onChange(of: store.taskState.isCameraEnabled) { _, isEnabled in
            if isEnabled && store.isTimerActive && !store.timerState.isCompleted {
                Task {
                    await cameraManager.ensurePermissionAndStart()
                }
            }
            if !isEnabled {
                cameraManager.stopSession()
            }
        }
        .onChange(of: store.timerState.isCompleted) { _, completed in
            if completed {
                cameraManager.stopSession()
            } else if store.taskState.isCameraEnabled && store.isTimerActive {
                Task {
                    await cameraManager.ensurePermissionAndStart()
                }
            }
        }
        .onChange(of: store.awayUtterances) { _, utterances in
            cameraManager.updateAwayUtterances(utterances)
        }
        .onChange(of: store.awayFailureSeconds) { _, seconds in
            awayFailureSecondsText = String(seconds)
            cameraManager.updateAwayFailureSeconds(seconds)
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .awayTimeout && newValue != .awayTimeout {
                persistAwayFailureSecondsDraft()
            }

            if oldValue == .awayVoiceLines && newValue != .awayVoiceLines {
                persistSupportiveUtterancesDraft()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Done in 5")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)

                Text("One contract. Five minutes. No excuses.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    isOnboardingPresented = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    isLibraryPresented = true
                    focusedField = .librarySearch
                } label: {
                    Image(systemName: "tray.full")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func dismissSettingsKeyboardAndSave() {
        let currentFocus = focusedField
        focusedField = nil

        if currentFocus == .awayTimeout {
            persistAwayFailureSecondsDraft()
        }

        if currentFocus == .awayVoiceLines {
            persistSupportiveUtterancesDraft()
        }
    }

    private func persistAwayFailureSecondsDraft() {
        let trimmed = awayFailureSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let seconds = Int(trimmed), seconds >= 1 else {
            awayFailureSecondsText = String(store.awayFailureSeconds)
            return
        }

        if seconds != store.awayFailureSeconds {
            store.updateAwayFailureSeconds(seconds)
        }

        awayFailureSecondsText = String(store.awayFailureSeconds)
    }

    private func persistSupportiveUtterancesDraft() {
        let updatedUtterances = supportiveUtterancesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !updatedUtterances.isEmpty else {
            supportiveUtterancesText = store.userState.supportiveUtterances.joined(separator: "\n")
            return
        }

        if updatedUtterances != store.userState.supportiveUtterances {
            store.updateSupportiveUtterances(updatedUtterances)
        }

        supportiveUtterancesText = updatedUtterances.joined(separator: "\n")
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatCard(title: "Today", value: "\(store.stats.todayBlocks)")
            StatCard(title: "Completed", value: "\(store.totalCompletions)")
            StatCard(title: "Streak", value: "\(store.stats.streak)")
            StatCard(title: "Failed", value: "\(store.totalFailures)")
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Start")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Spacer()

                Button("Task Library") {
                    isLibraryPresented = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            }

            Text("What are you committing to right now?")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            TextField("What are you working on?", text: $quickStartText)
                .focused($focusedField, equals: .quickStart)
                .textInputAutocapitalization(.sentences)
                .padding()
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)

            Button("Start 5-Minute Contract") {
                focusedField = nil
                let trimmed = quickStartText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= Constants.UI.minimumTaskNameLength {
                    quickStartValidationMessage = nil
                    runStartAction(.taskName(trimmed))
                } else {
                    quickStartValidationMessage = "Enter a task name (\(Constants.UI.minimumTaskNameLength)+ characters)."
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Save to Library") {
                focusedField = nil
                let trimmed = quickStartText.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    if trimmed.count >= Constants.UI.minimumTaskNameLength {
                        quickStartValidationMessage = nil
                        try store.addTask(named: trimmed)
                        quickStartText = ""
                        isLibraryPresented = true
                    } else {
                        quickStartValidationMessage = "Enter a task name (\(Constants.UI.minimumTaskNameLength)+ characters)."
                    }
                } catch {
                    print("Failed to save task: \(error)")
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            if let quickStartValidationMessage {
                Text(quickStartValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var recentTasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Open Library") {
                    isLibraryPresented = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            }

            Text("Keep this list short. Everything else lives in the library.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            let tasks = recentTasksList
            if tasks.isEmpty {
                Text("No tasks yet. Add one above.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 10) {
                    ForEach(tasks) { task in
                        Button {
                            runStartAction(.taskID(task.id))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.name)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    Text(pinnedTaskIDs.contains(task.id) ? "Pinned" : "Tap to start")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }

                                Spacer()

                                Text("Start")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.cyan)
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("App Settings")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Camera Accountability")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text("Keeps camera checking on while the app is open. The timer still runs in background, but camera enforcement is foreground-only.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { store.taskState.isCameraEnabled },
                        set: { _ in store.toggleCamera() }
                    ))
                    .labelsHidden()
                    .tint(.cyan)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Away Timeout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Fail the block after this many seconds away from the camera.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))

                HStack(spacing: 12) {
                    TextField("6", text: $awayFailureSecondsText)
                        .focused($focusedField, equals: .awayTimeout)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)

                    Text("seconds")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Away Voice")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Edit the accountability lines spoken when you leave frame.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Away Voice Lines")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("One line per row. These are the messages spoken when camera accountability sees you away.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))

                TextEditor(text: $supportiveUtterancesText)
                    .focused($focusedField, equals: .awayVoiceLines)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSettingsKeyboardAndSave()
        }
    }

    private var recentTasksList: [FocusTask] {
        let active = store.taskState.tasks.filter { !$0.isFinished }
        let pinned = active.filter { pinnedTaskIDs.contains($0.id) }
        let unpinned = active.filter { !pinnedTaskIDs.contains($0.id) }
        let sortedPinned = pinned.sorted { $0.createdAt > $1.createdAt }
        let sortedUnpinned = unpinned.sorted { $0.createdAt > $1.createdAt }
        return Array((sortedPinned + sortedUnpinned).prefix(5))
    }

    private enum StartAction {
        case taskName(String)
        case taskID(UUID)
    }

    private func runStartAction(_ action: StartAction) {
        switch action {
        case .taskName(let name):
            do {
                _ = try store.startTimerForTaskNamed(name)
                quickStartText = ""
            } catch {
                print("Failed to start timer: \(error)")
            }
        case .taskID(let id):
            do {
                try store.startTimer(for: id)
            } catch {
                print("Failed to start timer: \(error)")
            }
        }

        isLibraryPresented = false
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
                    .trim(from: 0, to: store.timerState.isCompleted ? 1 : store.progress)
                    .stroke(
                        AngularGradient(colors: [Color.cyan, Color.orange], center: .center),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text(store.formattedRemaining)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            if store.timerState.isCompleted {
                Text("Contract complete")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text("Start another contract or go back to your task list.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 16) {
                    Button("Return to Task List") {
                        store.returnToTasks()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Start Another 5-Minute Contract") {
                        store.restartCompletedTimer()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                HStack(spacing: 16) {
                    Button("Quit Contract") {
                        isQuitConfirmationPresented = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .alert("Quit this contract?", isPresented: $isQuitConfirmationPresented) {
            Button("Keep Going", role: .cancel) {}
            Button("Yes, Fail It", role: .destructive) {
                store.stopTimer(asFailure: true)
                cameraManager.stopSession()
            }
        } message: {
            Text("Quitting early counts as a failure and resets your streak.")
        }
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Camera Accountability")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.taskState.isCameraEnabled },
                    set: { _ in store.toggleCamera() }
                ))
                .tint(.cyan)
            }

            Text("Camera accountability works while the app is open. The timer continues in background even if camera stops.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            if cameraManager.authorizationStatus == .denied || cameraManager.authorizationStatus == .restricted {
                Text("Camera access is blocked. Enable it in Settings.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if cameraManager.isSessionActive {
                HStack {
                    Circle()
                        .fill(cameraStatusColor)
                        .frame(width: 12, height: 12)

                    Text(cameraStatusText)
                        .font(.caption)
                        .foregroundStyle(.white)

                    Spacer()

                    if cameraManager.secondsAway > 0 {
                        Text("Away \(cameraManager.secondsAway)s")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var cameraStatusText: String {
        switch cameraManager.presenceState {
        case .idle:
            return "Stay on Task ready"
        case .present:
            return "Present — contract live"
        case .away:
            return "Away — get back now"
        case .noPermission:
            return "Camera permission required"
        case .error:
            return "Camera error"
        }
    }

    private var cameraStatusColor: Color {
        switch cameraManager.presenceState {
        case .idle:
            return .white.opacity(0.7)
        case .present:
            return .green
        case .away:
            return .orange
        case .noPermission, .error:
            return .red
        }
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
}

private struct SettingsScreen<SettingsContent: View>: View {
    let settingsContent: SettingsContent

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    settingsContent
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TaskLibrarySheet: View {
    let tasks: [FocusTask]
    @Binding var pinnedTaskIDs: Set<UUID>
    @Binding var filter: TaskLibraryFilter
    @Binding var searchText: String

    let onStart: (UUID) -> Void
    let onEdit: (FocusTask) -> Void
    let onDelete: (UUID) -> Void
    let onTogglePin: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack {
                        Text("Task Library")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Spacer()

                        Text("\(filteredTasks.count) tasks")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    TextField("Find a task…", text: $searchText)
                        .textInputAutocapitalization(.sentences)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)

                    HStack(spacing: 10) {
                        ForEach(TaskLibraryFilter.allCases) { option in
                            Button(option.title) {
                                filter = option
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(filter == option ? Color.black : Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(filter == option ? Color.cyan : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredTasks) { task in
                                LibraryTaskRow(
                                    task: task,
                                    isPinned: pinnedTaskIDs.contains(task.id),
                                    onStart: { onStart(task.id) },
                                    onEdit: { onEdit(task) },
                                    onDelete: { onDelete(task.id) },
                                    onTogglePin: { onTogglePin(task.id) }
                                )
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(16)
            }
        }
    }

    private var filteredTasks: [FocusTask] {
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
}

private struct LibraryTaskRow: View {
    let task: FocusTask
    let isPinned: Bool
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(isPinned ? "Pinned" : "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
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
                .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Button("Edit") {
                    onEdit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

                Button("Delete") {
                    onDelete()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
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
                TextField("Task name", text: $name)
            }
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
