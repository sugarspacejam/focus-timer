import Foundation
import UserNotifications
import UIKit

@MainActor
class FocusStore: ObservableObject {
    // Grouped state properties
    @Published var timerState: TimerState
    @Published var taskState: TaskState
    @Published var userState: UserState
    @Published var stats: FocusStats
    
    // Services
    private let persistenceService: Persisting
    private let notificationService: NotificationServicing
    
    // Timer management
    private var timer: Timer?
    private var notificationSchedulingTask: Task<Void, Never>?
    
    init(persistenceService: Persisting = UserDefaultsPersistence(), notificationService: NotificationServicing = NotificationService()) {
        self.persistenceService = persistenceService
        self.notificationService = notificationService
        
        // Initialize state
        self.timerState = TimerState()
        self.taskState = TaskState()
        self.userState = UserState()
        self.stats = FocusStats()
        
        loadPersistedState()
        migrateDayIfNeeded()
        syncRemainingSeconds()
    }
    
    // MARK: - Computed Properties
    
    var isTimerActive: Bool {
        timerState.activeTaskID != nil
    }
    
    var isTimerPresentationActive: Bool {
        timerState.activeTaskID != nil || timerState.isCompleted
    }
    
    var activeTaskName: String {
        guard let activeTask = activeTask else {
            return ""
        }
        return activeTask.name
    }
    
    var activeTask: FocusTask? {
        guard let activeTaskID = timerState.activeTaskID else {
            return nil
        }
        return taskState.tasks.first(where: { $0.id == activeTaskID })
    }
    
    var completionRate: Int {
        if stats.totalBlocks == 0 {
            return 0
        }
        return Int((Double(stats.completedBlocks) / Double(stats.totalBlocks) * 100).rounded())
    }

    var totalCompletions: Int {
        stats.completedBlocks
    }

    var totalFailures: Int {
        stats.failedBlocks
    }

    var visibleRemainingSeconds: Int {
        guard let startDate = timerState.startDate,
              timerState.activeTaskID != nil,
              !timerState.isCompleted else {
            return timerState.remainingSeconds
        }

        let elapsed = Date().timeIntervalSince(startDate)
        return max(Int(Constants.Timer.durationSeconds) - Int(elapsed), 0)
    }
    
    var progress: Double {
        Double(visibleRemainingSeconds) / Double(Constants.Timer.durationSeconds)
    }
    
    var formattedRemaining: String {
        let minutes = visibleRemainingSeconds / 60
        let seconds = visibleRemainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var canStartContract: Bool {
        true
    }

    var canUseEnforcement: Bool {
        true
    }
    
    var awayUtterances: [String] {
        userState.supportiveUtterances
    }

    var awayFailureSeconds: Int {
        userState.awayFailureSeconds
    }
    
    // MARK: - Timer Management
    
    func startTimerForTaskNamed(_ name: String) throws -> Bool {
        guard name.count >= Constants.UI.minimumTaskNameLength else {
            throw AppError.taskNameTooShort
        }
        
        if let existingTask = taskState.tasks.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame && $0.isFinished == false }) {
            try startTimer(for: existingTask.id)
            return true
        }
        
        let newTask = FocusTask(id: UUID(), name: name, createdAt: Date(), isFinished: false)
        taskState.tasks.append(newTask)
        try startTimer(for: newTask.id)
        return true
    }
    
    func startTimer(for taskID: UUID) throws {
        guard taskState.tasks.contains(where: { $0.id == taskID }) else {
            throw AppError.taskNameTooShort
        }
        
        timerState.activeTaskID = taskID
        timerState.startDate = Date()
        timerState.remainingSeconds = Int(Constants.Timer.durationSeconds)
        timerState.isCompleted = false
        timerState.motivationalMessageIndex += 1
        
        try persist()

        scheduleNotificationIfNeeded()
        
        startHeartbeat()
    }
    
    func stopTimer(asFailure: Bool) {
        stopHeartbeat()
        notificationSchedulingTask?.cancel()
        notificationSchedulingTask = nil
        
        Task {
            await notificationService.cancelTimerCompletion()
        }
        
        guard let activeTaskID = timerState.activeTaskID else {
            return
        }
        
        if asFailure {
            stats.todayBlocks += 1
            stats.totalBlocks += 1
            stats.failedBlocks += 1
            stats.streak = 0
            
            var taskStat = stats.taskStats[activeTaskID] ?? TaskStat(completed: 0, failed: 0)
            taskStat.failed += 1
            stats.taskStats[activeTaskID] = taskStat
        }
        
        timerState.activeTaskID = nil
        timerState.startDate = nil
        timerState.isCompleted = false
        
        do {
            try persist()
        } catch {
            print("Failed to persist timer stop: \(error)")
        }
    }
    
    func completeTimer() {
        guard let activeTaskID = timerState.activeTaskID else {
            return
        }
        
        stopHeartbeat()
        notificationSchedulingTask?.cancel()
        notificationSchedulingTask = nil
        
        Task {
            await notificationService.cancelTimerCompletion()
        }
        
        stats.todayBlocks += 1
        stats.totalBlocks += 1
        stats.completedBlocks += 1
        stats.streak += 1
        
        var taskStat = stats.taskStats[activeTaskID] ?? TaskStat(completed: 0, failed: 0)
        taskStat.completed += 1
        stats.taskStats[activeTaskID] = taskStat
        
        if let task = activeTask {
            stats.taskTimeSpent[task.id, default: 0] += Int(Constants.Timer.durationSeconds)
        }
        
        timerState.remainingSeconds = 0
        timerState.isCompleted = true
        
        do {
            try persist()
        } catch {
            print("Failed to persist timer completion: \(error)")
        }
    }
    
    func restartCompletedTimer() {
        guard timerState.isCompleted, let activeTaskID = timerState.activeTaskID else {
            return
        }
        do {
            try startTimer(for: activeTaskID)
        } catch {
            print("Failed to restart timer: \(error)")
        }
    }

    func returnToTasks() {
        stopHeartbeat()
        notificationSchedulingTask?.cancel()
        notificationSchedulingTask = nil

        Task {
            await notificationService.cancelTimerCompletion()
        }

        timerState.activeTaskID = nil
        timerState.startDate = nil
        timerState.isCompleted = false
        timerState.remainingSeconds = Int(Constants.Timer.durationSeconds)

        do {
            try persist()
        } catch {
            print("Failed to persist return to tasks: \(error)")
        }
    }
    
    // MARK: - Task Management
    
    func addTask(named name: String) throws {
        guard name.count >= Constants.UI.minimumTaskNameLength else {
            throw AppError.taskNameTooShort
        }
        
        if taskState.tasks.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame && $0.isFinished == false }) {
            throw AppError.taskAlreadyExists
        }
        
        taskState.tasks.append(FocusTask(id: UUID(), name: name, createdAt: Date(), isFinished: false))
        try persist()
    }
    
    func renameTask(taskID: UUID, to name: String) throws {
        guard name.count >= Constants.UI.minimumTaskNameLength else {
            throw AppError.taskNameTooShort
        }
        
        guard let index = taskState.tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        
        if taskState.tasks.contains(where: { $0.id != taskID && $0.name.compare(name, options: .caseInsensitive) == .orderedSame && $0.isFinished == false }) {
            throw AppError.taskAlreadyExists
        }
        
        taskState.tasks[index].name = name
        try persist()
    }
    
    func deleteTask(taskID: UUID) throws {
        if isTimerActive {
            return
        }
        
        taskState.tasks.removeAll { $0.id == taskID }
        stats.taskStats[taskID] = nil
        stats.taskTimeSpent[taskID] = nil
        try persist()
    }
    
    // MARK: - Background Support
    
    func prepareNotifications() async throws {
        try await notificationService.requestPermissions()
        guard isTimerActive, !timerState.isCompleted, let task = activeTask else {
            return
        }

        let completionDate = Date().addingTimeInterval(TimeInterval(timerState.remainingSeconds))
        try await notificationService.scheduleTimerCompletion(for: task.name, at: completionDate)
    }
    
    func prepareForBackground() {
        guard isTimerActive, !timerState.isCompleted else {
            return
        }
        
        syncRemainingSeconds()

        let application = UIApplication.shared
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = application.beginBackgroundTask(withName: "ScheduleTimerCompletion") {
            if backgroundTaskID != .invalid {
                application.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        
        notificationSchedulingTask?.cancel()
        notificationSchedulingTask = Task {
            defer {
                if backgroundTaskID != .invalid {
                    application.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }

            guard !Task.isCancelled else {
                return
            }

            if let task = activeTask {
                let completionDate = Date().addingTimeInterval(TimeInterval(timerState.remainingSeconds))
                do {
                    try await notificationService.scheduleTimerCompletion(for: task.name, at: completionDate)
                } catch {
                    print("Failed to schedule background notification: \(error)")
                }
            }
        }
        
        stopHeartbeat()
        
        do {
            try persist()
        } catch {
            print("Failed to persist background state: \(error)")
        }
    }
    
    func resumeTimerIfNeeded() {
        guard let startDate = timerState.startDate,
              timerState.activeTaskID != nil,
              !timerState.isCompleted else {
            return
        }
        
        let elapsed = Date().timeIntervalSince(startDate)
        let remaining = max(Int(Constants.Timer.durationSeconds) - Int(elapsed), 0)
        
        if remaining <= 0 {
            completeTimer()
        } else {
            timerState.remainingSeconds = remaining
            startHeartbeat()
        }
    }
    
    // MARK: - Settings

    func toggleCamera() {
        taskState.isCameraEnabled.toggle()
        do {
            try persist()
        } catch {
            print("Failed to persist camera setting: \(error)")
        }
    }
    
    func setVoiceMode(_ mode: AwayVoiceMode) {
        userState.selectedVoiceMode = mode
        do {
            try persist()
        } catch {
            print("Failed to persist voice mode: \(error)")
        }
    }
    
    func updateSupportiveUtterances(_ utterances: [String]) {
        userState.supportiveUtterances = utterances
        do {
            try persist()
        } catch {
            print("Failed to persist utterances: \(error)")
        }
    }

    func updateAwayFailureSeconds(_ seconds: Int) {
        userState.awayFailureSeconds = max(seconds, 1)
        do {
            try persist()
        } catch {
            print("Failed to persist away failure seconds: \(error)")
        }
    }
    
    // MARK: - Stats Management
    
    func resetStats() {
        stats = FocusStats()
        do {
            try persist()
        } catch {
            print("Failed to reset stats: \(error)")
        }
    }
    
    func clearAll() throws {
        taskState = TaskState()
        stats = FocusStats()
        timerState = TimerState()
        userState = UserState()
        
        Task {
            await notificationService.cancelTimerCompletion()
        }
        
        try persist()
    }
    
    // MARK: - Private Methods
    
    private func startHeartbeat() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimer()
            }
        }
    }
    
    private func stopHeartbeat() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateTimer() {
        guard timerState.activeTaskID != nil, !timerState.isCompleted else {
            stopHeartbeat()
            return
        }
        
        timerState.remainingSeconds -= 1
        
        if timerState.remainingSeconds <= 0 {
            completeTimer()
        }
    }
    
    private func syncRemainingSeconds() {
        guard let startDate = timerState.startDate else {
            return
        }
        
        let elapsed = Date().timeIntervalSince(startDate)
        timerState.remainingSeconds = max(Int(Constants.Timer.durationSeconds) - Int(elapsed), 0)
    }
    
    private func migrateDayIfNeeded() {
        let today = FocusStats.currentStatsDay

        if stats.statsDay != today {
            stats.statsDay = today
            stats.todayBlocks = 0
            do {
                try persist()
            } catch {
                print("Failed to persist migrated stats day: \(error)")
            }
        }
    }

    private func persist() throws {
        let persistedState = PersistedState(
            tasks: taskState.tasks,
            stats: stats,
            activeTaskID: timerState.activeTaskID,
            timerStartDate: timerState.startDate,
            remainingSeconds: timerState.remainingSeconds,
            timerCompleted: timerState.isCompleted,
            isCameraEnabled: taskState.isCameraEnabled,
            selectedVoiceMode: userState.selectedVoiceMode,
            supportiveUtterances: userState.supportiveUtterances,
            awayFailureSeconds: userState.awayFailureSeconds
        )
        
        try persistenceService.save(persistedState, forKey: Constants.Persistence.storeKey)
    }
    
    private func loadPersistedState() {
        do {
            let state: PersistedState = try persistenceService.load(PersistedState.self, forKey: Constants.Persistence.storeKey)
            
            taskState.tasks = state.tasks
            stats = state.stats
            timerState.activeTaskID = state.activeTaskID
            timerState.startDate = state.timerStartDate
            timerState.remainingSeconds = state.remainingSeconds
            timerState.isCompleted = state.timerCompleted
            taskState.isCameraEnabled = state.isCameraEnabled
            userState.selectedVoiceMode = state.selectedVoiceMode
            userState.supportiveUtterances = state.supportiveUtterances
            userState.awayFailureSeconds = state.awayFailureSeconds

            if timerState.startDate != nil && timerState.activeTaskID != nil && !timerState.isCompleted {
                timerState.motivationalMessageIndex = Int.random(in: 0..<6)
            }
        } catch {
            print("Failed to load persisted state: \(error)")
            // Start with default state
        }
    }

    private func scheduleNotificationIfNeeded() {
        guard !timerState.isCompleted,
              let task = activeTask,
              let activeTaskID = timerState.activeTaskID,
              let startDate = timerState.startDate else {
            return
        }

        notificationSchedulingTask?.cancel()
        let expectedTaskID = activeTaskID
        let expectedStartDate = startDate
        let taskName = task.name
        let completionDate = Date().addingTimeInterval(TimeInterval(timerState.remainingSeconds))
        notificationSchedulingTask = Task {
            do {
                await Task.yield()

                guard Task.isCancelled == false else {
                    return
                }

                let shouldSchedule = await MainActor.run {
                    self.timerState.isCompleted == false &&
                    self.timerState.activeTaskID == expectedTaskID &&
                    self.timerState.startDate == expectedStartDate
                }

                guard shouldSchedule else {
                    return
                }

                try await notificationService.scheduleTimerCompletion(for: taskName, at: completionDate)
            } catch {
                if Task.isCancelled == false {
                    print("Failed to schedule notification: \(error)")
                }
            }
        }
    }
}
