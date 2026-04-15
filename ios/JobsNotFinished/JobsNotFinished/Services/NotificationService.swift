import Foundation
import UserNotifications

protocol NotificationServicing {
    func requestPermissions() async throws
    func scheduleTimerCompletion(for taskName: String, at date: Date) async throws
    func cancelTimerCompletion() async
}

class NotificationService: ObservableObject, NotificationServicing {
    private let center = UNUserNotificationCenter.current()
    
    func requestPermissions() async throws {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    func scheduleTimerCompletion(for taskName: String, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "JOB'S NOT FINISHED"
        content.body = "\(taskName) — 5 minutes done. Keep going or move on?"
        content.sound = .default
        
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: Constants.Notifications.timerCompleteIdentifier,
            content: content,
            trigger: trigger
        )
        
        try await center.add(request)
    }
    
    func cancelTimerCompletion() async {
        center.removePendingNotificationRequests(withIdentifiers: [Constants.Notifications.timerCompleteIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Constants.Notifications.timerCompleteIdentifier])
    }
}
