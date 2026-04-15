import Foundation

enum Constants {
    enum Timer {
        static let durationSeconds: TimeInterval = 300 // 5 minutes
    }
    
    enum Limits {
        static let freeContractsPerDay = 5
    }
    
    enum Notifications {
        static let timerCompleteIdentifier = "focus.timer.complete"
    }
    
    enum Persistence {
        static let storeKey = "focus.store.v3"
    }
    
    enum UI {
        static let minimumTaskNameLength = 2
    }
}
