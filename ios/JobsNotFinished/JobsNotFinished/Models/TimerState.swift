import Foundation

enum AppThemeMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

struct TimerState: Equatable {
    var activeTaskID: UUID?
    var startDate: Date?
    var blockStartedAt: Date?
    var remainingSeconds: Int
    var isCompleted: Bool
    var motivationalMessageIndex: Int
    
    init() {
        self.activeTaskID = nil
        self.startDate = nil
        self.blockStartedAt = nil
        self.remainingSeconds = Int(Constants.Timer.durationSeconds)
        self.isCompleted = false
        self.motivationalMessageIndex = 0
    }
}

struct TaskState: Equatable {
    var tasks: [FocusTask]
    
    init() {
        self.tasks = []
    }
}

struct UserState: Equatable {
    var selectedVoiceMode: AwayVoiceMode
    var supportiveUtterances: [String]
    var awayFailureSeconds: Int
    var themeMode: AppThemeMode
    var dailyContractsStarted: Int
    var lastContractDate: Date?
    var countdownSpeakingEnabled: Bool
    var paywallPreferences: PaywallPreferences
    
    init() {
        self.selectedVoiceMode = .supportive
        self.supportiveUtterances = AwayVoiceMode.supportive.utterances
        self.awayFailureSeconds = 6
        self.themeMode = .system
        self.dailyContractsStarted = 0
        self.lastContractDate = nil
        self.countdownSpeakingEnabled = true
        self.paywallPreferences = .default
    }
}
