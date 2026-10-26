import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Push carries only a lesson identifier. Fetch content from the authenticated service on open.
@MainActor
final class CoachNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = CoachNotifications()
    @Published var lessonID: String?
    @Published var deviceToken: String?
    @Published var status = "尚未开启通知"
    func install() {
        guard !AIKeychain.isRunningInTests else { return }
        UNUserNotificationCenter.current().delegate = self
        if UserDefaults.standard.bool(forKey: "coach.notificationsEnabled") {
            Task { await enable() }
        }
    }
    func enable() async {
        guard !AIKeychain.isRunningInTests else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
                status = "通知权限未开启，仍可在课堂查看课程"; return
            }
            UserDefaults.standard.set(true, forKey: "coach.notificationsEnabled")
            status = "正在向 Apple 注册此设备…"
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #else
            NSApplication.shared.registerForRemoteNotifications()
            #endif
        } catch { status = "通知注册失败：\(error.localizedDescription)" }
    }
    func receivedToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        status = "Apple 设备注册成功，正在同步教练服务"
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["coachLessonId"] as? String
        Task { @MainActor in self.lessonID = id }
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
        CoachNotifications.shared.install()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        CoachNotifications.shared.receivedToken(deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CoachNotifications.shared.status = "设备注册失败，请检查推送签名配置：\(error.localizedDescription)"
    }
}
#else
final class CoachAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CoachNotifications.shared.install()
    }
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        CoachNotifications.shared.receivedToken(deviceToken)
    }
    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CoachNotifications.shared.status = "设备注册失败，请检查推送签名配置：\(error.localizedDescription)"
    }
}
#endif
