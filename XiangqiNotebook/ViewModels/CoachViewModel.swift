import SwiftUI

@MainActor
final class CoachViewModel: ObservableObject {
    @Published var endpoint: String
    @Published var token = ""
    @Published var preferences = CoachPreferences()
    private(set) var preferencesRevision = 0
    @Published private(set) var snapshot: CoachSnapshot?
    @Published private(set) var isBusy = false
    @Published var error: String?
    @Published var answer = ""
    @Published var revealed = false
    @Published var showHint = false
    @Published var question = ""
    private var questionID = UUID().uuidString
    @Published var board = BoardViewModel.default
    @Published var sourceTitle = ""
    @Published var sourceLocator = ""
    @Published var sourceNote = ""
    @Published var objective = "理解双方计划与关键着法的目的"
    private var sourceFen = ""
    private var materialID = UUID().uuidString
    private var draftRevision = 0
    private var attemptID = UUID().uuidString
    private let defaults: UserDefaults
    private var connectedEndpoint: String?
    private var connectedToken = ""
    private var registeredToken: String?
    private var connectionFailures = 0
    private var nextConnectionAttempt = Date.distantPast
    private let readCredential: (String) -> String
    private let fetchSnapshot: (CoachAPI) async throws -> CoachSnapshot

    init(defaults: UserDefaults = .standard, initialSnapshot: CoachSnapshot? = nil,
         readCredential: @escaping (String) -> String = { CoachCredential.read(endpoint: $0) },
         fetchSnapshot: @escaping (CoachAPI) async throws -> CoachSnapshot = { try await $0.request() }) {
        self.defaults = defaults
        self.readCredential = readCredential
        self.fetchSnapshot = fetchSnapshot
        self.endpoint = defaults.string(forKey: "coach.endpoint") ?? ""
        self.token = readCredential(endpoint)
        if let initialSnapshot {
            connectedEndpoint = "https://coach.example.test"
            preferences = initialSnapshot.preferences
            apply(initialSnapshot)
        }
    }
    var lesson: CoachLesson? { snapshot?.activeLesson }
    var material: CoachMaterial? { snapshot?.materials.first { $0.id == lesson?.materialId } }
    var isConnected: Bool { connectedEndpoint != nil }
    var canUpload: Bool { isConnected && !sourceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var draftKey: String { "coach.draft.\(connectedEndpoint ?? endpoint)" }

    func setSource(from notebook: ViewModel) {
        let source = notebook.coachCurrentSource()
        materialID = UUID().uuidString
        sourceTitle = source.title; sourceLocator = source.locator
        sourceNote = source.note; sourceFen = source.fen
    }
    func saveDraft() {
        guard let lesson else { return }
        let draft = CoachDraft(lessonId: lesson.id, answer: answer, revealed: revealed || showHint, revision: draftRevision)
        if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: draftKey) }
    }
    private func apply(_ result: CoachSnapshot) {
        let oldID = lesson?.id
        if snapshot == nil || preferences == snapshot?.preferences {
            preferences = result.preferences
            preferencesRevision = result.preferencesRevision ?? result.revision
        }
        if let address = connectedEndpoint, let epoch = result.devicesEpoch {
            let epochKey = "coach.devicesEpoch.\(address)"
            let previous = defaults.object(forKey: epochKey) as? Int
            if (previous != nil && previous != epoch) || (previous == nil && epoch > 0) {
                revokeLocalNotificationConsent()
            }
            defaults.set(epoch, forKey: epochKey)
        }
        snapshot = result
        if oldID != lesson?.id {
            answer = ""; revealed = false; showHint = false; attemptID = UUID().uuidString
            draftRevision = result.draft?.revision ?? 0
            if let data = defaults.data(forKey: draftKey),
               let draft = try? JSONDecoder().decode(CoachDraft.self, from: data), draft.lessonId == lesson?.id {
                answer = draft.answer; revealed = draft.revealed
                draftRevision = draft.revision ?? 0
            }
            if answer.isEmpty, let draft = result.draft, draft.lessonId == lesson?.id {
                answer = draft.answer; revealed = revealed || draft.revealed
                draftRevision = draft.revision ?? 0
            }
            resetBoard()
        }
    }
    func resetBoard() {
        guard let material else { return }
        board = BoardViewModel(fen: material.fen, orientation: "red", isHorizontalFlipped: false,
            showPath: false, showAllNextMoves: false, shouldAnimate: false, currentFenPathGroups: [])
    }
    private func api() throws -> CoachAPI {
        guard let connectedEndpoint else { throw CoachServiceError(message: "请先连接教练服务") }
        return CoachAPI(endpoint: try CoachAPI.endpoint(connectedEndpoint), token: connectedToken)
    }
    private func perform(_ work: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do { try await work() } catch { self.error = error.localizedDescription }
    }
    func connect() async {
        // Capture editable fields before suspension. Automatic retries only use saved credentials.
        await connect(to: endpoint, credential: token)
    }
    private func connect(to address: String, credential: String) async {
        await perform {
            let url = try CoachAPI.endpoint(address)
            let cleanToken = credential.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanToken.count >= 32 else { throw CoachServiceError(message: "请输入服务配置中的完整凭据") }
            let client = CoachAPI(endpoint: url, token: cleanToken)
            let result = try await fetchSnapshot(client)
            try CoachCredential.save(cleanToken, endpoint: address)
            defaults.set(address, forKey: "coach.endpoint")
            connectedEndpoint = address; connectedToken = cleanToken; registeredToken = nil
            snapshot = nil
            preferences = result.preferences
            apply(result)
            connectionFailures = 0; nextConnectionAttempt = .distantPast
        }
    }
    func reconnectIfNeeded(now: Date = Date()) async {
        guard !isConnected, !isBusy, now >= nextConnectionAttempt,
              let address = defaults.string(forKey: "coach.endpoint"), !address.isEmpty else { return }
        let credential = readCredential(address)
        guard !credential.isEmpty else { return }
        await connect(to: address, credential: credential)
        if !isConnected {
            connectionFailures += 1
            nextConnectionAttempt = now.addingTimeInterval(min(300, 30 * pow(2, Double(min(connectionFailures - 1, 4)))))
        }
    }
    func refresh() async {
        guard isConnected else { await reconnectIfNeeded(); return }
        await perform { apply(try await fetchSnapshot(api())) }
    }
    func savePreferences() async {
        struct Update: Encodable { let revision: Int; let preferences: CoachPreferences }
        await perform {
            let result = try await api().post("v1/preferences", Update(revision: preferencesRevision, preferences: preferences))
            apply(result); preferences = result.preferences; preferencesRevision = result.preferencesRevision ?? result.revision
        }
    }
    func reloadPreferences() { if let snapshot { preferences = snapshot.preferences; preferencesRevision = snapshot.preferencesRevision ?? snapshot.revision } }
    func uploadSource() async {
        await perform {
            let source = CoachMaterial(id: materialID, title: sourceTitle, locator: sourceLocator, fen: sourceFen,
                                       note: sourceNote, objective: objective)
            apply(try await api().post("v1/materials", source))
            materialID = UUID().uuidString
        }
    }
    func askCoach() async {
        guard let lesson else { return }
        let input = ["id": questionID, "lessonId": lesson.id, "question": question]
        await perform {
            apply(try await api().post("v1/questions", input))
            question = ""; questionID = UUID().uuidString
        }
    }
    func syncDraft() async {
        struct Progress: Encodable { let lessonId: String; let answer: String; let revealed: Bool; let revision: Int }
        guard let lesson else { return }
        let progress = Progress(lessonId: lesson.id, answer: answer, revealed: revealed || showHint, revision: draftRevision)
        await perform {
            let result = try await api().post("v1/progress", progress)
            apply(result); draftRevision = result.draft?.revision ?? 0; saveDraft()
        }
    }
    func loadRemoteDraft() {
        guard let draft = snapshot?.draft, draft.lessonId == lesson?.id else { return }
        answer = draft.answer; revealed = revealed || draft.revealed
        draftRevision = draft.revision ?? 0
        saveDraft()
    }
    func submit(_ rating: String) async {
        struct Attempt: Encodable { let id: String; let lessonId: String; let answer: String; let rating: String; let revealed: Bool }
        guard let lesson else { return }
        let submission = Attempt(id: attemptID, lessonId: lesson.id, answer: answer, rating: rating, revealed: revealed || showHint)
        await perform {
            let result = try await api().post("v1/attempts", submission)
            defaults.removeObject(forKey: draftKey)
            apply(result)
        }
    }
    func deferLesson() async {
        guard let lesson else { return }
        await perform { apply(try await api().post("v1/defer", ["lessonId": lesson.id])) }
    }
    func clearCoachData() async {
        struct Reset: Encodable { let revision: Int; let confirm = "delete-coach-data" }
        await perform {
            let result = try await api().post("v1/reset", Reset(revision: snapshot?.revision ?? 0))
            defaults.removeObject(forKey: draftKey)
            apply(result); preferences = result.preferences; preferencesRevision = result.preferencesRevision ?? result.revision
            revokeLocalNotificationConsent()
        }
    }
    private func revokeLocalNotificationConsent() {
        registeredToken = nil
        defaults.set(false, forKey: "coach.notificationsEnabled")
        CoachNotifications.shared.deviceToken = nil
        CoachNotifications.shared.status = "教练记录已清除；如需接收后续课程，请重新开启此设备通知"
    }
    func registerDevice(_ token: String) async {
        guard defaults.bool(forKey: "coach.notificationsEnabled"), isConnected, token != registeredToken else { return }
        let id = defaults.string(forKey: "coach.deviceID") ?? UUID().uuidString
        defaults.set(id, forKey: "coach.deviceID")
        await perform {
            apply(try await api().post("v1/devices", ["id": id, "token": token]))
            registeredToken = token
            CoachNotifications.shared.status = "此设备已同步到教练服务；送达情况仍取决于 Apple 推送"
        }
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
