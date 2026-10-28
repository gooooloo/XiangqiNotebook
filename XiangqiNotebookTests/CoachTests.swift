import Foundation
import Testing
import SwiftUI
@testable import XiangqiNotebook
#if os(macOS)
import AppKit
#endif

@MainActor
struct CoachTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
    private var material: CoachMaterial { CoachMaterial(id: "m", title: "布局笔记", locator: "第一章 / 节点 1", fen: fen, note: "先观察对方威胁，再考虑自己的计划。", objective: "理解双方思路") }
    private func event(_ payload: CoachPayload, id: String = UUID().uuidString, day: Double = 0, device: String = "mac") -> CoachEvent {
        CoachEvent(id: id, deviceID: device, createdAt: date.addingTimeInterval(day * 86400), payload: payload)
    }
    private func plan(_ parents: [String] = [], enabled: Bool = true, ids: [String] = ["m"], minutes: Int = 10, reminder: String? = "mac") -> CoachPlan {
        CoachPlan(parents: parents, preferences: CoachPreferences(enabled: enabled, dailyMinutes: minutes, reminderDeviceID: reminder), materialIDs: ids, rationale: "先读懂笔记，再练习和巩固")
    }
    private func approval(_ p: CoachPlan, id: String) -> [CoachEvent] {
        [event(.plan(p)), event(.approval(CoachApproval(planID: p.id, parents: p.parents)), id: id)]
    }
    private var base: [CoachEvent] { [event(.material(material))] + approval(plan(), id: "root") }
    private func attempt(id: String, lesson: String = "l", rating: String = "independent", day: Double = 0, supersedes: String? = nil) -> CoachEvent {
        event(.attempt(CoachAttempt(lessonId: lesson, materialId: "m", answer: "先看对方威胁", rating: rating, revealed: false, supersedes: supersedes)), id: id, day: day)
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CoachTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "CoachTests-" + UUID().uuidString)! }

    @Test func pendingPlanDoesNotGrantPermissionAndExactHashMatters() {
        let p = plan()
        let snapshot = CoachSnapshot(events: [event(.material(material)), event(.plan(p))], now: date)
        #expect(snapshot.effectivePreferences == nil)
        #expect(snapshot.pendingPlans.count == 1)
        let altered = CoachPlan(parents: [], preferences: p.preferences, materialIDs: [], rationale: p.rationale)
        #expect(altered.id != p.id)
        let invalid = CoachSnapshot(events: snapshot.events + [event(.approval(.init(planID: altered.id, parents: [])))], now: date)
        #expect(invalid.approvals.isEmpty)
    }
    @Test func concurrentApprovalsIntersectInsteadOfRestoringRevokedScope() {
        let left = plan(["root"], ids: ["m"], minutes: 5)
        let right = plan(["root"], enabled: false)
        let state = CoachSnapshot(events: base + approval(left, id: "left") + approval(right, id: "right"), now: date)
        #expect(state.heads.count == 2)
        #expect(state.effectivePreferences?.enabled == false)
        #expect(state.effectivePreferences?.dailyMinutes == 5)
        #expect(state.activeLesson == nil)
        #expect(CoachReminderSchedule.reminders(snapshot: state, deviceID: "mac").isEmpty)
        let merged = plan(["left", "right"])
        let resolved = CoachSnapshot(events: state.events + approval(merged, id: "merge"), now: date)
        #expect(resolved.headIDs == ["merge"])
    }
    @Test func missingAncestorCannotBecomeNewAuthorization() {
        let p = plan(["not-downloaded"])
        let snapshot = CoachSnapshot(events: [event(.material(material))] + approval(p, id: "child"), now: date)
        #expect(snapshot.heads.isEmpty)
    }
    @Test func correctionBranchesArePreservedAndConservative() {
        let state = CoachSnapshot(events: base + [attempt(id: "a"), attempt(id: "b", rating: "again", day: 1, supersedes: "a"), attempt(id: "c", day: 2, supersedes: "a")], now: date.addingTimeInterval(3 * 86400))
        #expect(state.attempts.count == 3)
        #expect(state.effectiveAttempts.count == 2)
        #expect(state.hasCorrectionConflict)
        #expect(state.dueDate(for: material) == state.calendar.date(byAdding: .day, value: 1, to: state.calendar.startOfDay(for: date)))
    }
    @Test func correctionDoesNotPretendToBeANewReview() {
        let corrected = CoachSnapshot(events: base + [attempt(id: "a", rating: "again"), attempt(id: "b", day: 5, supersedes: "a")], now: date.addingTimeInterval(6 * 86400))
        #expect(corrected.dueDate(for: material) == corrected.calendar.date(byAdding: .day, value: 1, to: corrected.calendar.startOfDay(for: date)))
    }
    @Test func duplicateDeliveryAndSameDayPracticeDoNotInflateMemory() {
        let a = attempt(id: "a")
        let once = CoachSnapshot(events: base + [a], now: date)
        let twice = CoachSnapshot(events: base + [a, a, attempt(id: "b", lesson: "second", day: 0.1)], now: date.addingTimeInterval(86400))
        #expect(twice.attempts.count == 2)
        #expect(once.dueDate(for: material) == twice.dueDate(for: material))
    }
    @Test func contradictoryIDIsNotSelectedByTimestamp() {
        let state = CoachSnapshot(events: base + [attempt(id: "same"), attempt(id: "same", rating: "again", day: 1)], now: date)
        #expect(state.conflictingEventIDs == ["same"])
        #expect(state.incomplete)
        #expect(state.attempts.isEmpty)
        let repeated = CoachSnapshot(events: state.events + state.conflictingEvents + state.conflictingEvents, now: date)
        #expect(repeated.conflictingEvents.count == 2)
    }
    @Test func clocksAndReminderOwnership() {
        let snapshot = CoachSnapshot(events: base, now: date)
        #expect(CoachReminderSchedule.reminders(snapshot: snapshot, deviceID: "mac").count >= 3)
        #expect(CoachReminderSchedule.reminders(snapshot: snapshot, deviceID: "phone").isEmpty)
        let future = CoachSnapshot(events: base + [attempt(id: "future", day: 10)], now: date)
        #expect(future.hasClockUncertainty)
        #expect(future.dueDate(for: material) == .distantPast)
    }
    @Test func offlineDevicesUnionOnDiskAndSurviveReopen() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud")
        let a = CoachStore(localURL: root.appendingPathComponent("mac"), cloudURL: cloud)
        let b = CoachStore(localURL: root.appendingPathComponent("phone"), cloudURL: cloud)
        for e in base { try await a.append(e) }
        try await a.append(attempt(id: "a"))
        try await b.append(attempt(id: "b", lesson: "other"))
        _ = await a.synchronize(now: date); _ = await b.synchronize(now: date)
        let merged = await a.synchronize(now: date)
        #expect(merged.attempts.count == 2)
        let reopened = CoachStore(localURL: root.appendingPathComponent("mac"), cloudURL: cloud)
        let persisted = try await reopened.read(now: date)
        #expect(persisted.attempts.count == 2)
        #expect(persisted.headIDs == ["root"])
    }
    @Test func unknownCloudFileDoesNotEraseLocalHistory() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: cloud.appendingPathComponent("broken.json"))
        let store = CoachStore(localURL: root.appendingPathComponent("local"), cloudURL: cloud)
        try await store.append(attempt(id: "a"))
        let result = await store.synchronize(now: date)
        #expect(result.attempts.count == 1)
        #expect(result.incomplete)
    }
    @Test func offlineLessonAndLocalDraftWorkWithoutServer() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let settings = defaults()
        let vm = CoachViewModel(defaults: settings, store: store, now: { date }, generate: { _ in throw URLError(.notConnectedToInternet) })
        await vm.refresh(); await vm.waitForPreparation()
        #expect(vm.lesson?.model == "offline")
        #expect(vm.material?.id == "m")
        vm.answer = "这是我的独立思路"; vm.showHint = true; vm.flushDraft()
        let second = CoachViewModel(defaults: settings, store: store, now: { date }, generate: { _ in Issue.record("Cached lesson must not call model"); return "" })
        await second.refresh()
        #expect(second.answer == vm.answer)
        #expect(second.revealed)
        await second.submit("independent")
        #expect(second.snapshot.attempts.count == 1)
        #expect(second.snapshot.attempts.first?.value.revealed == true)
        #expect(second.lesson == nil)
    }
    @Test func reviewDoesNotBlockExistingTeachingAndStaleApprovalIsRejected() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let draft = plan(["root"], minutes: 5)
        try await store.append(event(.plan(draft)))
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in throw URLError(.notConnectedToInternet) })
        await vm.refresh(); await vm.waitForPreparation()
        #expect(vm.lesson != nil)
        #expect(vm.snapshot.pendingPlans.count == 1)
        let changed = plan(["root"], enabled: false)
        for e in approval(changed, id: "remotePause") { try await store.append(e) }
        await vm.approve(draft)
        #expect(vm.error != nil)
        #expect(vm.snapshot.effectivePreferences?.enabled == false)
        #expect(vm.lesson == nil)
    }
    @Test func pauseDuringGenerationDiscardsObsoleteLesson() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let paused = approval(plan(["root"], enabled: false), id: "pause")
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in
            for e in paused { try await store.append(e) }
            return "{\"title\":\"课\",\"question\":\"为什么\",\"explanation\":\"解释\",\"hint\":\"提示\"}"
        })
        await vm.refresh(); await vm.waitForPreparation()
        #expect(!vm.snapshot.lessons.contains { $0.model != "offline" })
        #expect(vm.lesson == nil)
    }
    @Test func partialNewApprovalDoesNotResurrectOldScope() {
        let missing = event(.approval(.init(planID: "not-downloaded", parents: ["root"])))
        let state = CoachSnapshot(events: base + [missing], now: date)
        #expect(state.hasUnresolvedApproval)
        #expect(state.effectivePreferences == nil)
        #expect(CoachReminderSchedule.reminders(snapshot: state, deviceID: "mac").isEmpty)
    }
    @Test func dailyLimitHidesDuplicateOfflineLessons() {
        let p = plan()
        let l = CoachLesson(id: "other-device-lesson", materialId: "m", planIDs: [p.id],
            content: .init(title: "课", question: "问题", explanation: "解释", hint: "提示"),
            reason: "复习", minutes: 10, provenance: "offline", model: "offline")
        let state = CoachSnapshot(events: base + [event(.lesson(l)), attempt(id: "done")], now: date)
        #expect(state.activeLesson == nil)
        let nextDay = CoachSnapshot(events: state.events, now: date.addingTimeInterval(3600))
        #expect(nextDay.activeLesson == nil)
    }
    @Test func initialTrialDoesNotCreateLongTermApproval() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in Issue.record("Trial should work without model"); return "" })
        vm.setSource(from: makeNotebook())
        vm.sourceNote = "先观察对方威胁"
        await vm.saveSource(startTrial: true)
        #expect(vm.lesson?.model == "offline")
        #expect(vm.snapshot.approvals.isEmpty)
        #expect(vm.snapshot.pendingPlans.count == 1)
        #expect(CoachReminderSchedule.reminders(snapshot: vm.snapshot, deviceID: vm.deviceID).isEmpty)
    }
    @Test func retriedAppendWithLaterClockIsIdempotent() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        try await store.append(attempt(id: "retry"))
        try await store.append(attempt(id: "retry", day: 1))
        let state = try await store.read(now: date)
        #expect(state.attempts.count == 1)
        #expect(state.conflictingEventIDs.isEmpty)
        #expect(state.attempts.first?.event.createdAt == date)
    }
    @Test func reviewedPlanIdentitySurvivesFractionalDateAndReopen() throws {
        var prefs = CoachPreferences()
        prefs.endDate = date.addingTimeInterval(12345.1234567)
        let p = CoachPlan(parents: [], preferences: prefs, materialIDs: ["m"], rationale: "有截止日期")
        let encoded = try CoachEncoding.encode(event(.plan(p)))
        let decoded = try CoachEncoding.decode(CoachEvent.self, encoded)
        guard case .plan(let restored) = decoded.payload else { Issue.record("Missing plan"); return }
        #expect(restored.id == p.id)
        #expect(try CoachEncoding.encode(restored) == CoachEncoding.encode(p))
        let state = CoachSnapshot(events: [event(.material(material)), decoded, event(.approval(.init(planID: p.id, parents: [])))], now: date)
        #expect(state.effectivePreferences?.enabled == true)
    }
    @Test func backgroundGenerationDoesNotBlockPauseOrLocalLesson() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in
            try await Task.sleep(for: .seconds(30)); return ""
        })
        await vm.refresh()
        #expect(!vm.isBusy)
        #expect(vm.lesson != nil)
        await vm.pause(); await vm.waitForPreparation()
        #expect(vm.snapshot.effectivePreferences?.enabled == false)
        #expect(!vm.isPreparing)
    }
    @Test func remoteEarlierLessonDoesNotReplaceCurrentAnswer() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in throw URLError(.notConnectedToInternet) })
        await vm.refresh(); await vm.waitForPreparation()
        let original = try #require(vm.lesson)
        vm.answer = "我正在思考"; vm.saveDraft(); vm.flushDraft()
        let earlier = CoachLesson(id: "remote", materialId: "m", planIDs: original.planIDs, content: original.content,
            reason: "另一设备准备", minutes: 10, provenance: "offline", model: "offline")
        try await store.append(event(.lesson(earlier), day: -1))
        await vm.refresh()
        #expect(vm.lesson?.id == original.id)
        #expect(vm.answer == "我正在思考")
    }
    @Test func unchangedDraftIsNotAppendedOnEveryBackgroundTransition() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in throw URLError(.notConnectedToInternet) })
        await vm.refresh(); await vm.waitForPreparation()
        await vm.syncDraft()
        #expect(vm.snapshot.drafts(for: vm.lesson!.id).isEmpty)
        vm.answer = "先看威胁"
        await vm.syncDraft(); await vm.syncDraft(); await vm.syncDraft()
        #expect(vm.snapshot.drafts(for: vm.lesson!.id).count == 1)
    }
    @Test func expiredScopeProposesReviewWithoutResumingTeaching() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        var p = CoachPreferences(); p.endDate = date.addingTimeInterval(-1)
        let expired = CoachPlan(parents: [], preferences: p, materialIDs: ["m"], rationale: "阶段计划")
        for e in [event(.material(material))] + approval(expired, id: "expired") { try await store.append(e) }
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in Issue.record("Expired scope cannot call model"); return "" })
        await vm.refresh()
        #expect(vm.lesson == nil)
        #expect(vm.snapshot.pendingPlans.count == 1)
        await vm.dismiss(vm.snapshot.pendingPlans[0]); await vm.refresh()
        #expect(vm.snapshot.pendingPlans.isEmpty)
    }
    @Test func remindersRespectDueDayAndDoNotRenewWithoutEngagement() {
        let state = CoachSnapshot(events: base + [attempt(id: "a")], now: date)
        let due = state.dueDate(for: material)
        let reminders = CoachReminderSchedule.reminders(snapshot: state, deviceID: "mac", anchor: date)
        #expect(reminders.allSatisfy { $0.date >= due })
        let muchLater = CoachSnapshot(events: state.events, now: date.addingTimeInterval(30 * 86400))
        #expect(CoachReminderSchedule.reminders(snapshot: muchLater, deviceID: "mac", anchor: date).isEmpty)
    }
    @Test func invalidGoalCannotWriteApprovalOrDisableExistingPlan() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in throw URLError(.notConnectedToInternet) })
        await vm.refresh(); await vm.waitForPreparation()
        vm.reloadPreferences(); vm.preferences.goal = "   "
        await vm.proposeChanges()
        #expect(vm.error != nil)
        var badPrefs = CoachPreferences(); badPrefs.goal = ""
        let bad = CoachPlan(parents: ["root"], preferences: badPrefs, materialIDs: ["m"], rationale: "非法内容")
        await vm.approve(bad)
        #expect(vm.snapshot.headIDs == ["root"])
        for e in approval(bad, id: "bad") { try await store.append(e) }
        await vm.refresh()
        #expect(vm.snapshot.invalidApprovalCount == 1)
        #expect(!vm.snapshot.hasUnresolvedApproval)
        #expect(vm.snapshot.effectivePreferences?.enabled == true)
    }
    @Test func duplicateSubmitIsOneFact() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in throw URLError(.notConnectedToInternet) })
        await vm.refresh(); await vm.waitForPreparation(); vm.answer = "先看威胁"
        async let first: Void = vm.submit("independent")
        async let second: Void = vm.submit("independent")
        _ = await (first, second)
        #expect(vm.snapshot.attempts.count == 1)
        #expect(!vm.snapshot.hasCorrectionConflict)
    }
    @Test func reminderChangeKeepsAnswerAndQuestion() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in throw URLError(.notConnectedToInternet) })
        await vm.refresh(); await vm.waitForPreparation()
        let id = vm.lesson?.id
        vm.answer = "正在思考"; vm.flushDraft()
        vm.reloadPreferences(); vm.preferences.hour = 8
        await vm.proposeChanges(); await vm.approve(vm.snapshot.pendingPlans[0])
        #expect(vm.lesson?.id == id)
        #expect(vm.answer == "正在思考")
    }
    @Test func deadlineReturnsEvenWhenProviderIgnoresCancellation() async throws {
        var providerReply: CheckedContinuation<String, Never>?
        let race = CoachModelRace()
        let task = Task { try await race.run(timeout: .milliseconds(20)) {
            await withCheckedContinuation { providerReply = $0 }
        } }
        do { _ = try await task.value; Issue.record("Expected timeout") } catch { }
        #expect(providerReply != nil)
        // Simulate a late reply from an SDK callback that ignored cancel. It must not resume twice.
        providerReply?.resume(returning: "late reply")
        await Task.yield()
    }
    @Test func nextCalendarDayReviewCountsEvenAfterLateEveningStudy() {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current
        let evening = c.date(bySettingHour: 22, minute: 0, second: 0, of: date)!
        let morning = c.date(bySettingHour: 9, minute: 0, second: 0, of: evening.addingTimeInterval(86400))!
        let a = CoachEvent(id: "evening", deviceID: "mac", createdAt: evening,
            payload: .attempt(.init(lessonId: "l1", materialId: "m", answer: "答", rating: "independent", revealed: false, supersedes: nil)))
        let b = CoachEvent(id: "morning", deviceID: "mac", createdAt: morning,
            payload: .attempt(.init(lessonId: "l2", materialId: "m", answer: "答", rating: "independent", revealed: false, supersedes: nil)))
        let snapshot = CoachSnapshot(events: base + [a, b], now: morning)
        #expect(snapshot.dueDate(for: material) == c.date(byAdding: .day, value: 2, to: c.startOfDay(for: morning)))
    }
    @Test func conflictingReviewDoesNotPoisonLaterIndependentRecall() {
        let state = CoachSnapshot(events: base + [attempt(id: "a"), attempt(id: "b", rating: "again", supersedes: "a"),
            attempt(id: "c", supersedes: "a"), attempt(id: "later", lesson: "l2", day: 2)], now: date.addingTimeInterval(3 * 86400))
        #expect(state.dueDate(for: material) == state.calendar.date(byAdding: .day, value: 4, to: state.calendar.startOfDay(for: date)))
        let normal = CoachSnapshot(events: base + [attempt(id: "a")], now: date)
        let conflictedDrafts = [event(.draft(.init(lessonId: "l", answer: "a", revealed: false)), id: "draft"), event(.draft(.init(lessonId: "l", answer: "b", revealed: false)), id: "draft")]
        let withDraftConflict = CoachSnapshot(events: normal.events + conflictedDrafts, now: date)
        #expect(withDraftConflict.dueDate(for: material) == normal.dueDate(for: material))
        #expect(withDraftConflict.effectivePreferences?.enabled == true)
    }
    @Test func oldUnfinishedDuplicateLessonIsNotReusedAsNextReview() {
        let l = CoachLesson(id: "unused", materialId: "m", planIDs: [plan().id],
            content: .init(title: "旧课", question: "旧问题", explanation: "解释", hint: "提示"),
            reason: "首次学习", minutes: 10, provenance: "offline", model: "offline")
        let state = CoachSnapshot(events: base + [event(.lesson(l)), attempt(id: "done", lesson: "used", day: 0.1)], now: date.addingTimeInterval(2 * 86400))
        #expect(!state.isAvailable(l))
        #expect(state.nextMaterial?.id == "m")
    }
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
    private func makeNotebook() -> ViewModel {
        let database = TestDatabaseBuilder().addFen(1, fen: fen).build()
        let data = SessionData(); data.currentGame2 = [1]; data.currentGameStep = 0
        let session = try! Session(sessionData: data, databaseView: .full(database: database))
        return ViewModel(sessionManager: SessionManager(mainSession: session, database: database), platformService: StubPlatformService())
    }
    #if os(macOS)
    @Test func renderLocalCoach() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CoachStore(localURL: root)
        for e in base { try await store.append(e) }
        let vm = CoachViewModel(defaults: defaults(), store: store, now: { date }, generate: { _ in throw URLError(.notConnectedToInternet) })
        await vm.refresh(); await vm.waitForPreparation(); vm.error = nil
        for width in [760, 390] {
            let view = CoachView(coach: vm, notebook: makeNotebook()).frame(width: CGFloat(width), height: 1120).background(.white).environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: width, height: 1120), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/xiangqi-local-coach-\(width).png"))
            window.orderOut(nil)
            #expect(png.count > 20000)
        }
    }
    #endif
}
