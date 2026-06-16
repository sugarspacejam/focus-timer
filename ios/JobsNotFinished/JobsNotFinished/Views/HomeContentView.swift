import SwiftUI
import UIKit

struct HomeContentView: View {
    private let taskNameMinimumScaleFactor: CGFloat = 0.82

    private enum FocusedField: Hashable {
        case quickStart
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @EnvironmentObject var store: FocusStore
    @EnvironmentObject var cameraManager: CameraManager

    @FocusState private var focusedField: FocusedField?

    @State private var quickStartText = ""
    @State private var quickStartValidationMessage: String?
    @State private var isLibraryPresented = false
    @State private var isFlameExplanationPresented = false

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
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(store.preferredColorScheme)
        .sheet(isPresented: $isLibraryPresented) {
            NavigationStack {
                LibraryView()
            }
        }
        .sheet(isPresented: $isFlameExplanationPresented) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What is Fire Power?")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(primaryTextColor)
                            
                            Text("Fire Power is your permanent progress score. Every completed block earns you +1 Fire Power.")
                                .font(.body)
                                .foregroundStyle(secondaryTextColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What is Momentum?")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(primaryTextColor)
                            
                            Text("Momentum is your streak multiplier. Complete consecutive blocks to build momentum (1x, 2x, 3x...). Higher momentum earns you more Fire Power per block.")
                                .font(.body)
                                .foregroundStyle(secondaryTextColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What are Flame Tiers?")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(primaryTextColor)
                            
                            Text("As your Fire Power grows, your flame evolves through 13 tiers—from Ember to Eternal Flame. Each tier has unique colors and visual effects.")
                                .font(.body)
                                .foregroundStyle(secondaryTextColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How it works")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(primaryTextColor)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(secondaryTextColor)
                                    Text("Complete a block → earn +1 Fire Power")
                                        .font(.body)
                                        .foregroundStyle(secondaryTextColor)
                                }
                                HStack(spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(secondaryTextColor)
                                    Text("Complete consecutive blocks → build momentum")
                                        .font(.body)
                                        .foregroundStyle(secondaryTextColor)
                                }
                                HStack(spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(secondaryTextColor)
                                    Text("Higher momentum → more Fire Power per block")
                                        .font(.body)
                                        .foregroundStyle(secondaryTextColor)
                                }
                                HStack(spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(secondaryTextColor)
                                    Text("More Fire Power → higher flame tier")
                                        .font(.body)
                                        .foregroundStyle(secondaryTextColor)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .navigationTitle("Flame System")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Got it") {
                            isFlameExplanationPresented = false
                        }
                    }
                }
            }
        }
        .onAppear {
            loadPinnedTaskIDs()
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.isTimerPresentationActive },
            set: { _ in }
        )) {
            TimerModalView(
                activeTimerSection: TimerView()
            )
            .interactiveDismissDisabled(true)
        }
        .task {
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
            cameraManager.updateCountdownSpeakingEnabled(store.userState.countdownSpeakingEnabled)

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
            cameraManager.updateAwayFailureSeconds(seconds)
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

                Text("5-minute blocks to fuel your flame.")
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            Button {
                isLibraryPresented = true
            } label: {
                Image(systemName: "square.fill.on.square.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatCard(title: "Today", value: "\(store.stats.todayBlocks)", explanation: "Blocks completed today")
            StatCard(title: "Streak", value: "\(store.stats.currentMomentumStreak)", explanation: "Current momentum streak")
            HStack(spacing: 4) {
                StatCard(title: "Fire Power", value: "\(store.stats.totalFirePower)", explanation: "Total accumulated power")
                Button {
                    isFlameExplanationPresented = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
            }
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you avoiding?")
                .font(.title3.weight(.bold))
                .foregroundStyle(primaryTextColor)

            Text("5-minute block. Stay focused to earn Fire Power.")
                .font(.caption)
                .foregroundStyle(secondaryTextColor)

            TextField("Send email to boss / Open job form / Reply to Dana", text: $quickStartText)
                .focused($focusedField, equals: .quickStart)
                .textInputAutocapitalization(.sentences)
                .padding()
                .background(subtleFillColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(primaryTextColor)

            Button("Start 5-Minute Block") {
                focusedField = nil
                let trimmed = quickStartText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= Constants.UI.minimumTaskNameLength {
                    quickStartValidationMessage = nil
                    Task {
                        await runStartAction(.taskName(trimmed))
                    }
                } else {
                    quickStartValidationMessage = "Enter a block name (\(Constants.UI.minimumTaskNameLength)+ characters)."
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            if store.isGracePeriodActive {
                let remaining = Int(store.gracePeriodRemainingSeconds)
                let minutes = remaining / 60
                let seconds = remaining % 60
                VStack(spacing: 4) {
                    Text("Momentum x\(store.stats.currentMomentumStreak) alive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.flameColor)
                    Text("\(minutes):\(String(format: "%02d", seconds)) to keep momentum")
                        .font(.caption)
                        .foregroundStyle(store.flameColor)
                    Text("Next block earns +\(store.nextFirePower) Fire Power")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
            } else {
                Text("Earn +1 Fire Power")
                    .font(.caption)
                    .foregroundStyle(store.flameColor)
            }

            Button("Save to Library") {
                focusedField = nil
                let trimmed = quickStartText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= Constants.UI.minimumTaskNameLength {
                    Task {
                        await saveTaskToLibrary(named: trimmed)
                    }
                } else {
                    quickStartValidationMessage = "Enter a block name (\(Constants.UI.minimumTaskNameLength)+ characters)."
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
            Text("Recent")
                .font(.headline)
                .foregroundStyle(primaryTextColor)

            Text("Your recent blocks for quick restart.")
                .font(.caption)
                .foregroundStyle(secondaryTextColor)

            let tasks = recentTasksList
            if tasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundStyle(secondaryTextColor)
                    
                    Text("No recent blocks")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(primaryTextColor)
                    
                    Text("Start a block above to see it here.")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
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

                                if pinnedTaskIDs.contains(task.id) {
                                    Text("Pinned")
                                        .font(.caption)
                                        .foregroundStyle(tertiaryTextColor)
                                }
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
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
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
    }

    private func saveTaskToLibrary(named name: String) async {
        do {
            quickStartValidationMessage = nil
            try store.addTask(named: name)
            quickStartText = ""
        } catch {
            print("Failed to save task: \(error)")
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
