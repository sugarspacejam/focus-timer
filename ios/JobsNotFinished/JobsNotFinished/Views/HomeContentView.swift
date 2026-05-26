import SwiftUI
import UIKit

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
    private let taskNameMinimumScaleFactor: CGFloat = 0.82

    private enum FocusedField: Hashable {
        case quickStart
        case librarySearch
        case awayTimeout
        case awayVoiceLines
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var isLedgerPresented = false
    @State private var editingTask: FocusTask?
    @State private var hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    @State private var quickStartValidationMessage: String?
    @State private var supportiveUtterances: [String] = []
    @State private var awayFailureSecondsText = ""
    @State private var isResetConfirmationPresented = false
    @State private var resetConfirmationText = ""

    @State private var pinnedTaskIDs: Set<UUID> = []
    @AppStorage("pinnedTaskIDs") private var pinnedTaskIDsStorage: String = "[]"

    private var isLightTheme: Bool {
        colorScheme == .light
    }

    private var screenBackground: LinearGradient {
        if isLightTheme {
            return LinearGradient(
                colors: [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryTextColor: Color {
        isLightTheme ? .black : .white
    }

    private var secondaryTextColor: Color {
        isLightTheme ? .black.opacity(0.65) : .white.opacity(0.65)
    }

    private var tertiaryTextColor: Color {
        isLightTheme ? .black.opacity(0.5) : .white.opacity(0.6)
    }

    private var cardBackgroundColor: Color {
        isLightTheme ? .white.opacity(0.85) : .white.opacity(0.07)
    }


    private var subtleFillColor: Color {
        isLightTheme ? .black.opacity(0.05) : .white.opacity(0.08)
    }

    private var rowBackgroundColor: Color {
        isLightTheme ? .black.opacity(0.04) : .white.opacity(0.05)
    }

    private var shouldKeepScreenAwake: Bool {
        store.isTimerActive && !store.timerState.isCompleted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                screenBackground
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
        .preferredColorScheme(store.preferredColorScheme)
        .sheet(isPresented: $isLibraryPresented) {
            TaskLibrarySheet(
                tasks: store.taskState.tasks.filter { !$0.isFinished },
                pinnedTaskIDs: $pinnedTaskIDs,
                filter: $libraryFilter,
                searchText: $librarySearchText,
                onStart: { id in
                    Task {
                        await runStartAction(.taskID(id))
                    }
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
        .sheet(isPresented: $isLedgerPresented) {
            LedgerView(entries: ledgerEntries)
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
            updateIdleTimerState()
            if !hasSeenOnboarding {
                isOnboardingPresented = true
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: hasSeenOnboarding) { _, seen in
            if seen == false {
                isOnboardingPresented = true
            }
        }
        .onChange(of: store.userState.supportiveUtterances) { _, utterances in
            if supportiveUtterances != utterances {
                supportiveUtterances = utterances
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.isTimerPresentationActive },
            set: { _ in }
        )) {
            TimerModalView(
                activeTimerSection: activeTimerSection
            )
            .interactiveDismissDisabled(true)
        }
        .task {
            loadPinnedTaskIDs()
            supportiveUtterances = store.userState.supportiveUtterances
            awayFailureSecondsText = String(store.awayFailureSeconds)

            do {
                try await store.prepareNotifications()
            } catch {
                print("Failed to prepare notifications: \(error)")
            }

            store.resumeTimerIfNeeded()

            cameraManager.updateAwayFailureSeconds(store.awayFailureSeconds)
            cameraManager.setAwayThresholdAction {
                if store.isTimerActive && !store.timerState.isCompleted {
                    store.stopTimer(asFailure: true)
                }
            }

            cameraManager.updateAwayUtterances(store.awayUtterances)

            if store.isTimerActive && !store.timerState.isCompleted {
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
                if store.isTimerActive && !store.timerState.isCompleted {
                    Task {
                        await cameraManager.ensurePermissionAndStart()
                    }
                }
            }
        }
        .onChange(of: store.isTimerActive) { _, isActive in
            updateIdleTimerState()
            if isActive {
                if !store.timerState.isCompleted {
                    Task {
                        await cameraManager.ensurePermissionAndStart()
                    }
                }
            } else {
                cameraManager.stopSession()
            }
        }
        .onChange(of: store.timerState.isCompleted) { _, completed in
            updateIdleTimerState()
            if completed {
                cameraManager.stopSession()
            } else if store.isTimerActive {
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
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)

                Text("Camera contracts for avoided tasks.")
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    isLedgerPresented = true
                } label: {
                    ZStack {
                        Image(systemName: "book.closed")
                            .font(.title3)
                            .foregroundStyle(primaryTextColor)
                            .padding(12)
                            .background(subtleFillColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        
                        // Badge showing kept count
                        if store.stats.completedBlocks > 0 {
                            Text("\(store.stats.completedBlocks)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green))
                                .offset(x: 8, y: -8)
                        }
                    }
                }

                Button {
                    isLibraryPresented = true
                    focusedField = .librarySearch
                } label: {
                    Image(systemName: "tray.full")
                        .font(.title3)
                        .foregroundStyle(primaryTextColor)
                        .padding(12)
                        .background(subtleFillColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(primaryTextColor)
                        .padding(12)
                        .background(subtleFillColor)
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

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = shouldKeepScreenAwake
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
        let updatedUtterances = supportiveUtterances
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !updatedUtterances.isEmpty else {
            supportiveUtterances = store.userState.supportiveUtterances
            return
        }

        if updatedUtterances != store.userState.supportiveUtterances {
            store.updateSupportiveUtterances(updatedUtterances)
        }

        supportiveUtterances = updatedUtterances
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatCard(title: "Today", value: "\(store.stats.todayBlocks)")
            StatCard(title: "Total", value: "\(store.totalCompletions)")
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What are you avoiding?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Button("Task Library") {
                    isLibraryPresented = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            }

            Text("5-minute camera contract. No escape.")
                .font(.caption)
                .foregroundStyle(secondaryTextColor)

            TextField("Send email to boss / Open job form / Reply to Dana", text: $quickStartText)
                .focused($focusedField, equals: .quickStart)
                .textInputAutocapitalization(.sentences)
                .padding()
                .background(subtleFillColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(primaryTextColor)

            Button("Start 5-Minute Contract") {
                focusedField = nil
                let trimmed = quickStartText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= Constants.UI.minimumTaskNameLength {
                    quickStartValidationMessage = nil
                    Task {
                        await runStartAction(.taskName(trimmed))
                    }
                } else {
                    quickStartValidationMessage = "Enter a task name (\(Constants.UI.minimumTaskNameLength)+ characters)."
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Save to Library") {
                focusedField = nil
                let trimmed = quickStartText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= Constants.UI.minimumTaskNameLength {
                    Task {
                        await saveTaskToLibrary(named: trimmed)
                    }
                } else {
                    quickStartValidationMessage = "Enter a task name (\(Constants.UI.minimumTaskNameLength)+ characters)."
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
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var recentTasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Button("Open Library") {
                    isLibraryPresented = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            }

            Text("Keep this list short. Everything else lives in the library.")
                .font(.caption)
                .foregroundStyle(secondaryTextColor)

            let tasks = recentTasksList
            if tasks.isEmpty {
                Text("No tasks yet. Add one above.")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 10) {
                    ForEach(tasks) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.name)
                                    .font(.headline)
                                    .foregroundStyle(primaryTextColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(taskNameMinimumScaleFactor)
                                    .allowsTightening(true)
                                    .truncationMode(.tail)

                                Text(pinnedTaskIDs.contains(task.id) ? "Pinned" : "Long press to edit")
                                    .font(.caption)
                                    .foregroundStyle(tertiaryTextColor)
                            }

                            Spacer()

                            Button("Start") {
                                Task {
                                    await runStartAction(.taskID(task.id))
                                }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.cyan)
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(rowBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .onLongPressGesture {
                            editingTask = task
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("App Settings")
                .font(.title3.weight(.bold))
                .foregroundStyle(primaryTextColor)

            Button {
                isOnboardingPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Quick Guide")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(primaryTextColor)

                        Text("See the onboarding walkthrough again.")
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.cyan)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(subtleFillColor)
                )
            }
            .buttonStyle(.plain)


            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                Picker("Appearance", selection: Binding(
                    get: { store.themeMode },
                    set: { store.setThemeMode($0) }
                )) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Choose Dark, Light, or follow the system setting.")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Away Timeout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                Text("Fail the block after this many seconds away from the camera.")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)

                HStack(spacing: 12) {
                    TextField("6", text: $awayFailureSecondsText)
                        .focused($focusedField, equals: .awayTimeout)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(subtleFillColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(primaryTextColor)

                    Text("seconds")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Away Voice")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                Text("Edit the accountability lines spoken when you leave frame.")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Away Voice Lines")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                Text("Add voice lines below. These are the messages spoken when camera accountability sees you away.")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)

                VStack(spacing: 8) {
                    ForEach(0..<supportiveUtterances.count, id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("Voice line \(index + 1)", text: $supportiveUtterances[index])
                                .focused($focusedField, equals: .awayVoiceLines)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(subtleFillColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(primaryTextColor)

                            Button(action: {
                                if supportiveUtterances.count > 1 {
                                    supportiveUtterances.remove(at: index)
                                    persistSupportiveUtterancesDraft()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(secondaryTextColor)
                                    .font(.title3)
                            }
                        }
                    }

                    Button(action: {
                        supportiveUtterances.append("")
                        focusedField = .awayVoiceLines
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add voice line")
                        }
                        .font(.subheadline)
                        .foregroundStyle(primaryTextColor)
                        .padding(12)
                        .background(subtleFillColor.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            Button {
                isResetConfirmationPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset All Data")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.red)

                        Text("Delete all tasks, stats, and settings. This cannot be undone.")
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.red)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(subtleFillColor)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSettingsKeyboardAndSave()
        }
        .alert("Reset All Data", isPresented: $isResetConfirmationPresented) {
            TextField("Type 'delete' to confirm", text: $resetConfirmationText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Cancel", role: .cancel) {
                resetConfirmationText = ""
            }

            Button("Reset", role: .destructive) {
                if resetConfirmationText.lowercased() == "delete" {
                    store.resetAllData()
                    resetConfirmationText = ""
                }
            }
            .disabled(resetConfirmationText.lowercased() != "delete")
        } message: {
            Text("This will permanently delete all your tasks, statistics, and settings. Type 'delete' to confirm.")
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

    private var ledgerEntries: [LedgerEntry] {
        // Build ledger entries from completed tasks and stats
        var entries: [LedgerEntry] = []
        
        // Add entries from task stats
        for (taskID, taskStat) in store.stats.taskStats {
            // Find task name
            let taskName = store.taskState.tasks.first(where: { $0.id == taskID })?.name ?? "Unknown Task"
            
            // Add completed entries
            for _ in 0..<taskStat.completed {
                entries.append(LedgerEntry(
                    taskName: taskName,
                    date: Date().addingTimeInterval(-Double.random(in: 0...86400 * 30)), // Spread over last 30 days for demo
                    isKept: true
                ))
            }
            
            // Add failed entries
            for _ in 0..<taskStat.failed {
                entries.append(LedgerEntry(
                    taskName: taskName,
                    date: Date().addingTimeInterval(-Double.random(in: 0...86400 * 30)),
                    isKept: false
                ))
            }
        }
        
        return entries.sorted { $0.date > $1.date }
    }

    private enum StartAction {
        case taskName(String)
        case taskID(UUID)
    }

    private func runStartAction(_ action: StartAction) async {
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

    private func saveTaskToLibrary(named name: String) async {
        do {
            quickStartValidationMessage = nil
            try store.addTask(named: name)
            quickStartText = ""
            isLibraryPresented = true
        } catch {
            print("Failed to save task: \(error)")
        }
    }

    private var activeTimerSection: some View {
        VStack(spacing: 26) {
            Text(store.activeTaskName)
                .font(.title2.weight(.bold))
                .foregroundStyle(primaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !store.timerState.isCompleted {
                cameraAccountabilityIndicator
            }

            timerDial

            if store.timerState.isCompleted {
                VStack(spacing: 8) {
                    Text("Block Completed")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.green)

                    Text("Sealed and recorded in your Ledger.")
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                }

                HStack(spacing: 16) {
                    Button("View Ledger") {
                        store.returnToTasks()
                        isLedgerPresented = true
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Start Another Block") {
                        store.returnToTasks()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                VStack(spacing: 8) {
                    Text("If you leave the app, the timer keeps running.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryTextColor)

                    Text("Camera enforcement stops in background. If time runs out before you return, the block fails.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(secondaryTextColor)
                }
                .padding(.top, 2)

                HStack(spacing: 16) {
                    Button("Fail Block") {
                        isQuitConfirmationPresented = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(20)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .alert("Fail this block?", isPresented: $isQuitConfirmationPresented) {
            Button("Keep Going", role: .cancel) {}
            Button("Yes, Break It", role: .destructive) {
                store.stopTimer(asFailure: true)
                cameraManager.stopSession()
            }
        } message: {
            Text("Failing the block counts as a failure and will be recorded.")
        }
    }

    private var timerDial: some View {
        ZStack {
            Circle()
                .stroke((isLightTheme ? Color.black : Color.white).opacity(0.12), lineWidth: 16)
                .frame(width: 250, height: 250)

            Circle()
                .trim(from: 0, to: store.timerState.isCompleted ? 1 : store.progress)
                .stroke(
                    AngularGradient(colors: [Color.cyan, Color.orange], center: .center),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .frame(width: 250, height: 250)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Text(store.formattedRemaining)
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(primaryTextColor)

                Text("remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
        }
    }

    private var cameraAccountabilityIndicator: some View {
        HStack(spacing: 10) {
            accountabilityStatusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(cameraStatusText)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(cameraStatusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let detailText = cameraIndicatorDetailText {
                    Text(detailText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
            }

            Spacer(minLength: 0)

            Text("\(store.awayFailureSeconds)s away")
                .font(.caption.weight(.black))
                .foregroundStyle(cameraStatusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(cameraStatusColor.opacity(0.14))
                .clipShape(Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cameraStatusColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var accountabilityStatusIcon: some View {
        ZStack {
            Circle()
                .fill(cameraStatusColor)
                .frame(width: 44, height: 44)

            Text(cameraIndicatorIconText)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var cameraIndicatorIconText: String {
        if cameraManager.presenceState == .away {
            return "\(awayCountdownRemaining)"
        }

        return cameraStatusSymbol
    }

    private var cameraStatusSymbol: String {
        switch cameraManager.presenceState {
        case .present:
            return "✓"
        case .away:
            return "!"
        case .noPermission, .error:
            return "!"
        case .idle:
            return "●"
        }
    }

    private var cameraIndicatorDetailText: String? {
        if cameraManager.presenceState == .away {
            return "\(awayCountdownRemaining)s until block fails"
        }

        if cameraManager.presenceState == .idle {
            return "Camera accountability required"
        }

        return nil
    }

    private var awayCountdownRemaining: Int {
        let remaining = store.awayFailureSeconds - cameraManager.secondsAway
        if remaining < 0 {
            return 0
        }
        return remaining
    }

    private var cameraStatusText: String {
        switch cameraManager.presenceState {
        case .idle:
            return "Block ready"
        case .present:
            return "Present — block live"
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .light
                    ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.99)]
                    : [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
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
    @Environment(\.colorScheme) private var colorScheme

    let onStart: (UUID) -> Void
    let onEdit: (FocusTask) -> Void
    let onDelete: (UUID) -> Void
    let onTogglePin: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: colorScheme == .light
                        ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.99)]
                        : [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack {
                        Text("Task Library")
                            .font(.headline)
                            .foregroundStyle(colorScheme == .light ? Color.black : Color.white)

                        Spacer()

                        Text("\(filteredTasks.count) tasks")
                            .font(.caption)
                            .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
                    }

                    TextField("Find a task…", text: $searchText)
                        .textInputAutocapitalization(.sentences)
                        .padding(12)
                        .background(colorScheme == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(colorScheme == .light ? Color.black : Color.white)

                    HStack(spacing: 10) {
                        ForEach(TaskLibraryFilter.allCases) { option in
                            Button(option.title) {
                                filter = option
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(filter == option ? Color.black : (colorScheme == .light ? Color.black : Color.white))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(filter == option ? Color.cyan : (colorScheme == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.08)))
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
