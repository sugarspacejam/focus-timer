import XCTest
@testable import JobsNotFinished

@MainActor
final class FocusStoreTests: XCTestCase {
    private final class InMemoryPersistence: Persisting {
        var storedData: [String: Data] = [:]

        func save<T: Codable>(_ object: T, forKey key: String) throws {
            storedData[key] = try JSONEncoder().encode(object)
        }

        func load<T: Codable>(_ type: T.Type, forKey key: String) throws -> T {
            guard let data = storedData[key] else {
                throw PersistenceError.keyNotFound
            }
            return try JSONDecoder().decode(type, from: data)
        }
    }

    private final class TestNotificationService: NotificationServicing {
        var scheduledTaskNames: [String] = []
        var scheduledDates: [Date] = []
        var cancelledCount = 0
        var requestedPermissionsCount = 0
        var onSchedule: (() -> Void)?

        func requestPermissions() async throws {
            requestedPermissionsCount += 1
        }

        func scheduleTimerCompletion(for taskName: String, at date: Date) async throws {
            scheduledTaskNames.append(taskName)
            scheduledDates.append(date)
            onSchedule?()
        }

        func cancelTimerCompletion() async {
            cancelledCount += 1
        }
    }

    private var persistence: InMemoryPersistence!
    private var notifications: TestNotificationService!
    private var store: FocusStore!

    override func setUp() {
        super.setUp()
        persistence = InMemoryPersistence()
        notifications = TestNotificationService()
        store = FocusStore(persistenceService: persistence, notificationService: notifications)
    }

    override func tearDown() {
        store = nil
        notifications = nil
        persistence = nil
        super.tearDown()
    }

    func testStartTimerForTaskNamedCreatesTaskAndActivatesTimer() throws {
        let started = try store.startTimerForTaskNamed("Write tests")

        XCTAssertTrue(started)
        XCTAssertEqual(store.taskState.tasks.count, 1)
        XCTAssertEqual(store.activeTaskName, "Write tests")
        XCTAssertTrue(store.isTimerActive)
        XCTAssertTrue(store.isTimerPresentationActive)
        XCTAssertFalse(store.timerState.isCompleted)
        XCTAssertEqual(store.timerState.remainingSeconds, Int(Constants.Timer.durationSeconds))
    }

    func testStartTimerForExistingTaskNameDoesNotDuplicateTask() throws {
        try store.addTask(named: "Deep Work")

        let started = try store.startTimerForTaskNamed("deep work")

        XCTAssertTrue(started)
        XCTAssertEqual(store.taskState.tasks.count, 1)
        XCTAssertEqual(store.activeTaskName, "Deep Work")
    }

    func testStartTimerForUnknownTaskIDRejectsStart() {
        XCTAssertThrowsError(try store.startTimer(for: UUID())) { error in
            guard case AppError.taskNameTooShort = error else {
                return XCTFail("Expected taskNameTooShort, got \(error)")
            }
        }
    }

    func testStartTimerForTaskNamedRejectsTooShortName() {
        XCTAssertThrowsError(try store.startTimerForTaskNamed("a")) { error in
            guard case AppError.taskNameTooShort = error else {
                return XCTFail("Expected taskNameTooShort, got \(error)")
            }
        }
    }

    func testCompleteTimerMarksCompletedAndUpdatesStats() throws {
        try store.startTimerForTaskNamed("Ship feature")
        let activeTaskID = try XCTUnwrap(store.timerState.activeTaskID)

        store.completeTimer()

        XCTAssertTrue(store.timerState.isCompleted)
        XCTAssertEqual(store.stats.todayBlocks, 1)
        XCTAssertEqual(store.stats.totalBlocks, 1)
        XCTAssertEqual(store.stats.completedBlocks, 1)
        XCTAssertEqual(store.stats.failedBlocks, 0)
        XCTAssertEqual(store.stats.streak, 1)
        XCTAssertEqual(store.stats.taskStats[activeTaskID]?.completed, 1)
        XCTAssertEqual(store.stats.taskTimeSpent[activeTaskID], Int(Constants.Timer.durationSeconds))
        XCTAssertTrue(store.isTimerPresentationActive)
    }

    func testCompleteTimerWithoutActiveTimerDoesNothing() {
        store.completeTimer()

        XCTAssertFalse(store.timerState.isCompleted)
        XCTAssertFalse(store.isTimerActive)
        XCTAssertEqual(store.stats.totalBlocks, 0)
        XCTAssertEqual(store.stats.completedBlocks, 0)
    }

    func testReturnToTasksClearsCompletedPresentationState() throws {
        try store.startTimerForTaskNamed("Finish flow")
        store.completeTimer()

        store.returnToTasks()

        XCTAssertNil(store.timerState.activeTaskID)
        XCTAssertNil(store.timerState.startDate)
        XCTAssertFalse(store.timerState.isCompleted)
        XCTAssertFalse(store.isTimerActive)
        XCTAssertFalse(store.isTimerPresentationActive)
        XCTAssertEqual(store.timerState.remainingSeconds, Int(Constants.Timer.durationSeconds))
    }

    func testStopTimerAsFailureUpdatesFailureStatsAndClearsActiveTimer() throws {
        try store.startTimerForTaskNamed("Stay focused")
        let activeTaskID = try XCTUnwrap(store.timerState.activeTaskID)

        store.stopTimer(asFailure: true)

        XCTAssertNil(store.timerState.activeTaskID)
        XCTAssertNil(store.timerState.startDate)
        XCTAssertFalse(store.timerState.isCompleted)
        XCTAssertEqual(store.stats.todayBlocks, 1)
        XCTAssertEqual(store.stats.totalBlocks, 1)
        XCTAssertEqual(store.stats.failedBlocks, 1)
        XCTAssertEqual(store.stats.completedBlocks, 0)
        XCTAssertEqual(store.stats.streak, 0)
        XCTAssertEqual(store.stats.taskStats[activeTaskID]?.failed, 1)
    }

    func testRestartCompletedTimerStartsSameTaskAgain() throws {
        try store.startTimerForTaskNamed("Repeatable")
        let originalTaskID = try XCTUnwrap(store.timerState.activeTaskID)
        store.completeTimer()

        store.restartCompletedTimer()

        XCTAssertEqual(store.timerState.activeTaskID, originalTaskID)
        XCTAssertFalse(store.timerState.isCompleted)
        XCTAssertTrue(store.isTimerActive)
        XCTAssertEqual(store.timerState.remainingSeconds, Int(Constants.Timer.durationSeconds))
    }

    func testRestartCompletedTimerWithoutCompletedStateDoesNothing() throws {
        try store.startTimerForTaskNamed("Still running")
        let originalTaskID = try XCTUnwrap(store.timerState.activeTaskID)
        let originalStartDate = try XCTUnwrap(store.timerState.startDate)

        store.restartCompletedTimer()

        XCTAssertEqual(store.timerState.activeTaskID, originalTaskID)
        XCTAssertEqual(store.timerState.startDate, originalStartDate)
        XCTAssertFalse(store.timerState.isCompleted)
    }

    func testContractAndEnforcementAreAlwaysAvailableInPaidUpfrontAppPath() {
        XCTAssertTrue(store.canStartContract)
        XCTAssertTrue(store.canUseEnforcement)
    }

    func testPersistedStateReloadsCompletedTimerState() throws {
        try store.startTimerForTaskNamed("Persist me")
        store.completeTimer()

        let reloadedStore = FocusStore(persistenceService: persistence, notificationService: notifications)

        XCTAssertTrue(reloadedStore.timerState.isCompleted)
        XCTAssertTrue(reloadedStore.isTimerPresentationActive)
        XCTAssertEqual(reloadedStore.activeTaskName, "Persist me")
        XCTAssertEqual(reloadedStore.stats.completedBlocks, 1)
    }

    func testDeleteTaskRemovesTaskAndAssociatedStatsWhenInactive() throws {
        try store.addTask(named: "Delete me")
        let taskID = try XCTUnwrap(store.taskState.tasks.first?.id)
        store.stats.taskStats[taskID] = TaskStat(completed: 2, failed: 1)
        store.stats.taskTimeSpent[taskID] = 300

        try store.deleteTask(taskID: taskID)

        XCTAssertFalse(store.taskState.tasks.contains(where: { $0.id == taskID }))
        XCTAssertNil(store.stats.taskStats[taskID])
        XCTAssertNil(store.stats.taskTimeSpent[taskID])
    }

    func testDeleteTaskDoesNothingWhileTimerIsActive() throws {
        _ = try store.startTimerForTaskNamed("Protected task")
        let taskID = try XCTUnwrap(store.timerState.activeTaskID)

        try store.deleteTask(taskID: taskID)

        XCTAssertTrue(store.taskState.tasks.contains(where: { $0.id == taskID }))
        XCTAssertTrue(store.isTimerActive)
    }

    func testPrepareNotificationsRequestsPermissionAndSchedulesActiveTimer() async throws {
        _ = try store.startTimerForTaskNamed("Notify me")

        try await store.prepareNotifications()

        XCTAssertEqual(notifications.requestedPermissionsCount, 1)
        XCTAssertEqual(notifications.scheduledTaskNames.last, "Notify me")
        XCTAssertFalse(notifications.scheduledDates.isEmpty)
    }

    func testPrepareNotificationsDoesNotScheduleWhenTimerCompleted() async throws {
        _ = try store.startTimerForTaskNamed("Finished notification")
        notifications.scheduledTaskNames.removeAll()
        notifications.scheduledDates.removeAll()
        store.completeTimer()

        try await store.prepareNotifications()

        XCTAssertEqual(notifications.requestedPermissionsCount, 1)
        XCTAssertTrue(notifications.scheduledTaskNames.isEmpty)
    }

    func testPrepareForBackgroundPersistsRemainingTimeAndSchedulesNotification() async throws {
        _ = try store.startTimerForTaskNamed("Background handoff")
        store.timerState.startDate = Date().addingTimeInterval(-42)

        let scheduled = expectation(description: "background notification scheduled")
        notifications.onSchedule = { scheduled.fulfill() }
        notifications.scheduledTaskNames.removeAll()
        notifications.scheduledDates.removeAll()

        store.prepareForBackground()
        await fulfillment(of: [scheduled], timeout: 1.0)

        XCTAssertEqual(store.timerState.remainingSeconds, Int(Constants.Timer.durationSeconds) - 42)
        XCTAssertEqual(notifications.scheduledTaskNames.last, "Background handoff")

        let reloadedStore = FocusStore(persistenceService: persistence, notificationService: notifications)
        XCTAssertEqual(reloadedStore.timerState.remainingSeconds, Int(Constants.Timer.durationSeconds) - 42)
        XCTAssertTrue(reloadedStore.isTimerActive)
    }

    func testPrepareForBackgroundDoesNotScheduleAgainAfterCompletion() async throws {
        _ = try store.startTimerForTaskNamed("Completed background")
        store.completeTimer()
        notifications.scheduledTaskNames.removeAll()
        notifications.scheduledDates.removeAll()

        store.prepareForBackground()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(notifications.scheduledTaskNames.isEmpty)
        XCTAssertEqual(store.timerState.remainingSeconds, 0)
    }

    func testReloadedStoreUsesPersistedStartDateForVisibleRemainingBeforeResume() async throws {
        _ = try store.startTimerForTaskNamed("Reload visible")
        store.timerState.startDate = Date().addingTimeInterval(-42)

        let scheduled = expectation(description: "background notification scheduled for reload")
        notifications.onSchedule = { scheduled.fulfill() }

        store.prepareForBackground()
        await fulfillment(of: [scheduled], timeout: 1.0)

        let reloadedStore = FocusStore(persistenceService: persistence, notificationService: notifications)
        XCTAssertTrue((257...258).contains(reloadedStore.visibleRemainingSeconds))
        XCTAssertTrue(["4:17", "4:18"].contains(reloadedStore.formattedRemaining))
    }

    func testResumeTimerIfNeededUpdatesRemainingTimeForActiveTimer() throws {
        _ = try store.startTimerForTaskNamed("Resume me")
        store.timerState.startDate = Date().addingTimeInterval(-30)

        store.resumeTimerIfNeeded()

        XCTAssertEqual(store.timerState.remainingSeconds, Int(Constants.Timer.durationSeconds) - 30)
        XCTAssertFalse(store.timerState.isCompleted)
        XCTAssertTrue(store.isTimerActive)
    }

    func testVisibleRemainingSecondsUsesStartDateWhileTimerIsActive() throws {
        _ = try store.startTimerForTaskNamed("Visible remaining")
        store.timerState.startDate = Date().addingTimeInterval(-30)
        store.timerState.remainingSeconds = Int(Constants.Timer.durationSeconds)

        XCTAssertEqual(store.visibleRemainingSeconds, Int(Constants.Timer.durationSeconds) - 30)
        XCTAssertEqual(store.formattedRemaining, "4:30")
    }

    func testResumeTimerIfNeededCompletesExpiredTimer() throws {
        _ = try store.startTimerForTaskNamed("Expired")
        store.timerState.startDate = Date().addingTimeInterval(-(Constants.Timer.durationSeconds + 5))

        store.resumeTimerIfNeeded()

        XCTAssertTrue(store.timerState.isCompleted)
        XCTAssertEqual(store.timerState.remainingSeconds, 0)
        XCTAssertEqual(store.stats.completedBlocks, 1)
        XCTAssertTrue(store.isTimerPresentationActive)
    }

    func testVisibleRemainingSecondsUsesStoredZeroForCompletedTimer() throws {
        _ = try store.startTimerForTaskNamed("Completed visible")
        store.timerState.startDate = Date().addingTimeInterval(-(Constants.Timer.durationSeconds + 5))

        store.resumeTimerIfNeeded()

        XCTAssertEqual(store.visibleRemainingSeconds, 0)
        XCTAssertEqual(store.formattedRemaining, "0:00")
    }

    func testToggleCameraPersistsSettingAcrossReload() {
        XCTAssertFalse(store.taskState.isCameraEnabled)

        store.toggleCamera()

        XCTAssertTrue(store.taskState.isCameraEnabled)

        let reloadedStore = FocusStore(persistenceService: persistence, notificationService: notifications)
        XCTAssertTrue(reloadedStore.taskState.isCameraEnabled)
    }

    func testSupportiveUtterancesPersistAcrossReload() {
        let customUtterances = ["One", "Two", "Three"]

        store.updateSupportiveUtterances(customUtterances)

        let reloadedStore = FocusStore(persistenceService: persistence, notificationService: notifications)
        XCTAssertEqual(reloadedStore.userState.selectedVoiceMode, .supportive)
        XCTAssertEqual(reloadedStore.userState.supportiveUtterances, customUtterances)
        XCTAssertEqual(reloadedStore.awayUtterances, customUtterances)
    }

    func testAwayFailureSecondsPersistAcrossReload() {
        store.updateAwayFailureSeconds(12)

        let reloadedStore = FocusStore(persistenceService: persistence, notificationService: notifications)
        XCTAssertEqual(reloadedStore.awayFailureSeconds, 12)
        XCTAssertEqual(reloadedStore.userState.awayFailureSeconds, 12)
    }

    func testLegacyStrictVoiceModeDecodesAsSupportive() throws {
        let legacyState = PersistedState(
            tasks: [],
            stats: FocusStats(),
            activeTaskID: nil,
            timerStartDate: nil,
            remainingSeconds: Int(Constants.Timer.durationSeconds),
            timerCompleted: false,
            isCameraEnabled: false,
            selectedVoiceMode: try JSONDecoder().decode(AwayVoiceMode.self, from: Data("\"strict\"".utf8)),
            supportiveUtterances: ["Custom" ],
            awayFailureSeconds: 6
        )

        try persistence.save(legacyState, forKey: Constants.Persistence.storeKey)

        let reloadedStore = FocusStore(persistenceService: persistence, notificationService: notifications)
        XCTAssertEqual(reloadedStore.userState.selectedVoiceMode, .supportive)
        XCTAssertEqual(reloadedStore.awayUtterances, ["Custom"])
    }

    func testReloadResetsTodayBlocksWhenPersistedStatsDayIsOld() throws {
        var oldStats = FocusStats()
        oldStats.statsDay = "2000-01-01"
        oldStats.todayBlocks = 24
        oldStats.completedBlocks = 7
        oldStats.failedBlocks = 5
        oldStats.totalBlocks = 12
        oldStats.streak = 3

        let persistedState = PersistedState(
            tasks: [],
            stats: oldStats,
            activeTaskID: nil,
            timerStartDate: nil,
            remainingSeconds: Int(Constants.Timer.durationSeconds),
            timerCompleted: false,
            isCameraEnabled: false,
            selectedVoiceMode: .supportive,
            supportiveUtterances: AwayVoiceMode.supportive.utterances,
            awayFailureSeconds: 6
        )

        try persistence.save(persistedState, forKey: Constants.Persistence.storeKey)

        let reloadedStore = FocusStore(persistenceService: persistence, notificationService: notifications)
        XCTAssertEqual(reloadedStore.stats.todayBlocks, 0)
        XCTAssertEqual(reloadedStore.stats.completedBlocks, 7)
        XCTAssertEqual(reloadedStore.stats.failedBlocks, 5)
        XCTAssertEqual(reloadedStore.stats.totalBlocks, 12)
        XCTAssertEqual(reloadedStore.stats.streak, 3)
        XCTAssertEqual(reloadedStore.stats.statsDay, FocusStats.currentStatsDay)
    }

    func testClearAllResetsTasksStatsAndTimerState() throws {
        _ = try store.startTimerForTaskNamed("Wipe me")
        store.toggleCamera()
        store.completeTimer()

        try store.clearAll()

        XCTAssertTrue(store.taskState.tasks.isEmpty)
        XCTAssertEqual(store.stats.todayBlocks, 0)
        XCTAssertEqual(store.stats.totalBlocks, 0)
        XCTAssertEqual(store.stats.completedBlocks, 0)
        XCTAssertEqual(store.stats.failedBlocks, 0)
        XCTAssertEqual(store.stats.streak, 0)
        XCTAssertTrue(store.stats.taskStats.isEmpty)
        XCTAssertTrue(store.stats.taskTimeSpent.isEmpty)
        XCTAssertNil(store.timerState.activeTaskID)
        XCTAssertNil(store.timerState.startDate)
        XCTAssertFalse(store.timerState.isCompleted)
        XCTAssertFalse(store.taskState.isCameraEnabled)
        XCTAssertEqual(store.userState, UserState())
    }
}
