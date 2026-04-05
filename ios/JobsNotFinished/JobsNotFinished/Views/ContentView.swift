import SwiftUI
import AVFoundation
import Vision
import StoreKit
import UserNotifications

struct ContentView: View {
    private enum FocusedField: Hashable {
        case newTaskName
        case searchText
        case supportiveVoiceLine(Int)
    }

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = FocusStore()
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var purchaseManager = PurchaseManager()
    
    @FocusState private var focusedField: FocusedField?
    @State private var newTaskName = ""
    @State private var searchText = ""
    @State private var pendingAction: PendingAction?
    @State private var pendingStartAction: PendingStartAction?
    @State private var pendingUpgradeAction: PendingUpgradeAction?
    @State private var isUpgradePresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        statsSection
                        addTaskSection
                        tasksSection
                        settingsSection
                    }
                    .padding(.horizontal, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Done in 5")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        pendingAction = .clearAll
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.white)
                    }
                }
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
                        do {
                            try store.clearAll()
                            cameraManager.stopSession()
                        } catch {
                            print("Failed to clear all: \(error)")
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .alert(item: $pendingStartAction) { action in
            Alert(
                title: Text("Start focus contract?"),
                message: Text(action.message),
                primaryButton: .default(Text("Start Contract")) {
                    runPendingStartAction(action)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $isUpgradePresented) {
            UpgradeView(
                purchaseManager: purchaseManager,
                pendingAction: $pendingUpgradeAction
            )
            .interactiveDismissDisabled()
        }
        .task {
            await purchaseManager.prepare()
            store.setProUnlocked(purchaseManager.isUnlocked)
            do {
                try await store.prepareNotifications()
            } catch {
                print("Failed to prepare notifications: \(error)")
            }
            store.resumeTimerIfNeeded()
            cameraManager.setAwayThresholdAction {
                if store.isTimerActive && !store.timerState.isCompleted {
                    store.stopTimer(asFailure: true)
                }
            }
            cameraManager.updateAwayUtterances(store.awayUtterances)
            if store.taskState.isCameraEnabled && store.isTimerActive {
                do {
                    try await cameraManager.ensurePermissionAndStart()
                } catch {
                    print("Failed to start camera: \(error)")
                }
            }
        }
        .onChange(of: store.isTimerActive) { _, isActive in
            if isActive {
                if store.taskState.isCameraEnabled {
                    Task {
                        do {
                            try await cameraManager.ensurePermissionAndStart()
                        } catch {
                            print("Failed to start camera: \(error)")
                        }
                    }
                }
            } else {
                cameraManager.stopSession()
            }
        }
        .onChange(of: store.taskState.isCameraEnabled) { _, isEnabled in
            if isEnabled && store.isTimerActive {
                Task {
                    do {
                        try await cameraManager.ensurePermissionAndStart()
                    } catch {
                        print("Failed to start camera: \(error)")
                    }
                }
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
                        do {
                            try await cameraManager.ensurePermissionAndStart()
                        } catch {
                            print("Failed to start camera: \(error)")
                        }
                    }
                }
            }
        }
        .onChange(of: store.timerState.isCompleted) { _, isCompleted in
            if isCompleted {
                cameraManager.stopSession()
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(title: "Today", value: "\(store.stats.todayBlocks)")
            StatCard(title: "Streak", value: "\(store.stats.streak)")
            StatCard(title: "Rate", value: "\(store.completionRate)%")
            StatCard(title: "Failures", value: "\(store.stats.failedBlocks)")
        }
    }

    private var addTaskSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start a Task")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("Start one 5-minute contract. If you leave early, it counts as a failure.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            TextField("What are you working on?", text: $newTaskName)
                .focused($focusedField, equals: .newTaskName)
                .textInputAutocapitalization(.sentences)
                .padding()
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)

            Button("Start 5-Minute Contract") {
                focusedField = nil
                let trimmedName = newTaskName.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingStartAction = .taskName(trimmedName)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Save Task Without Starting") {
                focusedField = nil
                let trimmedName = newTaskName.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    try store.addTask(named: trimmedName)
                    newTaskName = ""
                } catch {
                    print("Failed to add task: \(error)")
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Text("Type one task and either commit now or save it for later.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            if !store.userState.isProUnlocked {
                Text("Free: 3 contracts per day. Unlock forever for unlimited contracts and strict voice mode.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
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

            HStack(spacing: 16) {
                Button("Keep Going") {
                    store.restartCompletedTimer()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Done") {
                    store.completeTimer()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
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

            if store.taskState.isCameraEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Camera accountability works while the app is open. The timer continues in background even if camera stops.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                    if cameraManager.isSessionActive {
                        HStack {
                            Circle()
                                .fill(cameraManager.presenceState == .present ? .green : .red)
                                .frame(width: 12, height: 12)

                            Text(cameraManager.presenceState == .present ? "Present" : "Away")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tasks")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    pendingAction = .resetStats
                } label: {
                    Text("Reset Stats")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            if !store.taskState.isCameraEnabled {
                TextField("Search tasks...", text: $searchText)
                    .focused($focusedField, equals: .searchText)
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }

            if filteredTasks.isEmpty {
                Text("No tasks yet. Add one above to get started.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredTasks) { task in
                        TaskRow(
                            task: task,
                            onStart: {
                                pendingStartAction = .taskID(task.id)
                            },
                            onRename: { newName in
                                do {
                                    try store.renameTask(taskID: task.id, to: newName)
                                } catch {
                                    print("Failed to rename task: \(error)")
                                }
                            },
                            onDelete: {
                                do {
                                    try store.deleteTask(taskID: task.id)
                                } catch {
                                    print("Failed to delete task: \(error)")
                                }
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .foregroundStyle(.white)

            voiceModeSection

            if !store.userState.isProUnlocked {
                Button("Upgrade to Pro") {
                    isUpgradePresented = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var voiceModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Mode")
                .font(.subheadline)
                .foregroundStyle(.white)

            Picker("Voice Mode", selection: Binding(
                get: { store.userState.selectedVoiceMode },
                set: { store.setVoiceMode($0) }
            )) {
                ForEach(AwayVoiceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(store.userState.selectedVoiceMode.description)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            if store.userState.selectedVoiceMode == .supportive && store.userState.isProUnlocked {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Supportive Messages")
                        .font(.caption)
                        .foregroundStyle(.white)

                    ForEach(store.userState.supportiveUtterances.indices, id: \.self) { index in
                        HStack {
                            TextField("Message \(index + 1)", text: Binding(
                                get: { store.userState.supportiveUtterances[index] },
                                set: { newValue in
                                    var utterances = store.userState.supportiveUtterances
                                    utterances[index] = newValue
                                    store.updateSupportiveUtterances(utterances)
                                }
                            ))
                            .focused($focusedField, equals: .supportiveVoiceLine(index))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    private var filteredTasks: [FocusTask] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            return activeTasks
        }
        return activeTasks.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    private var activeTasks: [FocusTask] {
        store.taskState.tasks.filter { !$0.isFinished }
    }

    private func runPendingStartAction(_ action: PendingStartAction) {
        if !store.canStartContract {
            isUpgradePresented = true
            return
        }

        switch action {
        case .taskName(let name):
            do {
                try store.startTimerForTaskNamed(name)
                newTaskName = ""
            } catch {
                print("Failed to start timer for task name: \(error)")
            }
        case .taskID(let id):
            do {
                try store.startTimer(for: id)
            } catch {
                print("Failed to start timer for task ID: \(error)")
            }
        case .restartActiveTask:
            store.restartCompletedTimer()
        }
    }
}

// MARK: - Supporting Views

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

private enum PendingStartAction: Identifiable {
    case taskName(String)
    case taskID(UUID)
    case restartActiveTask

    var id: String {
        switch self {
        case .taskName(let name):
            return "taskName-\(name)"
        case .taskID(let id):
            return "taskID-\(id.uuidString)"
        case .restartActiveTask:
            return "restartActiveTask"
        }
    }

    var message: String {
        switch self {
        case .taskName:
            return "If you leave early, this counts as a failure and resets your streak."
        case .taskID:
            return "This contract starts now. Leaving early counts as a failure and resets your streak."
        case .restartActiveTask:
            return "Start another 5-minute contract for this task. Leaving early counts as a failure and resets your streak."
        }
    }
}

private enum PendingUpgradeAction {
    case purchase
    case restore
}
