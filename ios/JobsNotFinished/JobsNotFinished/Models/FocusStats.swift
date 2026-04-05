import Foundation

struct FocusStats: Codable {
    var todayBlocks: Int
    var completedBlocks: Int
    var failedBlocks: Int
    var totalBlocks: Int
    var streak: Int
    var taskStats: [UUID: TaskStat]
    var taskTimeSpent: [UUID: Int]

    init() {
        self.todayBlocks = 0
        self.completedBlocks = 0
        self.failedBlocks = 0
        self.totalBlocks = 0
        self.streak = 0
        self.taskStats = [:]
        self.taskTimeSpent = [:]
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
