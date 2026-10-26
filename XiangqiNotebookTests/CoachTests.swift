import Foundation
import Testing
import SwiftUI
@testable import XiangqiNotebook
#if os(macOS)
import AppKit
#endif

@MainActor
struct CoachTests {
    private final class StubPlatformService: PlatformService {
        func openURL(_ url: URL) {}
        func showAlert(title: String, message: String) {}
        func showWarningAlert(title: String, message: String) {}
        func showConfirmAlert(title: String, message: String, completion: @escaping (Bool) throws -> Void) { try? completion(false) }
        func saveFile(defaultName: String, completion: @escaping (URL?) -> Void) { completion(nil) }
        func openFile(completion: @escaping (URL?) -> Void) { completion(nil) }
        func backupData(_ data: Data, defaultName: String, completion: @escaping (Bool) -> Void) { completion(false) }
        func recoverData(completion: @escaping (Data?) -> Void) { completion(nil) }
    }
    private let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
    private func snapshot(draft: CoachDraft? = nil, revision: Int = 1, devicesEpoch: Int = 0, enabled: Bool = true, preferencesRevision: Int = 1) -> CoachSnapshot {
        let material = CoachMaterial(id: "source-1", title: "布局笔记第一节", locator: "布局笔记 / 第一节 / 节点 1",
                                     fen: fen, note: "先观察对方的威胁，再考虑自己的计划。", objective: "说清双方的计划", dueAt: "2026-10-27T11:00:00.000Z", intervalDays: 1)
        let lesson = CoachLesson(id: "lesson-1", materialId: material.id, createdAt: "2026-10-26T11:00:00.000Z", completedAt: nil,
            reason: "从你选定的教材笔记开始，先了解你的思路。",
            content: .init(sourceId: material.id, title: "先看对方，再想自己", question: "在这个局面中，你准备先观察什么？请说说你的思路。",
                           explanation: "原笔记建议先观察对方威胁。具体着法与变化还需要引擎核验。", hint: "先想想对手下一步想做什么。"),
            minutes: 10, provenance: "ai-explanation-unverified", model: "test-fixture")
        return CoachSnapshot(revision: revision, preferences: CoachPreferences(enabled: enabled), materials: [material], lessons: [lesson], attempts: [],
                             activeLesson: lesson, lastError: nil, capabilities: .init(generator: true, push: false), deliveryStatus: "none", draft: draft, devicesEpoch: devicesEpoch, preferencesRevision: preferencesRevision)
    }
    private func makeNotebook() -> ViewModel {
        let database = TestDatabaseBuilder().addFen(1, fen: fen).build()
        let data = SessionData()
        data.currentGame2 = [1]; data.currentGameStep = 0
        let session = try! Session(sessionData: data, databaseView: .full(database: database))
        return ViewModel(sessionManager: SessionManager(mainSession: session, database: database), platformService: StubPlatformService())
    }
    @Test func endpointRejectsCredentialLeakDestinations() throws {
        for value in ["http://example.com", "https://user:pass@example.com", "https://example.com/?token=x", "https://example.com/#x", "https://example.com/api", "file:///tmp/data"] {
            #expect(throws: CoachServiceError.self) { try CoachAPI.endpoint(value) }
        }
        #expect(try CoachAPI.endpoint("https://example.com").host == "example.com")
        #expect(try CoachAPI.endpoint("http://127.0.0.1:9220").port == 9220)
    }
    @Test func localDraftSurvivesReopenAndKeepsHintEvidence() throws {
        let suite = "CoachTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CoachViewModel(defaults: defaults, initialSnapshot: snapshot())
        first.answer = "先观察对方威胁"; first.showHint = true; first.saveDraft()
        let second = CoachViewModel(defaults: defaults, initialSnapshot: snapshot())
        #expect(second.answer == "先观察对方威胁")
        #expect(second.revealed)
        #expect(second.board.getFen() == fen)
    }
    @Test func staleLocalDraftDoesNotBorrowNewerRemoteRevision() throws {
        let suite = "CoachConflict.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "coach.draft.https://coach.example.test"
        let local = CoachDraft(lessonId: "lesson-1", answer: "尚未同步的本地思路", revealed: false, revision: 1)
        defaults.set(try JSONEncoder().encode(local), forKey: key)
        let remote = CoachDraft(lessonId: "lesson-1", answer: "另一台设备的新思路", revealed: true, revision: 2)
        let coach = CoachViewModel(defaults: defaults, initialSnapshot: snapshot(draft: remote))
        coach.saveDraft()
        let saved = try JSONDecoder().decode(CoachDraft.self, from: #require(defaults.data(forKey: key)))
        #expect(saved.answer == local.answer)
        #expect(saved.revision == 1)
        coach.loadRemoteDraft()
        #expect(coach.answer == remote.answer)
        #expect(coach.revealed)
    }
    @Test func savedConnectionRetriesAfterOfflineLaunchWithoutSendingCredentialsToEditedAddress() async {
        let suite = "CoachRetry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://saved.example.test", forKey: "coach.endpoint")
        let response = snapshot()
        var calls = 0
        let coach = CoachViewModel(defaults: defaults, readCredential: { _ in String(repeating: "x", count: 40) }, fetchSnapshot: { api in
            #expect(api.endpoint.host == "saved.example.test")
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return response
        })
        coach.endpoint = "https://edited.example.test"
        let start = Date(timeIntervalSince1970: 1000)
        await coach.reconnectIfNeeded(now: start)
        #expect(!coach.isConnected)
        await coach.reconnectIfNeeded(now: start.addingTimeInterval(10))
        #expect(calls == 1)
        await coach.reconnectIfNeeded(now: start.addingTimeInterval(30))
        #expect(coach.isConnected)
        #expect(coach.lesson?.id == "lesson-1")
    }
    @Test func remoteResetRevokesStaleDeviceConsent() async {
        let suite = "CoachReset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "coach.notificationsEnabled")
        let response = snapshot(revision: 2, devicesEpoch: 1, enabled: false)
        let coach = CoachViewModel(defaults: defaults, initialSnapshot: snapshot(), fetchSnapshot: { _ in response })
        await coach.refresh()
        #expect(!defaults.bool(forKey: "coach.notificationsEnabled"))
        #expect(!coach.preferences.enabled)
    }
    @Test func backgroundRefreshDoesNotRebaseUnsavedPreferences() async {
        let suite = "CoachPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let response = snapshot(revision: 2, enabled: false, preferencesRevision: 2)
        let coach = CoachViewModel(defaults: defaults, initialSnapshot: snapshot(), fetchSnapshot: { _ in response })
        coach.preferences.goal = "我正在编辑的目标"
        await coach.refresh()
        #expect(coach.preferences.goal == "我正在编辑的目标")
        #expect(coach.preferencesRevision == 1)
        #expect(coach.snapshot?.revision == 2)
        coach.reloadPreferences()
        #expect(!coach.preferences.enabled)
        #expect(coach.preferencesRevision == 2)
    }
    @Test func sourceSnapshotDoesNotAlterNotebook() {
        let notebook = makeNotebook()
        let before = notebook.currentFen
        let source = notebook.coachCurrentSource()
        #expect(source.fen == before)
        #expect(source.locator.contains("节点"))
        #expect(notebook.currentFen == before)
    }
    #if os(macOS)
    @Test func renderCoachClassroom() async throws {
        let suite = "CoachRender.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coach = CoachViewModel(defaults: defaults, initialSnapshot: snapshot())
        for width in [760, 390] {
            let view = CoachView(coach: coach, notebook: makeNotebook()).frame(width: CGFloat(width), height: 1120).background(.white)
                .environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: width, height: 1120), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/xiangqi-coach-classroom-\(width).png"))
            window.orderOut(nil)
            #expect(png.count > 30000)
        }
    }
    #endif
}
