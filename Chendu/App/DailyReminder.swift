import BackgroundTasks
import Foundation
import UserNotifications

enum DailyReminder {
    static let enabledKey = "dailyReminderEnabled"
    static let requestID = "chendu.daily"
    static let refreshTaskID = "com.scoheart.chendu.refresh"
    private static let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        schedule()
        scheduleRefresh()
        return true
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID])
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
    }

    /// Next occurrence of `hour:minute` Beijing time.
    static func next(hour: Int, minute: Int, after date: Date = .now) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghai
        return cal.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime) ?? date
    }

    /// Repeating 8:00 Beijing reminder, expressed in the device's current time zone. Re-run on launch.
    static func schedule() {
        guard isEnabled else { return }
        let fire = next(hour: 8, minute: 0)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: fire)
        let content = UNMutableNotificationContent()
        content.title = "晨读 · 新一期已上线"
        content.body = "今天的英文精读和朗读音频已经准备好了。"
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
    }

    /// Ask iOS to wake the app shortly after publication to cache the newest issue.
    static func scheduleRefresh() {
        guard isEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = next(hour: 7, minute: 55)
        try? BGTaskScheduler.shared.submit(req)
    }
}
