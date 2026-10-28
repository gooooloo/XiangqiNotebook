import SwiftUI

@MainActor
final class CoachViewModel: ObservableObject {
    static let shared = CoachViewModel()
    @Published var preferences = CoachPreferences()
    @Published private(set) var snapshot = CoachSnapshot(events: [])
    @Published private(set) var isBusy = false
    @Published private(set) var isPreparing = false
    @Published var error: String?
    @Published var answer = ""
    @Published var revealed = false
    @Published var showHint = false
    @Published var question = ""
    @Published var board = BoardViewModel.default
    @Published var sourceTitle = ""
    @Published var sourceLocator = ""
    @Published var sourceNote = ""
    @Published var objective = "理解双方计划与关键着法的目的"
    @Published var selectedMaterials: Set<String> = []
    @Published var correctionTarget: String?
    private var sourceFen = ""
    private var attemptID = UUID().uuidString
    private let store: CoachStore
    private let defaults: UserDefaults
    let deviceID: String
    private let generate: (String) async throws -> String
    private let now: () -> Date
    private let modelTimeout: Duration
    private var runtime: Task<Void, Never>?
    private var editorParents: [String] = []
    private var preparedOnce = false
    private var modelTask: Task<String, Error>?
    private var modelReserved = false
    private var cancellationEpoch = 0
    private var pauseInProgress = false
    private var isRefreshing = false
    private var actionWaiters: [CheckedContinuation<Void, Never>] = []
    private var pinnedLesson: CoachLesson?
    private var draftTask: Task<Void, Never>?
    private var lastSharedDraft: CoachDraft?
    private var preparationTask: Task<Void, Never>?


    init(defaults: UserDefaults = .standard, store: CoachStore = .shared,
         now: @escaping () -> Date = Date.init, modelTimeout: Duration = .seconds(45),
         generate: @escaping (String) async throws -> String = CoachGenerator.respond) {
        self.defaults = defaults; self.store = store; self.now = now; self.generate = generate; self.modelTimeout = modelTimeout
        deviceID = defaults.string(forKey: "coach.localDeviceID") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "coach.localDeviceID")
    }
    var lesson: CoachLesson? {
        if let pinned = pinnedLesson, snapshot.isAvailable(pinned) { return pinned }
        return snapshot.activeLesson
    }
    var material: CoachMaterial? { snapshot.materials.first { $0.id == lesson?.materialId } }
    var canSaveSource: Bool { !sourceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sourceTitle.isEmpty }
    var draftKey: String { "coach.localDraft.\(lesson?.id ?? "none")" }
    var discussions: [(CoachEvent, CoachDiscussion)] {
        snapshot.events.compactMap { if case .discussion(let d) = $0.payload, d.lessonId == lesson?.id { return ($0, d) }; return nil }
    }
    func start() {
        guard runtime == nil, !AIKeychain.isRunningInTests else { return }
        runtime = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
    private func apply(_ value: CoachSnapshot) {
        let oldID = lesson?.id
        let hadInput = !answer.isEmpty || revealed || showHint
        if hadInput { flushDraft() }
        // Concurrent refresh/user operations can return snapshots out of order. Immutable facts only accumulate.
        snapshot = CoachSnapshot(events: snapshot.events + snapshot.conflictingEvents + value.events + value.conflictingEvents,
            syncStatus: value.syncStatus, incomplete: value.incomplete, now: now())
        if !preparedOnce { reloadPreferences(); preparedOnce = true }
        if oldID != lesson?.id {
            draftTask?.cancel()
            answer = ""; revealed = false; showHint = false; question = ""; correctionTarget = nil
            attemptID = UUID().uuidString
            if let data = defaults.data(forKey: draftKey), let draft = try? CoachEncoding.decode(CoachDraft.self, data) {
                answer = draft.answer; revealed = draft.revealed
                pinnedLesson = draft.lessonVersion
            }
            resetBoard()
        }
    }
    private func append(_ payload: CoachPayload, id: String = UUID().uuidString) async throws {
        try await store.append(CoachEvent(id: id, deviceID: deviceID, createdAt: now(), payload: payload))
        apply(try await store.read(now: now()))
    }
    private func perform(_ work: () async throws -> Void) async {
        if isBusy { await withCheckedContinuation { actionWaiters.append($0) } }
        else { isBusy = true }
        error = nil
        defer {
            if actionWaiters.isEmpty { isBusy = false }
            else { actionWaiters.removeFirst().resume() }
        }
        do { try await work() } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
    }
    func refresh() async {
        guard !isRefreshing, !isBusy else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            apply(try await store.read(now: now()))
            apply(await store.synchronize(now: now()))
            await updateNotifications()
            if !isBusy { try await proposeExpiredFollowup(); try await prepareNextLesson() }
        } catch { self.error = error.localizedDescription }
    }
    private func proposeExpiredFollowup() async throws {
        guard snapshot.approvedPlans.count == 1, let old = snapshot.approvedPlans.first,
              old.preferences.enabled, let end = old.preferences.endDate, end <= now(),
              !snapshot.hasUnresolvedApproval,
              !snapshot.plans.contains(where: { Set($0.parents) == Set(snapshot.headIDs) }) else { return }
        var p = old.preferences
        p.endDate = snapshot.calendar.date(byAdding: .day, value: 15, to: snapshot.calendar.startOfDay(for: now()))
        let proposal = CoachPlan(parents: snapshot.headIDs, preferences: p, materialIDs: old.materialIDs,
            rationale: "这一阶段已经到期。我建议保持目标和教材，继续两周巩固与学习。请 review；确认前不会恢复教学或提醒。")
        try await append(.plan(proposal))
    }
    func rebase(_ old: CoachPlan) async {
        await perform {
            apply(await store.synchronize(now: now()))
            let proposal = CoachPlan(parents: snapshot.headIDs, preferences: old.preferences,
                materialIDs: old.materialIDs, rationale: "这份建议基于旧计划。已重新提出，请比较当前范围后 review，尚未生效。")
            try await append(.plan(proposal)); try await append(.dismissed(old.id))
        }
    }
    func reloadPreferences() {
        preferences = snapshot.effectivePreferences ?? CoachPreferences()
        selectedMaterials = snapshot.approvedPlans.isEmpty ? Set(snapshot.materials.map(\.id)) : snapshot.allowedMaterialIDs
        editorParents = snapshot.headIDs
    }
    func setSource(from notebook: ViewModel) {
        let source = notebook.coachCurrentSource()
        sourceTitle = source.title; sourceLocator = source.locator; sourceNote = source.note; sourceFen = source.fen
    }
    func saveSource(startTrial: Bool = false) async {
        await perform {
            guard canSaveSource else { return }
            apply(await store.synchronize(now: now()))
            let material = CoachMaterial(id: UUID().uuidString, title: sourceTitle, locator: sourceLocator,
                                         fen: sourceFen, note: sourceNote, objective: objective)
            try await append(.material(material))
            reloadPreferences()
            selectedMaterials.insert(material.id)
            try await propose(rationale: snapshot.approvedPlans.isEmpty
                ? "先从这份笔记了解你的思路：解释双方计划、完成一题，再根据表现安排复习。每天一节短课，后续由我带你推进。"
                : "把这份新材料加入学习范围；原来的学习记录和复习安排继续保留。")
            if startTrial && snapshot.approvals.isEmpty && !snapshot.hasUnresolvedApproval {
                let trial = CoachLesson(id: UUID().uuidString, materialId: material.id, planIDs: [],
                    content: .init(title: material.title + " · 先试一小节", question: "先说说你看到了什么：双方各有什么威胁？原笔记中哪一句你还不理解？",
                        explanation: "先对照原笔记，试着用自己的话复述：\n" + material.note, hint: "先观察对方下一步能做什么，再看自己的子力。"),
                    reason: "这次只试学你选定的笔记；没有批准长期计划，也不会自动联系你。", minutes: 3,
                    provenance: "本地诊断练习 · 尚未判题", model: "offline")
                try await append(.trial(trial))
            }
        }
    }
    private func propose(rationale: String) async throws {
        guard !selectedMaterials.isEmpty else { throw CoachServiceError(message: "请先选一份教材笔记") }
        guard Set(editorParents) == Set(snapshot.headIDs) else {
            throw CoachServiceError(message: "另一设备更新了计划，请先重新载入安排，再提交修改。")
        }
        let plan = CoachPlan(parents: editorParents.sorted(), preferences: preferences,
                             materialIDs: selectedMaterials.sorted(), rationale: rationale)
        if let message = plan.validationError { throw CoachServiceError(message: message) }
        try await append(.plan(plan))
    }
    func proposeChanges() async {
        await perform {
            apply(await store.synchronize(now: now()))
            try await propose(rationale: "按你的意见调整学习范围和节奏。请 review 下列完整安排，确认后才生效。")
        }
    }
    func approve(_ plan: CoachPlan) async {
        await perform {
            if let message = plan.validationError { throw CoachServiceError(message: message) }
            apply(await store.synchronize(now: now()))
            guard !snapshot.hasUnresolvedApproval, snapshot.plans.contains(where: { $0.id == plan.id }), Set(plan.parents) == Set(snapshot.headIDs) else {
                throw CoachServiceError(message: "计划依据已变化，请重新 review 当前版本。")
            }
            try await append(.approval(CoachApproval(planID: plan.id, parents: plan.parents)))
            reloadPreferences()
            await updateNotifications()
            try await prepareNextLesson()
        }
    }
    func resolve(using plan: CoachPlan) async {
        // A new exact revision acknowledges all observed heads. No old branch is overwritten.
        await perform {
            let reviewedHeads = snapshot.headIDs
            apply(await store.synchronize(now: now()))
            guard !snapshot.hasUnresolvedApproval, Set(reviewedHeads) == Set(snapshot.headIDs), snapshot.approvedPlans.contains(where: { $0.id == plan.id }) else {
                throw CoachServiceError(message: "计划分支有新变化，请重新选择。")
            }
            let resolved = CoachPlan(parents: reviewedHeads, preferences: plan.preferences,
                                     materialIDs: plan.materialIDs, rationale: "由你选择此安排，合并已看到的计划分支；学习历史保留。")
            try await append(.plan(resolved))
            try await append(.approval(CoachApproval(planID: resolved.id, parents: resolved.parents)))
            reloadPreferences(); await updateNotifications(); try await prepareNextLesson()
        }
    }
    func dismiss(_ plan: CoachPlan) async { await perform { try await append(.dismissed(plan.id)) } }
    func cancelModel() { cancellationEpoch += 1; preparationTask?.cancel(); modelTask?.cancel() }
    func waitForPreparation() async { await preparationTask?.value }
    func pause() async {
        guard !pauseInProgress else { return }
        pauseInProgress = true
        defer { pauseInProgress = false }
        cancelModel()
        do {
            apply(await store.synchronize(now: now()))
            guard var p = snapshot.effectivePreferences else { return }
            p.enabled = false
            let plan = CoachPlan(parents: snapshot.headIDs, preferences: p, materialIDs: snapshot.allowedMaterialIDs.sorted(), rationale: "你暂停了教练；保留学习历史，停止教学和提醒。")
            try await append(.plan(plan))
            try await append(.approval(CoachApproval(planID: plan.id, parents: plan.parents)))
            reloadPreferences(); await updateNotifications()
        } catch { self.error = error.localizedDescription }
    }
    private func requestModel(_ prompt: String) async throws -> String {
        try Task.checkCancellation()
        guard let p = snapshot.effectivePreferences, p.enabled else { throw CoachServiceError(message: "请先确认教学范围") }
        let count = snapshot.events.filter { e in
            if case .modelCall = e.payload { return snapshot.calendar.isDate(e.createdAt, inSameDayAs: now()) }; return false
        }.count
        guard count < p.maxDailyCalls else { throw CoachServiceError(message: "今天的模型请求额度已用完，可以继续已有课程。") }
        guard !modelReserved else { throw CoachServiceError(message: "教练正在备课，请稍后继续追问。") }
        modelReserved = true
        let epoch = cancellationEpoch
        defer { modelTask = nil; modelReserved = false }
        try await append(.modelCall("App 已配置模型；含失败和重试"))
        guard epoch == cancellationEpoch else { throw CancellationError() }
        try Task.checkCancellation()
        let generator = generate
        let timeout = modelTimeout
        let task = Task { try await CoachModelRace().run(timeout: timeout) { try await generator(prompt) } }
        modelTask = task
        return try await task.value
    }
    private func prepareNextLesson() async throws {
        guard !pauseInProgress, !isPreparing, lesson == nil, let m = snapshot.nextMaterial, let p = snapshot.effectivePreferences else { return }
        isPreparing = true
        var handedOff = false
        defer { if !handedOff { isPreparing = false } }
        let heads = snapshot.headIDs
        let planIDs = snapshot.approvedPlans.map(\.id).sorted()
        let history = snapshot.effectiveAttempts.filter { $0.value.materialId == m.id }.suffix(5)
            .map { "\($0.value.rating)：\($0.value.answer.prefix(600))" }.joined(separator: "\n")
        let content = CoachLesson.Content(title: m.title + " · 读懂思路",
            question: "先看这个局面：双方各有什么打算？请用自己的话解释笔记中的一个关键理由。",
            explanation: "原笔记（尚未由教练重新核验）：\n" + m.note,
            hint: "从对方的威胁、自己的子力位置和下一步目标依次想起。")
        let lastStudy = snapshot.attempts.map { $0.event.createdAt }.max()
        let returning = lastStudy.map { now().timeIntervalSince($0) > 3 * 86400 } ?? false
        let lesson = CoachLesson(id: UUID().uuidString, materialId: m.id, planIDs: planIDs, content: content,
            reason: returning ? "我们先用一节短课找回状态，不补堆积的欠课。" : (history.isEmpty ? "今天先读懂这份笔记，再检查你的理解。" : "这部分到了复习时间，先独立想一想。"),
            minutes: returning ? min(5, p.dailyMinutes) : p.dailyMinutes,
            provenance: "本地笔记练习 · 未自动判题", model: "offline")
        // Publish a usable local lesson BEFORE the network request. Enrichment never changes its identity.
        try await append(.lesson(lesson))
        handedOff = true
        preparationTask = Task {
        defer { isPreparing = false }
        do {
            let enriched = try CoachGenerator.parseLesson(await requestModel(CoachGenerator.lessonPrompt(material: m, goal: p.goal, history: history)))
            apply(await store.synchronize(now: now()))
            guard !pauseInProgress, snapshot.headIDs == heads, snapshot.isAvailable(lesson), self.lesson?.id == lesson.id else { return }
            try await append(.enrichment(CoachEnrichment(lessonID: lesson.id, content: enriched, model: AIConfig.load().model)))
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && !pauseInProgress && snapshot.effectivePreferences?.enabled == true { self.error = error.localizedDescription + " 可以继续本地笔记练习。" }
        }
    }
    }
    func saveDraft() {
        guard let lesson else { return }
        pinnedLesson = lesson
        let d = CoachDraft(lessonId: lesson.id, answer: answer, revealed: revealed || showHint, lessonVersion: lesson)
        let key = draftKey
        draftTask?.cancel()
        draftTask = Task { [defaults] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if let data = try? CoachEncoding.encode(d) { defaults.set(data, forKey: key) }
        }
    }
    func flushDraft() {
        draftTask?.cancel()
        guard let lesson else { return }
        pinnedLesson = lesson
        let d = CoachDraft(lessonId: lesson.id, answer: answer, revealed: revealed || showHint, lessonVersion: lesson)
        if let data = try? CoachEncoding.encode(d) { defaults.set(data, forKey: draftKey) }
    }
    func syncDraft() async {
        flushDraft()
        guard let lesson, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let draft = CoachDraft(lessonId: lesson.id, answer: answer, revealed: revealed || showHint, lessonVersion: lesson)
        await perform {
            guard draft != lastSharedDraft else { return }
            let previous = snapshot.drafts(for: lesson.id).last { $0.deviceID == deviceID }
            if let previous, case .draft(let d) = previous.payload, d == draft { lastSharedDraft = draft; return }
            try await append(.draft(draft)); lastSharedDraft = draft
            apply(await store.synchronize(now: now()))
        }
    }
    func loadDraft(_ event: CoachEvent) {
        guard case .draft(let d) = event.payload, d.lessonId == lesson?.id else { return }
        answer = d.answer; revealed = revealed || d.revealed; pinnedLesson = d.lessonVersion; saveDraft()
    }
    func submit(_ rating: String) async {
        guard let lesson, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let attempt = CoachAttempt(lessonId: lesson.id, materialId: lesson.materialId, answer: answer,
                                   rating: rating, revealed: revealed || showHint, supersedes: nil, questionVersion: CoachEncoding.hash(try! CoachEncoding.encode(lesson.content)))
        let key = draftKey
        let submissionID = attemptID
        await perform {
            guard !snapshot.completedLessonIDs.contains(lesson.id) else { return }
            try await append(.attempt(attempt), id: submissionID)
            defaults.removeObject(forKey: key)
            // Repeated difficulty triggers a concrete proposal, not an unapproved scope change.
            if snapshot.effectiveAttempts.suffix(3).count == 3,
               snapshot.effectiveAttempts.suffix(3).allSatisfy({ $0.value.rating == "again" }), snapshot.pendingPlans.isEmpty {
                reloadPreferences()
                preferences.dailyMinutes = max(3, preferences.dailyMinutes - 2)
                try await propose(rationale: "最近三次都觉得需要再学。我建议缩短每课时长，把精力放在解释和重复练习上。原安排在你决定前继续。")
            }
            apply(await store.synchronize(now: now())); await updateNotifications()
        }
    }
    func correct(_ event: CoachEvent, rating: String) async {
        guard case .attempt(let old) = event.payload else { return }
        await perform {
            try await append(.attempt(CoachAttempt(lessonId: old.lessonId, materialId: old.materialId,
                answer: old.answer, rating: rating, revealed: old.revealed, supersedes: event.id, questionVersion: old.questionVersion)))
        }
    }
    func askCoach() async {
        guard let lesson, let material, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let input = question
        let heads = snapshot.headIDs
        await perform {
            let context = discussions.suffix(4).map { "学生：\($0.1.question)\n教练：\($0.1.answer)" }.joined(separator: "\n")
            let response = try await requestModel("教材：\(material.title)\n位置：\(material.locator)\nFEN：\(material.fen)\n原笔记：\(material.note)\n本课：\(lesson.content.explanation)\n学生思路：\(answer)\n此前讨论：\(context)\n请回答并给一个后续理解检查问题：\(input)")
            apply(await store.synchronize(now: now()))
            guard !pauseInProgress, snapshot.headIDs == heads, snapshot.effectivePreferences?.enabled == true else { return }
            try await append(.discussion(CoachDiscussion(lessonId: lesson.id, question: input, answer: response, provenance: "AI 解释 · 未经引擎核验")))
            question = ""
        }
    }
    func deferLesson() async {
        guard let lesson else { return }
        await perform { try await append(.deferred(lesson.id)); await updateNotifications() }
    }
    func updateNotifications() async {
        guard !AIKeychain.isRunningInTests else { return }
        await CoachNotifications.shared.schedule(snapshot: snapshot, deviceID: deviceID)
    }
    func resetBoard() {
        guard let material else { return }
        board = BoardViewModel(fen: material.fen, orientation: "red", isHorizontalFlipped: false,
            showPath: false, showAllNextMoves: false, shouldAnimate: false, currentFenPathGroups: [])
    }
}
extension ViewModel {
    func coachCurrentSource() -> CoachMaterial {
        let session = sessionManager.currentSession
        let db = session.databaseView
        let game = session.sessionData.specificGameId.flatMap { db.getGameObjectUnfiltered($0) }
        let book = session.sessionData.specificBookId.flatMap { db.getBookObjectUnfiltered($0) }
        let title = game?.displayTitle ?? "当前局面笔记"
        let locator = [book?.name, game?.displayTitle, "局面节点 \(currentFenId)", "第 \(currentGameStepDisplay) 手"].compactMap { $0 }.joined(separator: " / ")
        let moves = db.moves(from: currentFenId).prefix(6).map { move in
            let name = db.formatMove(move, isHorizontalFlipped: false)
            return name + (move.comment.map { "：" + $0 } ?? "")
        }
        var note = currentCombinedComment ?? ""
        if !moves.isEmpty { note += "\n笔记库记录的后续着法（未重新核验）：\n" + moves.joined(separator: "\n") }
        return CoachMaterial(id: UUID().uuidString, title: title, locator: locator, fen: currentFen,
            note: note, objective: "理解双方计划与关键着法的目的")
    }
}
