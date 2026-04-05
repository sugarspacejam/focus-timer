import Foundation

enum AppError: LocalizedError {
    case transactionVerificationFailed
    case persistenceError(PersistenceError)
    case cameraPermissionDenied
    case notificationPermissionDenied
    case taskNameTooShort
    case taskAlreadyExists
    case contractLimitReached
    
    var errorDescription: String? {
        switch self {
        case .transactionVerificationFailed:
            return "Could not verify purchase"
        case .persistenceError(let error):
            return error.localizedDescription
        case .cameraPermissionDenied:
            return "Camera access is required for accountability mode"
        case .notificationPermissionDenied:
            return "Notifications are required for timer reminders"
        case .taskNameTooShort:
            return "Task name must be at least \(Constants.UI.minimumTaskNameLength) characters"
        case .taskAlreadyExists:
            return "A task with this name already exists"
        case .contractLimitReached:
            return "You've reached your daily limit of \(Constants.Limits.freeContractsPerDay) contracts. Upgrade to Pro for unlimited contracts."
        }
    }
}
