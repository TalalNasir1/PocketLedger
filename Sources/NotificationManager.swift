import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private init() {}

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func status() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func reschedule(from data: LedgerData) {
        center.removeAllPendingNotificationRequests()
        var requestCount = 0
        for subscription in data.subscriptions.filter(\.isActive).sorted(by: { $0.nextDueDate < $1.nextDueDate }) {
            var dueDate = subscription.nextDueDate
            let today = Calendar.current.startOfDay(for: Date())
            while dueDate < today { dueDate = subscription.dateAfter(dueDate) }
            for occurrence in 0..<6 where requestCount < 60 {
                let reminder = Calendar.current.date(byAdding: .day, value: -subscription.reminderDays, to: dueDate) ?? dueDate
                var scheduledDate = reminder
                if reminder <= Date(), dueDate >= today {
                    scheduledDate = Date().addingTimeInterval(5)
                }
                var components = Calendar.current.dateComponents([.year, .month, .day], from: scheduledDate)
                components.hour = data.settings.reminderHour
                components.minute = 0
                if scheduledDate.timeIntervalSinceNow < 60 {
                    components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: scheduledDate)
                }
                guard let scheduled = Calendar.current.date(from: components), scheduled > Date() else {
                    dueDate = subscription.dateAfter(dueDate)
                    continue
                }
                let content = UNMutableNotificationContent()
                content.title = "Subscription payment coming up"
                let amount = subscription.amount.formatted(.currency(code: data.settings.currencyCode))
                let actualDays = max(Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: dueDate)).day ?? 0, 0)
                if actualDays == 0 {
                    content.body = "\(subscription.name) payment of \(amount) is due today."
                } else {
                    content.body = "\(subscription.name) payment of \(amount) is due in \(actualDays) day\(actualDays == 1 ? "" : "s")."
                }
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "subscription-\(subscription.id.uuidString)-\(occurrence)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
                requestCount += 1
                dueDate = subscription.dateAfter(dueDate)
            }
        }
    }
}
