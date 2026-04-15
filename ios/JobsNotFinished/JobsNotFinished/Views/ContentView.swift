import SwiftUI
import AVFoundation
import Vision
import StoreKit
import UserNotifications

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
    @State private var newTaskName = ""
    @State private var searchText = ""
    @State private var pendingAction: PendingAction?
    @State private var pendingStartAction: PendingStartAction?
    @State private var isQuitConfirmationPresented = false
    @State private var isUpgradePresented = false
    @State private var pendingUpgradeAction: PendingUpgradeAction?
    @State private var editingTask: FocusTask?
    @State private var isDetailsPresented = false
    @State private var hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
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
                        recentBlocksSection
                        addTaskSection
                        tasksSection
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $isDetailsPresented) {
                SettingsView(
                    voiceModeSection: voiceModeSection,
                    settingsSection: settingsSection
                )
            }
        }
        .sheet(item: $editingTask) { task in
            EditTaskView(task: task) { updatedName in
                store.renameTask(taskID: task.id, to: updatedName)
            }
        }
        .sheet(isPresented: $isUpgradePresented) {
            UpgradeView(
                remainingFreeContracts: store.remainingFreeContracts,
                product: purchaseManager.product,
                isLoading: purchaseManager.isLoading,
                errorMessage: purchaseManager.errorMessage,
                onUnlock: {
                    if purchaseManager.product == nil {
                        Task {
                            await purchaseManager.prepare()
                        }
                        return
                    }
                    pendingUpgradeAction = .purchase
                    isUpgradePresented = false
                },
                onRestore: {
                    pendingUpgradeAction = .restore
                    isUpgradePresented = false
                }
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { _ in }
        )) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                hasSeenOnboarding = true
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
                        store.clearAll()
                        cameraManager.stopSession()
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
        .task {
            await purchaseManager.prepare()
            store.setProUnlocked(purchaseManager.isUnlocked)
            await store.prepareNotifications()
            store.resumeTimerIfNeeded()
            cameraManager.setAwayThresholdAction {
                if store.canUseEnforcement && store.isTimerActive && !store.timerCompleted {
                    store.stopTimer(asFailure: true)
                }
            }
            cameraManager.updateAwayUtterances(store.awayUtterances)
            if store.canUseEnforcement && store.isCameraEnabled && store.isTimerActive {
                await cameraManager.ensurePermissionAndStart()
            }
        }
        .onChange(of: store.isTimerActive) { _, isActive in
            if isActive {
                if store.canUseEnforcement && store.isCameraEnabled {
                    Task {
                        await cameraManager.ensurePermissionAndStart()
                    }
                }
            } else {
                cameraManager.stopSession()
            }
        }
        .onChange(of: store.isCameraEnabled) { _, isEnabled in
            if isEnabled && store.isTimerActive && store.canUseEnforcement {
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
            } else if store.isCameraEnabled && store.isTimerActive && store.canUseEnforcement {
                Task {
                    await cameraManager.ensurePermissionAndStart()
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
                if store.isCameraEnabled && store.isTimerActive && !store.timerCompleted && store.canUseEnforcement {
                    Task {
                        await cameraManager.ensurePermissionAndStart()
                    }
                }
            }
        }
        .onChange(of: store.awayUtterances) { _, utterances in
            cameraManager.updateAwayUtterances(utterances)
        }
        .onChange(of: purchaseManager.isUnlocked) { _, isUnlocked in
            store.setProUnlocked(isUnlocked)
        }
        .onChange(of: isUpgradePresented) { _, isPresented in
            if isPresented == false, let pendingUpgradeAction {
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)

                    switch pendingUpgradeAction {
                    case .purchase:
                        let unlocked = await purchaseManager.purchaseUnlock()
                        if unlocked == false, purchaseManager.errorMessage != nil {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            isUpgradePresented = true
                        }
                    case .restore:
                        let unlocked = await purchaseManager.restorePurchases()
                        store.setProUnlocked(unlocked)
                        if unlocked == false, purchaseManager.errorMessage != nil {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            isUpgradePresented = true
                        }
                    }

                    self.pendingUpgradeAction = nil
                }
            }
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
            StatCard(title: "Failures", value: "\(store.stats.failedBlocks)")
        }
    }

    private var recentBlocksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            if store.stats.recentBlocks.isEmpty {
                Text("Your last contracts show up here.")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.stats.recentBlocks.prefix(10)) { block in
                        RecentBlockRow(block: block)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
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
                if store.addTask(named: trimmedName) {
                    newTaskName = ""
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Text("Type one task and either commit now or save it for later.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            if store.isProUnlocked == false {
                Text("Free: \(store.freeContractsPerDayLimit) contracts per day, honor system only. Pro adds camera enforcement and unlimited contracts.")
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
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)

                VStack(spacing: 8) {
                    Text(store.formattedRemaining)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(store.timerCompleted ? "Contract complete" : "Stay locked in")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if store.timerCompleted {
                VStack(spacing: 12) {
                    Text("5-minute contract complete")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    Text("Start another contract or go back to your task list.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))

                    Button("Start Another 5-Minute Contract") {
                        pendingStartAction = .restartActiveTask
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Return to Task List") {
                        store.returnToTasks()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                HStack(spacing: 12) {
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
            Text("Leaving early counts as a failure and resets your streak.")
        }
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Camera Enforcement")
                            .font(.headline)
                            .foregroundStyle(.white)
                        if store.isProUnlocked == false {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    if store.isProUnlocked == false {
                        Text("Pro — leave the frame and your contract fails")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if store.isProUnlocked {
                    Toggle("", isOn: Binding(
                        get: { store.isCameraEnabled },
                        set: { store.isCameraEnabled = $0 }
                    ))
                    .tint(.cyan)
                } else {
                    Button("Unlock") {
                        isUpgradePresented = true
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                }
            }

            if store.isProUnlocked && store.isCameraEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Leave the frame and your contract fails immediately.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                    if cameraManager.authorizationStatus == .denied || cameraManager.authorizationStatus == .restricted {
                        Text("Camera access is blocked. Enable it in Settings.")
                            .foregroundStyle(.orange)
                    } else if store.isTimerActive {
                        HStack {
                            Circle()
                                .fill(cameraManager.presenceState == .present ? .green : .red)
                                .frame(width: 12, height: 12)

                            Text(cameraManager.presenceState == .present ? "Present — contract live" : "Away — get back now")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            if store.isProUnlocked == false {
                Text("Free users run on the honor system. Pro enforces it.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
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
                                pendingStartAction = .taskID(task.id)
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

            if store.isProUnlocked {
                Text("Unlimited contracts unlocked.")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("\(store.remainingFreeContracts) free contracts left today.")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Button("Unlock Pro") {
                    isUpgradePresented = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }

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

    private var voiceModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stay on Task Voice")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("Choose how Done in 5 talks to you when you drift away from the contract.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            Picker("Voice Mode", selection: Binding(
                get: { store.selectedVoiceMode },
                set: { store.updateVoiceMode($0) }
            )) {
                ForEach(AwayVoiceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.isProUnlocked == false)

            Text(store.selectedVoiceMode.description)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))

            if store.isProUnlocked == false {
                Text("Strict voice unlocks with the forever upgrade.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(store.awayUtterances.enumerated()), id: \.offset) { index, line in
                    voiceLineRow(index: index, line: line)
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private func voiceLineRow(index: Int, line: String) -> some View {
        if store.selectedVoiceMode == .supportive {
            TextField(
                "Voice line \(index + 1)",
                text: Binding(
                    get: { store.supportiveUtterances[index] },
                    set: { store.updateSupportiveUtterance(at: index, to: $0) }
                ),
                axis: .vertical
            )
            .focused($focusedField, equals: .supportiveVoiceLine(index))
            .textInputAutocapitalization(.sentences)
            .padding()
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
        } else {
            Text(line)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
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
        store.tasks.filter { $0.isFinished == false }
    }

    private func runPendingStartAction(_ action: PendingStartAction) {
        print("🔍 runPendingStartAction: \(action)")
        if store.canStartContract == false {
            print("🔍 Cannot start contract - showing upgrade")
            isUpgradePresented = true
            return
        }

        switch action {
        case .taskName(let name):
            print("🔍 Starting timer for name: \(name)")
            let started = store.startTimerForTaskNamed(name)
            print("🔍 Timer started: \(started), isTimerPresentationActive: \(store.isTimerPresentationActive)")
            if started {
                newTaskName = ""
            }
        case .taskID(let id):
            store.startTimer(for: id)
        case .restartActiveTask:
            store.restartCompletedTimer()
        }
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

private enum BlockOutcome: String, Codable {
    case completed
    case failed
}

private struct RecentBlock: Identifiable, Codable, Equatable {
    let id: UUID
    var taskName: String
    var endedAt: Date
    var outcome: BlockOutcome
    var heldSeconds: Int
    var streakAfter: Int
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
    var recentBlocks: [RecentBlock]

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
            completedTasksList: [],
            recentBlocks: []
        )
    }
}

@MainActor
private final class PurchaseManager: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var isUnlocked = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let productID = "com.5minutesblockstimer.pro.lifetime"
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        await loadProduct()
        await refreshEntitlements()
    }

    func purchaseUnlock() async -> Bool {
        errorMessage = nil

        if product == nil {
            await loadProduct()
        }

        guard let product else {
            errorMessage = "StoreKit did not return the lifetime unlock product. The configured product ID matches App Store Connect, so test on a real device with the sandbox environment and retry after Apple propagation."
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verify(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isUnlocked
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Purchase is pending approval."
                return false
            @unknown default:
                errorMessage = "Purchase returned an unknown result."
                return false
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    func restorePurchases() async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isUnlocked == false {
                errorMessage = "No lifetime unlock purchase was found to restore."
            }
            return isUnlocked
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
            return false
        }
    }

    private func loadProduct() async {
        errorMessage = nil

        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                self.product = nil
                errorMessage = "StoreKit returned no product for \(productID). The identifier matches App Store Connect, so the remaining checks are real-device sandbox testing and Apple propagation."
                return
            }
            self.product = product
        } catch {
            self.product = nil
            errorMessage = "Failed to load purchase options: \(error.localizedDescription)"
        }
    }

    private func refreshEntitlements() async {
        var hasUnlock = false

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verify(result)
                if transaction.productID == productID {
                    hasUnlock = true
                }
            } catch {
                errorMessage = "Failed to verify current entitlement: \(error.localizedDescription)"
            }
        }

        isUnlocked = hasUnlock
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try verify(result)
                    await transaction.finish()
                    await refreshEntitlements()
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Transaction verification failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let signedType):
            return signedType
        case .unverified:
            throw NSError(domain: "PurchaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "StoreKit verification failed."])
        }
    }
}

private struct PersistedState: Codable {
    var tasks: [FocusTask]
    var stats: FocusStats
    var activeTaskID: UUID?
    var timerStartDate: Date?
    var timerCompleted: Bool
    var isCameraEnabled: Bool
    var selectedVoiceMode: AwayVoiceMode
    var supportiveUtterances: [String]
    var isProUnlocked: Bool

    init(tasks: [FocusTask], stats: FocusStats, activeTaskID: UUID?, timerStartDate: Date?, timerCompleted: Bool, isCameraEnabled: Bool, selectedVoiceMode: AwayVoiceMode, supportiveUtterances: [String], isProUnlocked: Bool) {
        self.tasks = tasks
        self.stats = stats
        self.activeTaskID = activeTaskID
        self.timerStartDate = timerStartDate
        self.timerCompleted = timerCompleted
        self.isCameraEnabled = isCameraEnabled
        self.selectedVoiceMode = selectedVoiceMode
        self.supportiveUtterances = supportiveUtterances
        self.isProUnlocked = isProUnlocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([FocusTask].self, forKey: .tasks)
        stats = try container.decode(FocusStats.self, forKey: .stats)
        activeTaskID = try container.decodeIfPresent(UUID.self, forKey: .activeTaskID)
        timerStartDate = try container.decodeIfPresent(Date.self, forKey: .timerStartDate)
        timerCompleted = try container.decode(Bool.self, forKey: .timerCompleted)
        isCameraEnabled = try container.decode(Bool.self, forKey: .isCameraEnabled)
        selectedVoiceMode = try container.decodeIfPresent(AwayVoiceMode.self, forKey: .selectedVoiceMode) ?? .supportive
        supportiveUtterances = try container.decodeIfPresent([String].self, forKey: .supportiveUtterances) ?? AwayVoiceMode.supportive.utterances
        isProUnlocked = try container.decodeIfPresent(Bool.self, forKey: .isProUnlocked) ?? false
    }
}

@MainActor
private final class FocusStore: ObservableObject {
    @Published var tasks: [FocusTask]
    @Published var stats: FocusStats
    @Published var activeTaskID: UUID?
    @Published var timerStartDate: Date?
    @Published var remainingSeconds: Int
    @Published var timerCompleted: Bool
    @Published var motivationalMessageIndex: Int
    @Published var isCameraEnabled: Bool
    @Published var selectedVoiceMode: AwayVoiceMode
    @Published var supportiveUtterances: [String]
    @Published var isProUnlocked: Bool

    private let persistenceKey = "focus.store.v3"
    private let timerDuration = 5 * 60
    private let freeContractsPerDay = 5
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
            selectedVoiceMode = state.selectedVoiceMode
            supportiveUtterances = state.supportiveUtterances
            isProUnlocked = state.isProUnlocked
        } else {
            tasks = []
            stats = FocusStats.initial()
            activeTaskID = nil
            timerStartDate = nil
            timerCompleted = false
            isCameraEnabled = true
            selectedVoiceMode = .supportive
            supportiveUtterances = AwayVoiceMode.supportive.utterances
            isProUnlocked = false
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

    var awayUtterances: [String] {
        if selectedVoiceMode == .supportive {
            return supportiveUtterances
        }
        return AwayVoiceMode.strict.utterances
    }

    var remainingFreeContracts: Int {
        max(freeContractsPerDay - stats.todayBlocks, 0)
    }

    var freeContractsPerDayLimit: Int {
        freeContractsPerDay
    }

    var canStartContract: Bool {
        isProUnlocked || remainingFreeContracts > 0
    }

    var canUseEnforcement: Bool {
        isProUnlocked
    }

    func prepareNotifications() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        if isTimerActive && !timerCompleted {
            scheduleCompletionNotification()
        }
    }

    func resumeTimerIfNeeded() {
        guard activeTaskID != nil else {
            return
        }
        syncRemainingSeconds()
        if remainingSeconds == 0 {
            completeTimer()
            return
        }
        if !timerCompleted {
            scheduleCompletionNotification()
            startHeartbeat()
        }
    }

    func prepareForBackground() {
        guard isTimerActive, !timerCompleted else {
            return
        }
        syncRemainingSeconds()
        scheduleCompletionNotification()
        stopHeartbeat()
        persist()
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
        scheduleCompletionNotification()
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
        cancelCompletionNotification()
        if asFailure, let activeTaskID {
            let heldSeconds = max(timerDuration - remainingSeconds, 0)
            let taskName = tasks.first(where: { $0.id == activeTaskID })?.name ?? ""

            stats.todayBlocks += 1
            stats.totalBlocks += 1
            stats.failedBlocks += 1
            stats.streak = 0

            stats.recentBlocks.insert(
                RecentBlock(
                    id: UUID(),
                    taskName: taskName,
                    endedAt: Date(),
                    outcome: .failed,
                    heldSeconds: heldSeconds,
                    streakAfter: stats.streak
                ),
                at: 0
            )
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
        cancelCompletionNotification()
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
        cancelCompletionNotification()
        timerCompleted = true
        remainingSeconds = 0

        let taskName = tasks.first(where: { $0.id == activeTaskID })?.name ?? ""

        stats.todayBlocks += 1
        stats.totalBlocks += 1
        stats.completedBlocks += 1
        stats.streak += 1

        stats.recentBlocks.insert(
            RecentBlock(
                id: UUID(),
                taskName: taskName,
                endedAt: Date(),
                outcome: .completed,
                heldSeconds: timerDuration,
                streakAfter: stats.streak
            ),
            at: 0
        )

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
        cancelCompletionNotification()
        tasks = []
        stats = FocusStats.initial()
        activeTaskID = nil
        timerStartDate = nil
        timerCompleted = false
        remainingSeconds = timerDuration
        selectedVoiceMode = .supportive
        persist()
    }

    func updateVoiceMode(_ mode: AwayVoiceMode) {
        if mode == .strict && isProUnlocked == false {
            return
        }
        selectedVoiceMode = mode
        persist()
    }

    func updateSupportiveUtterance(at index: Int, to value: String) {
        if supportiveUtterances.indices.contains(index) == false {
            return
        }
        supportiveUtterances[index] = value
        persist()
    }

    func setProUnlocked(_ isUnlocked: Bool) {
        isProUnlocked = isUnlocked
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
            remainingSeconds: remainingSeconds,
            timerCompleted: timerCompleted,
            isCameraEnabled: isCameraEnabled,
            selectedVoiceMode: selectedVoiceMode,
            supportiveUtterances: supportiveUtterances,
            awayFailureSeconds: 6
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func scheduleCompletionNotification() {
        guard let timerStartDate, let activeTask else {
            cancelCompletionNotification()
            return
        }
        let remaining = max(timerDuration - Int(Date().timeIntervalSince(timerStartDate)), 0)
        guard remaining > 0 else {
            cancelCompletionNotification()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "JOB'S NOT FINISHED"
        content.body = "\(activeTask.name) — 5 minutes done. Keep going or move on?"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(remaining), repeats: false)
        let request = UNNotificationRequest(identifier: FocusNotification.timerCompleteIdentifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [FocusNotification.timerCompleteIdentifier])
        center.add(request)
    }

    private func cancelCompletionNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [FocusNotification.timerCompleteIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [FocusNotification.timerCompleteIdentifier])
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
    private var awayUtterances = AwayVoiceMode.supportive.utterances
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
            fatalError("Away utterances are required")
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

            Button(isActive ? "In Progress" : "Start 5-Minute Contract") {
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

private struct SettingsView<VoiceModeContent: View, SettingsContent: View>: View {
    let voiceModeSection: VoiceModeContent
    let settingsSection: SettingsContent

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    voiceModeSection
                    settingsSection
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UpgradeView: View {
    let remainingFreeContracts: Int
    let product: Product?
    let isLoading: Bool
    let errorMessage: String?
    let onUnlock: () -> Void
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("Camera Enforcement")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Leave the frame and your contract fails.\nNo honor system. No excuses.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))

                    Text("Free contracts left today: \(remainingFreeContracts)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Camera enforcement (fail on leave)")
                        Text("Unlimited 5-minute contracts")
                        Text("Strict accountability voice")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                    Button("Unlock Pro") {
                        onUnlock()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading)

                    Button("Restore Purchase") {
                        onRestore()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isLoading)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.orange)
                    } else if product == nil {
                        Text("StoreKit will show the price at checkout. If purchase options are missing, test on a real device and allow Apple time to propagate the IAP.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Button("Not Now") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isLoading)
                }
                .padding(20)
            }
            .navigationBarHidden(true)
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

private struct RecentBlockRow: View {
    let block: RecentBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(block.taskName.isEmpty ? "(Unnamed task)" : block.taskName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(block.outcome == .completed ? "COMPLETED" : "FAILED")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(block.outcome == .completed ? .green : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }

                Text(durationLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Text("Streak \(block.streakAfter)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var durationLine: String {
        let held = Self.format(seconds: block.heldSeconds)
        let total = Self.format(seconds: 5 * 60)
        if block.outcome == .completed {
            return "Held: \(held)"
        }
        return "Held: \(held) / \(total)"
    }

    private static func format(seconds: Int) -> String {
        let m = max(seconds, 0) / 60
        let s = max(seconds, 0) % 60
        return String(format: "%d:%02d", m, s)
    }
}
