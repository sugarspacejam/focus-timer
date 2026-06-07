import Foundation
import UserNotifications
import UIKit
import SwiftUI

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
    
    var awayUtterances: [String] {
        userState.supportiveUtterances
    }
    
    var ledgerEntries: [LedgerEntry] {
        var entries: [LedgerEntry] = []
        
        for (taskID, taskStat) in stats.taskStats {
            let taskName = taskState.tasks.first(where: { $0.id == taskID })?.name ?? "Unknown Task"
            
            for _ in 0..<taskStat.completed {
                entries.append(LedgerEntry(
                    taskName: taskName,
                    date: Date(),
                    isKept: true
                ))
            }
            
            for _ in 0..<taskStat.failed {
                entries.append(LedgerEntry(
                    taskName: taskName,
                    date: Date(),
                    isKept: false
                ))
            }
        }
        
        return entries.sorted { $0.date > $1.date }
    }

    var awayFailureSeconds: Int {
        userState.awayFailureSeconds
    }

    var themeMode: AppThemeMode {
        userState.themeMode
    }

    var preferredColorScheme: ColorScheme? {
        switch userState.themeMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
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
        timerState.blockStartedAt = Date()
        timerState.remainingSeconds = Int(Constants.Timer.durationSeconds)
        timerState.isCompleted = false
        timerState.motivationalMessageIndex += 1
        userState.dailyContractsStarted += 1
        userState.lastContractDate = Date()
        
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
            stats.totalFailedBlocks += 1
            
            // Flame system: failed block ends momentum streak, no Fire Power
            stats.currentMomentumStreak = 0
            stats.lastBlockEndTime = nil
            stats.gracePeriodEndTime = nil
            
            var taskStat = stats.taskStats[activeTaskID] ?? TaskStat(completed: 0, failed: 0)
            taskStat.failed += 1
            stats.taskStats[activeTaskID] = taskStat
        }
        
        timerState.activeTaskID = nil
        timerState.startDate = nil
        timerState.blockStartedAt = nil
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
        stats.totalKeptBlocks += 1
        
        // Flame system: calculate Fire Power based on momentum streak
        let now = Date()
        let blockStartedAt = timerState.blockStartedAt ?? now
        
        // Check if momentum is still active (started within grace period and same day)
        let isMomentumActive: Bool
        if let graceEnd = stats.gracePeriodEndTime,
           let lastCompleted = stats.lastKeptBlockCompletedAt {
            let sameDay = Calendar.current.isDate(lastCompleted, inSameDayAs: now)
            let startedInWindow = blockStartedAt <= graceEnd
            isMomentumActive = sameDay && startedInWindow
        } else {
            isMomentumActive = false
        }
        
        if isMomentumActive {
            stats.currentMomentumStreak += 1
        } else {
            stats.currentMomentumStreak = 1
        }
        
        let firePowerGained = stats.currentMomentumStreak
        stats.totalFirePower += firePowerGained
        stats.todayFirePowerEarned += firePowerGained
        stats.bestMomentum = max(stats.bestMomentum, stats.currentMomentumStreak)
        
        stats.lastBlockEndTime = now
        stats.lastKeptBlockCompletedAt = now
        stats.gracePeriodEndTime = now.addingTimeInterval(FocusStats.gracePeriodSeconds)
        
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
        timerState.blockStartedAt = nil
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
    
    func resetAllData() {
        timerState = TimerState()
        taskState = TaskState()
        userState = UserState()
        stats = FocusStats()
        try? persist()
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

    func updateCountdownSpeakingEnabled(_ enabled: Bool) {
        userState.countdownSpeakingEnabled = enabled
        do {
            try persist()
        } catch {
            print("Failed to persist countdown speaking enabled: \(error)")
        }
    }

    func setThemeMode(_ mode: AppThemeMode) {
        userState.themeMode = mode
        do {
            try persist()
        } catch {
            print("Failed to persist theme mode: \(error)")
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
        stopHeartbeat()
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
            userState.dailyContractsStarted = 0
            
            // Flame system: reset momentum streak daily, keep total Fire Power
            stats.currentMomentumStreak = 0
            stats.lastBlockEndTime = nil
            stats.gracePeriodEndTime = nil
            stats.todayFirePowerEarned = 0
            
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
            selectedVoiceMode: userState.selectedVoiceMode,
            supportiveUtterances: userState.supportiveUtterances,
            awayFailureSeconds: userState.awayFailureSeconds,
            themeMode: userState.themeMode,
            dailyContractsStarted: userState.dailyContractsStarted,
            lastContractDate: userState.lastContractDate
        )
        
        try persistenceService.save(persistedState, forKey: Constants.Persistence.storeKey)
    }
    
    // MARK: - Flame System
    
    var isGracePeriodActive: Bool {
        guard let graceEnd = stats.gracePeriodEndTime else {
            return false
        }
        return Date() <= graceEnd
    }
    
    var gracePeriodRemainingSeconds: TimeInterval {
        guard let graceEnd = stats.gracePeriodEndTime else {
            return 0
        }
        return max(graceEnd.timeIntervalSinceNow, 0)
    }
    
    var nextFirePower: Int {
        stats.currentMomentumStreak + 1
    }
    
    var flameColor: Color {
        let power = stats.totalFirePower
        if power >= 25000 {
            return Color(red: 0.97, green: 0.96, blue: 0.91) // Eternal Flame core
        } else if power >= 10000 {
            return Color(red: 1.0, green: 0.84, blue: 0.42) // Supernova outer
        } else if power >= 5000 {
            return Color(red: 0.35, green: 0.42, blue: 1.0) // Cosmic outer
        } else if power >= 2000 {
            return Color(red: 0.3, green: 1.0, blue: 0.72) // Aurora outer
        } else if power >= 1000 {
            return Color(red: 0.0, green: 0.85, blue: 1.0) // Plasma outer
        } else if power >= 500 {
            return Color(red: 1.0, green: 0.7, blue: 0.0) // Solar outer
        } else if power >= 250 {
            return Color(red: 0.97, green: 0.96, blue: 0.91) // White Flame
        } else if power >= 100 {
            return Color(red: 0.61, green: 0.36, blue: 1.0) // Violet Flame
        } else if power >= 50 {
            return Color(red: 0.24, green: 0.65, blue: 1.0) // Blue Flame
        } else if power >= 25 {
            return Color(red: 1.0, green: 0.76, blue: 0.2) // Gold Flame
        } else if power >= 10 {
            return Color(red: 1.0, green: 0.48, blue: 0.1) // Orange Flame
        } else if power >= 1 {
            return Color(red: 0.9, green: 0.22, blue: 0.21) // Red Flame
        } else {
            return Color(red: 0.6, green: 0.29, blue: 0.1) // Ember
        }
    }
    
    var flameSecondaryColor: Color {
        let power = stats.totalFirePower
        if power >= 25000 {
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Eternal secondary
        } else if power >= 10000 {
            return Color(red: 1.0, green: 0.3, blue: 0.43) // Supernova secondary
        } else if power >= 5000 {
            return Color(red: 0.76, green: 0.24, blue: 1.0) // Cosmic secondary
        } else if power >= 2000 {
            return Color(red: 0.54, green: 0.36, blue: 1.0) // Aurora secondary
        } else if power >= 1000 {
            return Color(red: 0.42, green: 0.36, blue: 1.0) // Plasma glow
        } else if power >= 500 {
            return Color(red: 1.0, green: 0.42, blue: 0.0) // Solar glow
        } else {
            return .clear
        }
    }
    
    var flameGlowColor: Color {
        let power = stats.totalFirePower
        if power >= 25000 {
            return Color(red: 1.0, green: 1.0, blue: 1.0) // Eternal glow
        } else if power >= 10000 {
            return Color(red: 1.0, green: 0.54, blue: 0.0) // Supernova glow
        } else if power >= 5000 {
            return Color(red: 0.11, green: 0.11, blue: 0.35) // Cosmic glow
        } else if power >= 2000 {
            return Color(red: 0.0, green: 0.76, blue: 1.0) // Aurora glow
        } else if power >= 1000 {
            return Color(red: 0.42, green: 0.36, blue: 1.0) // Plasma glow
        } else if power >= 500 {
            return Color(red: 1.0, green: 0.42, blue: 0.0) // Solar glow
        } else {
            return flameColor.opacity(0.4)
        }
    }
    
    var flameTier: String {
        let power = stats.totalFirePower
        if power >= 25000 {
            return "Eternal Flame"
        } else if power >= 10000 {
            return "Supernova Flame"
        } else if power >= 5000 {
            return "Cosmic Flame"
        } else if power >= 2000 {
            return "Aurora Flame"
        } else if power >= 1000 {
            return "Plasma Flame"
        } else if power >= 500 {
            return "Solar Flame"
        } else if power >= 250 {
            return "White Flame"
        } else if power >= 100 {
            return "Violet Flame"
        } else if power >= 50 {
            return "Blue Flame"
        } else if power >= 25 {
            return "Gold Flame"
        } else if power >= 10 {
            return "Orange Flame"
        } else if power >= 1 {
            return "Red Flame"
        } else {
            return "Ember"
        }
    }
    
    var prestigeRingCount: Int {
        min(stats.totalFirePower / 1000, 5)
    }
    
    var flameSizeMultiplier: CGFloat {
        let power = stats.totalFirePower
        if power >= 10000 {
            return 1.3
        } else if power >= 5000 {
            return 1.2
        } else if power >= 2000 {
            return 1.15
        } else if power >= 1000 {
            return 1.1
        } else if power >= 500 {
            return 1.05
        } else {
            return 1.0
        }
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
            userState.selectedVoiceMode = state.selectedVoiceMode
            userState.supportiveUtterances = state.supportiveUtterances
            userState.awayFailureSeconds = state.awayFailureSeconds
            userState.themeMode = state.themeMode
            userState.dailyContractsStarted = state.dailyContractsStarted
            userState.lastContractDate = state.lastContractDate

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
