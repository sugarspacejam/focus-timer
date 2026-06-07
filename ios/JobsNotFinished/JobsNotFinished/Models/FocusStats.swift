import Foundation

struct FocusStats: Codable {
    var statsDay: String
    var todayBlocks: Int
    var completedBlocks: Int
    var failedBlocks: Int
    var totalBlocks: Int
    var streak: Int
    var taskStats: [UUID: TaskStat]
    var taskTimeSpent: [UUID: Int]
    
    // Flame system
    var totalFirePower: Int
    var currentMomentumStreak: Int
    var lastBlockEndTime: Date?
    var gracePeriodEndTime: Date?
    var bestMomentum: Int
    var totalKeptBlocks: Int
    var totalFailedBlocks: Int
    var todayFirePowerEarned: Int
    var lastKeptBlockCompletedAt: Date?

    init() {
        self.statsDay = FocusStats.currentStatsDay
        self.todayBlocks = 0
        self.completedBlocks = 0
        self.failedBlocks = 0
        self.totalBlocks = 0
        self.streak = 0
        self.taskStats = [:]
        self.taskTimeSpent = [:]
        self.totalFirePower = 0
        self.currentMomentumStreak = 0
        self.lastBlockEndTime = nil
        self.gracePeriodEndTime = nil
        self.bestMomentum = 0
        self.totalKeptBlocks = 0
        self.totalFailedBlocks = 0
        self.todayFirePowerEarned = 0
        self.lastKeptBlockCompletedAt = nil
    }

    private enum CodingKeys: String, CodingKey {
        case statsDay
        case todayBlocks
        case completedBlocks
        case failedBlocks
        case totalBlocks
        case streak
        case taskStats
        case taskTimeSpent
        case totalFirePower
        case currentMomentumStreak
        case lastBlockEndTime
        case gracePeriodEndTime
        case bestMomentum
        case totalKeptBlocks
        case totalFailedBlocks
        case todayFirePowerEarned
        case lastKeptBlockCompletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statsDay = try container.decodeIfPresent(String.self, forKey: .statsDay) ?? FocusStats.currentStatsDay
        todayBlocks = try container.decodeIfPresent(Int.self, forKey: .todayBlocks) ?? 0
        completedBlocks = try container.decodeIfPresent(Int.self, forKey: .completedBlocks) ?? 0
        failedBlocks = try container.decodeIfPresent(Int.self, forKey: .failedBlocks) ?? 0
        totalBlocks = try container.decodeIfPresent(Int.self, forKey: .totalBlocks) ?? 0
        streak = try container.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        taskStats = try container.decodeIfPresent([UUID: TaskStat].self, forKey: .taskStats) ?? [:]
        taskTimeSpent = try container.decodeIfPresent([UUID: Int].self, forKey: .taskTimeSpent) ?? [:]
        totalFirePower = try container.decodeIfPresent(Int.self, forKey: .totalFirePower) ?? 0
        currentMomentumStreak = try container.decodeIfPresent(Int.self, forKey: .currentMomentumStreak) ?? 0
        lastBlockEndTime = try container.decodeIfPresent(Date.self, forKey: .lastBlockEndTime)
        gracePeriodEndTime = try container.decodeIfPresent(Date.self, forKey: .gracePeriodEndTime)
        bestMomentum = try container.decodeIfPresent(Int.self, forKey: .bestMomentum) ?? 0
        totalKeptBlocks = try container.decodeIfPresent(Int.self, forKey: .totalKeptBlocks) ?? 0
        totalFailedBlocks = try container.decodeIfPresent(Int.self, forKey: .totalFailedBlocks) ?? 0
        todayFirePowerEarned = try container.decodeIfPresent(Int.self, forKey: .todayFirePowerEarned) ?? 0
        lastKeptBlockCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastKeptBlockCompletedAt)
    }

    static var currentStatsDay: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    static let gracePeriodSeconds: TimeInterval = 15 * 60 // 15 minutes
}

struct TaskStat: Codable {
    var completed: Int
    var failed: Int
    
    init(completed: Int, failed: Int) {
        self.completed = completed
        self.failed = failed
    }
}
