import Foundation

struct PersistedState: Codable {
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
