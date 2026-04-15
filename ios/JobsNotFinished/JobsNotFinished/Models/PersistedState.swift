import Foundation

struct PersistedState: Codable {
    var tasks: [FocusTask]
    var stats: FocusStats
    var activeTaskID: UUID?
    var timerStartDate: Date?
    var remainingSeconds: Int
    var timerCompleted: Bool
    var isCameraEnabled: Bool
    var selectedVoiceMode: AwayVoiceMode
    var supportiveUtterances: [String]
    var awayFailureSeconds: Int

    init(tasks: [FocusTask], stats: FocusStats, activeTaskID: UUID?, timerStartDate: Date?, remainingSeconds: Int, timerCompleted: Bool, isCameraEnabled: Bool, selectedVoiceMode: AwayVoiceMode, supportiveUtterances: [String], awayFailureSeconds: Int) {
        self.tasks = tasks
        self.stats = stats
        self.activeTaskID = activeTaskID
        self.timerStartDate = timerStartDate
        self.remainingSeconds = remainingSeconds
        self.timerCompleted = timerCompleted
        self.isCameraEnabled = isCameraEnabled
        self.selectedVoiceMode = selectedVoiceMode
        self.supportiveUtterances = supportiveUtterances
        self.awayFailureSeconds = awayFailureSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([FocusTask].self, forKey: .tasks)
        stats = try container.decode(FocusStats.self, forKey: .stats)
        activeTaskID = try container.decodeIfPresent(UUID.self, forKey: .activeTaskID)
        timerStartDate = try container.decodeIfPresent(Date.self, forKey: .timerStartDate)
        remainingSeconds = try container.decodeIfPresent(Int.self, forKey: .remainingSeconds) ?? Int(Constants.Timer.durationSeconds)
        timerCompleted = try container.decode(Bool.self, forKey: .timerCompleted)
        isCameraEnabled = try container.decode(Bool.self, forKey: .isCameraEnabled)
        selectedVoiceMode = try container.decodeIfPresent(AwayVoiceMode.self, forKey: .selectedVoiceMode) ?? .supportive
        supportiveUtterances = try container.decodeIfPresent([String].self, forKey: .supportiveUtterances) ?? AwayVoiceMode.supportive.utterances
        awayFailureSeconds = try container.decodeIfPresent(Int.self, forKey: .awayFailureSeconds) ?? 6
    }
}
