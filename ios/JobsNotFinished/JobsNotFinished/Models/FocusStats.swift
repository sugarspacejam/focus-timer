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

    init() {
        self.statsDay = FocusStats.currentStatsDay
        self.todayBlocks = 0
        self.completedBlocks = 0
        self.failedBlocks = 0
        self.totalBlocks = 0
        self.streak = 0
        self.taskStats = [:]
        self.taskTimeSpent = [:]
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
    }

    static var currentStatsDay: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

struct TaskStat: Codable {
    var completed: Int
    var failed: Int
    
    init(completed: Int, failed: Int) {
        self.completed = completed
        self.failed = failed
    }
}
