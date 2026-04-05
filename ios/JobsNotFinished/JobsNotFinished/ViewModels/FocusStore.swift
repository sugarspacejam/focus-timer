import Foundation
import UserNotifications

@MainActor
class FocusStore: ObservableObject {
    // Grouped state properties
    @Published var timerState: TimerState
    @Published var taskState: TaskState
    @Published var userState: UserState
    @Published var stats: FocusStats
    
    // Services
    private let persistenceService: Persisting
    private let notificationService: NotificationService
    
    // Timer management
    private var timer: Timer?
    
    init(persistenceService: Persisting = UserDefaultsPersistence(), notificationService: NotificationService = NotificationService()) {
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
    
    var progress: Double {
        Double(timerState.remainingSeconds) / Double(Constants.Timer.durationSeconds)
    }
    
    var formattedRemaining: String {
        let minutes = timerState.remainingSeconds / 60
        let seconds = timerState.remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var canStartContract: Bool {
        userState.isProUnlocked || stats.todayBlocks < Constants.Limits.freeContractsPerDay
    }
    
    var awayUtterances: [String] {
        if userState.selectedVoiceMode == .supportive {
            return userState.supportiveUtterances
        }
        return AwayVoiceMode.strict.utterances
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
        
        // Schedule notification
        if let task = activeTask {
            let completionDate = Date().addingTimeInterval(Constants.Timer.durationSeconds)
            try await notificationService.scheduleTimerCompletion(for: task.name, at: completionDate)
        }
        
        startHeartbeat()
    }
    
    func stopTimer(asFailure: Bool) {
        stopHeartbeat()
        
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
        
        timerState.isCompleted = true
        
        do {
            try persist()
        } catch {
            print("Failed to persist timer completion: \(error)")
        }
    }
    
    func restartCompletedTimer() {
        guard let activeTaskID = timerState.activeTaskID else {
            return
        }
        do {
            try startTimer(for: activeTaskID)
        } catch {
            print("Failed to restart timer: \(error)")
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
        if isTimerActive && !timerState.isCompleted {
            if let task = activeTask {
                let completionDate = Date().addingTimeInterval(TimeInterval(timerState.remainingSeconds))
                try await notificationService.scheduleTimerCompletion(for: task.name, at: completionDate)
            }
        }
    }
    
    func prepareForBackground() {
        guard isTimerActive, !timerState.isCompleted else {
            return
        }
        
        syncRemainingSeconds()
        
        Task {
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
    
    func setProUnlocked(_ unlocked: Bool) {
        userState.isProUnlocked = unlocked
        do {
            try persist()
        } catch {
            print("Failed to persist pro status: \(error)")
        }
    }
    
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
        taskState.tasks.removeAll()
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
        let today = Calendar.current.startOfDay(for: Date())
        let lastOpen = Calendar.current.startOfDay(for: UserDefaults.standard.object(forKey: "lastOpen") as? Date ?? today)
        
        if today > lastOpen {
            stats.todayBlocks = 0
            UserDefaults.standard.set(today, forKey: "lastOpen")
        }
    }
    
    private func persist() throws {
        let persistedState = PersistedState(
            tasks: taskState.tasks,
            stats: stats,
            activeTaskID: timerState.activeTaskID,
            timerStartDate: timerState.startDate,
            timerCompleted: timerState.isCompleted,
            isCameraEnabled: taskState.isCameraEnabled,
            selectedVoiceMode: userState.selectedVoiceMode,
            supportiveUtterances: userState.supportiveUtterances,
            isProUnlocked: userState.isProUnlocked
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
            timerState.isCompleted = state.timerCompleted
            taskState.isCameraEnabled = state.isCameraEnabled
            userState.selectedVoiceMode = state.selectedVoiceMode
            userState.supportiveUtterances = state.supportiveUtterances
            userState.isProUnlocked = state.isProUnlocked
            
            if timerState.startDate != nil && timerState.activeTaskID != nil && !timerState.isCompleted {
                timerState.motivationalMessageIndex = Int.random(in: 0..<6)
            }
        } catch {
            print("Failed to load persisted state: \(error)")
            // Start with default state
        }
    }
}
