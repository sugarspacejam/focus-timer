import Foundation

struct PersistedState: Codable {
    var tasks: [FocusTask]
    var stats: FocusStats
    var activeTaskID: UUID?
    var timerStartDate: Date?
    var remainingSeconds: Int
    var timerCompleted: Bool
    var selectedVoiceMode: AwayVoiceMode
    var supportiveUtterances: [String]
    var awayFailureSeconds: Int
    var themeMode: AppThemeMode
    var dailyContractsStarted: Int
    var lastContractDate: Date?

    init(tasks: [FocusTask], stats: FocusStats, activeTaskID: UUID?, timerStartDate: Date?, remainingSeconds: Int, timerCompleted: Bool, selectedVoiceMode: AwayVoiceMode, supportiveUtterances: [String], awayFailureSeconds: Int, themeMode: AppThemeMode, dailyContractsStarted: Int, lastContractDate: Date?) {
        self.tasks = tasks
        self.stats = stats
        self.activeTaskID = activeTaskID
        self.timerStartDate = timerStartDate
        self.remainingSeconds = remainingSeconds
        self.timerCompleted = timerCompleted
        self.selectedVoiceMode = selectedVoiceMode
        self.supportiveUtterances = supportiveUtterances
        self.awayFailureSeconds = awayFailureSeconds
        self.themeMode = themeMode
        self.dailyContractsStarted = dailyContractsStarted
        self.lastContractDate = lastContractDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([FocusTask].self, forKey: .tasks)
        stats = try container.decode(FocusStats.self, forKey: .stats)
        activeTaskID = try container.decodeIfPresent(UUID.self, forKey: .activeTaskID)
        timerStartDate = try container.decodeIfPresent(Date.self, forKey: .timerStartDate)
        remainingSeconds = try container.decodeIfPresent(Int.self, forKey: .remainingSeconds) ?? Int(Constants.Timer.durationSeconds)
        timerCompleted = try container.decode(Bool.self, forKey: .timerCompleted)
        selectedVoiceMode = try container.decodeIfPresent(AwayVoiceMode.self, forKey: .selectedVoiceMode) ?? .supportive
        supportiveUtterances = try container.decodeIfPresent([String].self, forKey: .supportiveUtterances) ?? AwayVoiceMode.supportive.utterances
        awayFailureSeconds = try container.decodeIfPresent(Int.self, forKey: .awayFailureSeconds) ?? 6
        themeMode = try container.decodeIfPresent(AppThemeMode.self, forKey: .themeMode) ?? .system
        dailyContractsStarted = try container.decodeIfPresent(Int.self, forKey: .dailyContractsStarted) ?? 0
        lastContractDate = try container.decodeIfPresent(Date.self, forKey: .lastContractDate)
    }
}
