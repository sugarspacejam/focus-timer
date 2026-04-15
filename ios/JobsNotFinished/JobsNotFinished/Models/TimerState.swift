import Foundation

struct TimerState: Equatable {
    var activeTaskID: UUID?
    var startDate: Date?
    var remainingSeconds: Int
    var isCompleted: Bool
    var motivationalMessageIndex: Int
    
    init() {
        self.activeTaskID = nil
        self.startDate = nil
        self.remainingSeconds = Int(Constants.Timer.durationSeconds)
        self.isCompleted = false
        self.motivationalMessageIndex = 0
    }
}

struct TaskState: Equatable {
    var tasks: [FocusTask]
    var isCameraEnabled: Bool
    
    init() {
        self.tasks = []
        self.isCameraEnabled = false
    }
}

struct UserState: Equatable {
    var selectedVoiceMode: AwayVoiceMode
    var supportiveUtterances: [String]
    var awayFailureSeconds: Int
    
    init() {
        self.selectedVoiceMode = .supportive
        self.supportiveUtterances = AwayVoiceMode.supportive.utterances
        self.awayFailureSeconds = 6
    }
}
