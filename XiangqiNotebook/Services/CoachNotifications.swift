import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
import ServiceManagement
#endif

struct CoachReminder: Equatable {
    let id: String
    let date: Date
}

enum CoachReminderSchedule {
    static let prefix = "coach.local."
    static func reminders(snapshot: CoachSnapshot, deviceID: String, anchor: Date? = nil) -> [CoachReminder] {
        guard let p = snapshot.effectivePreferences, p.enabled, p.reminderDeviceID == deviceID else { return [] }
        let due = snapshot.materials.filter { snapshot.allowedMaterialIDs.contains($0.id) }.map { snapshot.dueDate(for: $0) }.min()
        guard let due else { return [] }
        let c = snapshot.calendar
        var start = max(c.startOfDay(for: anchor ?? snapshot.now), due)
        if !snapshot.todayAttempts.isEmpty || snapshot.lessons.contains(where: { snapshot.isDeferred($0.id) }) {
            start = max(start, c.date(byAdding: .day, value: 1, to: c.startOfDay(for: snapshot.now))!)
        }
        // Fixed engagement anchor, not a rolling 'now' on each background tick. No indefinite nagging.
        return [0, 1, 3, 6].compactMap { offset in
            guard let day = c.date(byAdding: .day, value: offset, to: start),
                  let date = c.date(bySettingHour: p.hour, minute: 0, second: 0, of: day),
                  date > snapshot.now, p.endDate.map({ date < $0 }) ?? true else { return nil }
            return CoachReminder(id: prefix + String(Int(date.timeIntervalSince1970)), date: date)
        }
    }

}

@MainActor
final class CoachNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = CoachNotifications()
    @Published var lessonID: String?
    @Published var status = "本地通知尚未开启"
    private var scheduleRevision = 0
    private var desiredIDs: Set<String> = []
    #if os(macOS)
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    #endif
    func becameActive() { UserDefaults.standard.set(Date(), forKey: "coach.reminderAnchor") }
    func install() {
        guard !AIKeychain.isRunningInTests else { return }
        UNUserNotificationCenter.current().delegate = self
        CoachViewModel.shared.start()
    }
    func enable() async {
        guard !AIKeychain.isRunningInTests else { return }
        do {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            UserDefaults.standard.set(allowed, forKey: "coach.notificationsEnabled")
            status = allowed ? "本地通知已开启；提醒设备和时间按已批准计划执行" : "系统未允许通知，仍可在课堂继续学习"
        } catch { status = "通知设置失败：\(error.localizedDescription)" }
    }
    func schedule(snapshot: CoachSnapshot, deviceID: String) async {
        let center = UNUserNotificationCenter.current()
        scheduleRevision += 1
        let revision = scheduleRevision
        let anchor = UserDefaults.standard.object(forKey: "coach.reminderAnchor") as? Date ?? snapshot.now
        let reminders = CoachReminderSchedule.reminders(snapshot: snapshot, deviceID: deviceID, anchor: anchor)
        desiredIDs = UserDefaults.standard.bool(forKey: "coach.notificationsEnabled") ? Set(reminders.map(\.id)) : []
        let pending = await center.pendingNotificationRequests()
        guard revision == scheduleRevision else { return }
        let ours = pending.filter { $0.identifier.hasPrefix(CoachReminderSchedule.prefix) }
        guard UserDefaults.standard.bool(forKey: "coach.notificationsEnabled"), !reminders.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: ours.map(\.identifier))
            return
        }
        let settings = await center.notificationSettings()
        guard revision == scheduleRevision else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            status = "系统通知权限已关闭；可在系统设置中重新开启"
            return
        }
        // Keep existing reminders if replacement fails. Other app features own their own identifiers.
        do {
            for reminder in reminders where !pending.contains(where: { $0.identifier == reminder.id }) {
                let content = UNMutableNotificationContent()
                content.title = "来上一小节象棋课"
                content.body = "打开笔记本，教练会接着你的进度带你学习和复习。"
                content.sound = .default
                content.userInfo = ["coachLessonId": "today"]
                var components = snapshot.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                components.timeZone = snapshot.calendar.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                guard revision == scheduleRevision else { return }
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
                if revision != scheduleRevision {
                    if !desiredIDs.contains(reminder.id) { center.removePendingNotificationRequests(withIdentifiers: [reminder.id]) }
                    return
                }
            }
            let keep = Set(reminders.map(\.id))
            center.removePendingNotificationRequests(withIdentifiers: ours.filter { !keep.contains($0.identifier) }.map(\.identifier))
            status = "已安排本地学习提醒；不需要服务器。系统专注模式可能使通知静音。"
        } catch { if revision == scheduleRevision { status = "新提醒未安排成功，已保留已有提醒：\(error.localizedDescription)" } }
    }
    #if os(macOS)
    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            status = loginEnabled ? "已开启登录 Mac 时启动" : "自动启动未启用；可在系统登录项中检查权限"
        } catch { status = "自动启动设置失败：\(error.localizedDescription)" }
    }
    #endif
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["coachLessonId"] as? String
        Task { @MainActor in self.lessonID = id == nil ? nil : UUID().uuidString }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
#if os(iOS)
final class CoachAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        CoachNotifications.shared.install(); return true
    }
}
#else
final class CoachAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { CoachNotifications.shared.install() }
    func applicationWillTerminate(_ notification: Notification) { CoachViewModel.shared.flushDraft() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#endif
