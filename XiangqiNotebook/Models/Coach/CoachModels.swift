import Foundation
import CryptoKit

struct CoachServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Reviewed teaching scope, not a daily timetable. No implicit expiry or approval.
struct CoachPreferences: Codable, Equatable {
    var enabled = true
    var goal = "理解教材中的思路，并能独立运用"
    var timeZone = TimeZone.current.identifier
    var hour = 19
    var dailyMinutes = 10
    var maxDailyCalls = 3
    var reminderDeviceID: String? = nil
    var endDate: Date? = nil
}

struct CoachMaterial: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let locator: String
    let fen: String
    let note: String
    let objective: String
}

struct CoachPlan: Codable, Identifiable, Equatable {
    private struct Body: Codable, Equatable {
        let parents: [String]
        let preferences: CoachPreferences
        let materialIDs: [String]
        let rationale: String
    }
    // Hash the original bytes, never a decoded/re-encoded representation. Schema evolution cannot change identity.
    private let original: Data
    private let body: Body
    let id: String
    var parents: [String] { body.parents }
    var preferences: CoachPreferences { body.preferences }
    var materialIDs: [String] { body.materialIDs }
    var rationale: String { body.rationale }
    var validationError: String? {
        if preferences.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "学习目标不能为空" }
        if !(3...30).contains(preferences.dailyMinutes) || !(1...10).contains(preferences.maxDailyCalls) || !(0...23).contains(preferences.hour) { return "教学时长、模型额度或提醒时间不在允许范围内" }
        if materialIDs.isEmpty && preferences.enabled { return "请至少选择一份教材" }
        return nil
    }

    init(parents: [String], preferences: CoachPreferences, materialIDs: [String], rationale: String) {
        let value = Body(parents: parents.sorted(), preferences: preferences, materialIDs: materialIDs.sorted(), rationale: rationale)
        original = try! CoachEncoding.encode(value)
        body = try! CoachEncoding.decode(Body.self, original)
        id = CoachEncoding.hash(original)
    }
    init(from decoder: Decoder) throws {
        original = try decoder.singleValueContainer().decode(Data.self)
        body = try CoachEncoding.decode(Body.self, original)
        id = CoachEncoding.hash(original)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(original)
    }
}

struct CoachApproval: Codable, Equatable {
    let planID: String
    let parents: [String]
}

struct CoachLesson: Codable, Identifiable, Equatable {
    struct Content: Codable, Equatable {
        let title: String
        let question: String
        let explanation: String
        let hint: String
    }
    let id: String
    let materialId: String
    let planIDs: [String]
    let content: Content
    let reason: String
    let minutes: Int
    let provenance: String
    let model: String
}

struct CoachAttempt: Codable, Equatable {
    let lessonId: String
    let materialId: String
    let answer: String
    let rating: String // Explicit student self-report, never AI ground truth.
    let revealed: Bool
    let supersedes: String? // The event being corrected; original is never overwritten.
    var algorithm: String = "coach-review-v1"
    var questionVersion: String? = nil
}

struct CoachDraft: Codable, Equatable {
    let lessonId: String
    let answer: String
    let revealed: Bool
    var lessonVersion: CoachLesson? = nil
}

struct CoachDiscussion: Codable, Equatable {
    let lessonId: String
    let question: String
    let answer: String
    let provenance: String
}

struct CoachEnrichment: Codable, Equatable {
    let lessonID: String
    let content: CoachLesson.Content
    let model: String
}

enum CoachPayload: Codable, Equatable {
    case material(CoachMaterial)
    case plan(CoachPlan)
    case approval(CoachApproval)
    case dismissed(String)
    case lesson(CoachLesson)
    case trial(CoachLesson)
    case enrichment(CoachEnrichment)
    case attempt(CoachAttempt)
    case draft(CoachDraft)
    case discussion(CoachDiscussion)
    case deferred(String)
    case modelCall(String)
}

struct CoachEvent: Codable, Identifiable, Equatable {
    var schema = 1
    let id: String
    let deviceID: String
    let createdAt: Date
    let payload: CoachPayload

    init(id: String = UUID().uuidString, deviceID: String, createdAt: Date = Date(), payload: CoachPayload) {
        self.id = id; self.deviceID = deviceID; self.createdAt = createdAt; self.payload = payload
    }
}

enum CoachEncoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

/// Pure projection. Disk records are the authority; this object may always be rebuilt.
struct CoachSnapshot {
    let events: [CoachEvent]
    let conflictingEvents: [CoachEvent]
    let materials: [CoachMaterial]
    let plans: [CoachPlan]
    let approvals: [CoachEvent]
    let hasUnresolvedApproval: Bool
    let invalidApprovalCount: Int
    var hasAuthorityConflict: Bool {
        conflictingEvents.contains { switch $0.payload { case .plan, .approval: return true; default: return false } }
    }
    let completedLessonIDs: Set<String>
    private var dueDates: [String: Date] = [:]
    let syncStatus: String
    let incomplete: Bool
    let now: Date
    let conflictingEventIDs: Set<String>

    init(events: [CoachEvent], syncStatus: String = "保存在本机", incomplete: Bool = false, now: Date = Date()) {
        var seen = Set<Data>()
        let unique = events.filter { event in
            guard let bytes = try? CoachEncoding.encode(event) else { return false }
            return seen.insert(bytes).inserted
        }
        let groups = Dictionary(grouping: unique, by: \.id)
        let conflicts = Set(groups.filter { Set($0.value.compactMap { try? CoachEncoding.encode($0) }).count > 1 }.keys)
        self.conflictingEventIDs = conflicts
        self.conflictingEvents = unique.filter { conflicts.contains($0.id) }
        // Duplicate delivery is idempotent; contradictory IDs remain on disk, not selected by time.
        self.events = groups.filter { !conflicts.contains($0.key) }.compactMap { $0.value.first }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        self.materials = self.events.compactMap { if case .material(let m) = $0.payload { return m }; return nil }
            .reduce(into: [CoachMaterial]()) { result, m in if !result.contains(where: { $0.id == m.id }) { result.append(m) } }
        self.plans = self.events.compactMap { if case .plan(let p) = $0.payload { return p }; return nil }
            .reduce(into: [CoachPlan]()) { result, p in if !result.contains(where: { $0.id == p.id }) { result.append(p) } }
        let classified = Self.classifyApprovals(events: self.events, plans: self.plans, materials: self.materials)
        self.approvals = self.events.filter { classified[$0.id] == .valid }
        self.hasUnresolvedApproval = classified.values.contains(.waiting)
        self.invalidApprovalCount = classified.values.filter { $0 == .invalid }.count
        self.syncStatus = syncStatus
        self.incomplete = incomplete || !conflicts.isEmpty
        self.now = now
        self.completedLessonIDs = Set((self.events + self.conflictingEvents).compactMap { if case .attempt(let a) = $0.payload { return a.lessonId }; return nil })
        for material in self.materials { self.dueDates[material.id] = computeDueDate(for: material) }
    }
    private enum ApprovalStatus { case valid, waiting, invalid }
    private static func classifyApprovals(events: [CoachEvent], plans: [CoachPlan], materials: [CoachMaterial]) -> [String: ApprovalStatus] {
        let planIndex = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        let records = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        let materialIDs = Set(materials.map(\.id))
        var statuses: [String: ApprovalStatus] = [:]
        func classify(_ id: String, path: Set<String>) -> ApprovalStatus {
            if let status = statuses[id] { return status }
            guard let event = records[id] else { return .waiting }
            guard !path.contains(id), case .approval(let a) = event.payload else { return .invalid }
            guard let plan = planIndex[a.planID] else { return .waiting }
            guard plan.validationError == nil, Set(plan.parents) == Set(a.parents) else { return .invalid }
            let parents = a.parents.map { classify($0, path: path.union([id])) }
            let status: ApprovalStatus
            if parents.contains(.invalid) { status = .invalid }
            else if parents.contains(.waiting) || !Set(plan.materialIDs).isSubset(of: materialIDs) { status = .waiting }
            else { status = .valid }
            statuses[id] = status
            return status
        }
        for event in events { if case .approval = event.payload { statuses[event.id] = classify(event.id, path: []) } }
        return statuses
    }
    var heads: [CoachEvent] {
        let all = approvals
        let parents = Set(all.flatMap { event -> [String] in
            if case .approval(let a) = event.payload { return a.parents }; return []
        })
        return all.filter { !parents.contains($0.id) }.sorted { $0.id < $1.id }
    }
    var headIDs: [String] { heads.map(\.id) }
    var approvedPlans: [CoachPlan] {
        heads.compactMap { event in
            guard case .approval(let approval) = event.payload else { return nil }
            return plans.first { $0.id == approval.planID }
        }
    }
    var pendingPlans: [CoachPlan] {
        let acted = Set(events.compactMap { event -> String? in
            switch event.payload { case .approval(let a): return a.planID; case .dismissed(let id): return id; default: return nil }
        })
        return plans.filter { !acted.contains($0.id) && Set($0.parents) == Set(headIDs) }
    }
    var stalePlans: [CoachPlan] {
        let acted = Set(events.compactMap { event -> String? in
            switch event.payload { case .approval(let a): return a.planID; case .dismissed(let id): return id; default: return nil }
        })
        return plans.filter { !acted.contains($0.id) && Set($0.parents) != Set(headIDs) }
    }
    var effectivePreferences: CoachPreferences? {
        guard !hasUnresolvedApproval, !hasAuthorityConflict, let first = approvedPlans.first else { return nil }
        var result = first.preferences
        for plan in approvedPlans {
            let p = plan.preferences
            result.enabled = result.enabled && p.enabled && p.goal == result.goal
            result.dailyMinutes = min(result.dailyMinutes, p.dailyMinutes)
            result.maxDailyCalls = min(result.maxDailyCalls, p.maxDailyCalls)
            if result.reminderDeviceID != p.reminderDeviceID || result.hour != p.hour || result.timeZone != p.timeZone {
                result.reminderDeviceID = nil
            }
            if let end = p.endDate { result.endDate = min(result.endDate ?? end, end) }
        }
        if let end = result.endDate, end <= now { result.enabled = false }
        if allowedMaterialIDs.isEmpty { result.enabled = false }
        return result
    }
    var allowedMaterialIDs: Set<String> {
        guard let first = approvedPlans.first else { return [] }
        return approvedPlans.dropFirst().reduce(Set(first.materialIDs)) { $0.intersection($1.materialIDs) }
    }
    var attempts: [(event: CoachEvent, value: CoachAttempt)] {
        events.compactMap { if case .attempt(let a) = $0.payload { return ($0, a) }; return nil }
    }
    var effectiveAttempts: [(event: CoachEvent, value: CoachAttempt)] {
        let all = attempts
        // A correction must reference an existing attempt of the same lesson/material. Invalid chains do not hide facts.
        var accepted = all.filter { $0.value.supersedes == nil }
        var remaining = all.filter { $0.value.supersedes != nil }
        while true {
            let ready = remaining.filter { child in accepted.contains { parent in
                parent.event.id == child.value.supersedes && parent.value.lessonId == child.value.lessonId && parent.value.materialId == child.value.materialId
            } }
            if ready.isEmpty { break }
            accepted += ready
            let ids = Set(ready.map { $0.event.id }); remaining.removeAll { ids.contains($0.event.id) }
        }
        let superseded = Set(accepted.compactMap { $0.value.supersedes })
        return accepted.filter { !superseded.contains($0.event.id) }
    }
    var hasCorrectionConflict: Bool {
        Dictionary(grouping: effectiveAttempts, by: { $0.value.lessonId }).values.contains { $0.count > 1 }
    }
    var hasClockUncertainty: Bool { events.contains { $0.createdAt > now.addingTimeInterval(300) } }
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: effectivePreferences?.timeZone ?? "") ?? .current
        return c
    }
    var todayAttempts: [(event: CoachEvent, value: CoachAttempt)] {
        // Count actual submissions, not later correction dates.
        attempts.filter { $0.value.supersedes == nil && calendar.isDate($0.event.createdAt, inSameDayAs: now) }
    }
    func dueDate(for material: CoachMaterial) -> Date { dueDates[material.id] ?? .distantPast }
    private func computeDueDate(for material: CoachMaterial) -> Date {
        let conflictingAttempts: [(event: CoachEvent, value: CoachAttempt)] = conflictingEvents.compactMap {
            if case .attempt(let a) = $0.payload { return ($0, a) }; return nil
        }
        let source = attempts + conflictingAttempts
        let all = (effectiveAttempts + conflictingAttempts).filter { $0.value.materialId == material.id }
        func originalTime(_ item: (event: CoachEvent, value: CoachAttempt)) -> Date {
            var current = item
            var visited = Set<String>()
            while let parent = current.value.supersedes, visited.insert(parent).inserted,
                  let found = source.first(where: { $0.event.id == parent }) { current = found }
            return current.event.createdAt
        }
        // Uncertain future dates are retained as evidence but cannot postpone reviews or poison other materials.
        let known = all.filter { originalTime($0) <= now.addingTimeInterval(300) }
        let groups = Dictionary(grouping: known, by: { $0.value.lessonId })
        var reviews: [(id: String, time: Date, independent: Bool)] = []
        for (id, items) in groups {
            let time = items.map { originalTime($0) }.min()!
            let first = items[0]
            let independent = items.count == 1 && !conflictingEventIDs.contains(first.event.id) &&
                first.value.rating == "independent" && !first.value.revealed
            reviews.append((id, time, independent))
        }
        reviews.sort { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
        var interval = 0
        var lastConsolidation: Date?
        var due = Date.distantPast
        for review in reviews {
            let t = review.time
            if !review.independent {
                interval = 1; due = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: t))!; lastConsolidation = t
            } else if lastConsolidation == nil || calendar.startOfDay(for: t) > calendar.startOfDay(for: lastConsolidation!) {
                interval = interval == 0 ? 1 : min(30, interval * 2)
                due = calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: t))!; lastConsolidation = t
            }
        }
        return due
    }
    var lessons: [CoachLesson] {
        let enrichments = events.compactMap { event -> CoachEnrichment? in
            if case .enrichment(let e) = event.payload { return e }; return nil
        }
        return events.compactMap { event in
            let lesson: CoachLesson
            switch event.payload { case .lesson(let l), .trial(let l): lesson = l; default: return nil }
            guard let enrichment = enrichments.last(where: { $0.lessonID == lesson.id }) else { return lesson }
            return CoachLesson(id: lesson.id, materialId: lesson.materialId, planIDs: lesson.planIDs,
                content: enrichment.content, reason: lesson.reason, minutes: lesson.minutes,
                provenance: "AI 教练讲解 · 具体着法尚未经引擎核验", model: enrichment.model)
        }
    }
    func isAvailable(_ lesson: CoachLesson) -> Bool {
        guard !completedLessonIDs.contains(lesson.id) else { return false }
        let created = events.first { event in
            switch event.payload { case .lesson(let l), .trial(let l): return l.id == lesson.id; default: return false }
        }?.createdAt ?? .distantPast
        let lastStudy = attempts.filter { $0.value.materialId == lesson.materialId && $0.value.supersedes == nil && $0.event.createdAt <= now.addingTimeInterval(300) }
            .map { $0.event.createdAt }.max()
        if let lastStudy, created <= lastStudy { return false }
        guard effectivePreferences?.enabled == true, todayAttempts.isEmpty else { return false }
        return allowedMaterialIDs.contains(lesson.materialId) &&
            !completedLessonIDs.contains(lesson.id) && !isDeferred(lesson.id) &&
            materials.first(where: { $0.id == lesson.materialId }).map({ dueDate(for: $0) <= now }) == true
    }
    var activeLesson: CoachLesson? {
        if approvals.isEmpty && !hasUnresolvedApproval && conflictingEventIDs.isEmpty {
            return events.reversed().compactMap { event -> CoachLesson? in
                if case .trial(let l) = event.payload, !completedLessonIDs.contains(l.id), !isDeferred(l.id) { return l }
                return nil
            }.first
        }
        return lessons.first { isAvailable($0) }
    }

    func isDeferred(_ lessonID: String) -> Bool {
        events.contains { event in
            if case .deferred(let id) = event.payload { return id == lessonID && calendar.isDate(event.createdAt, inSameDayAs: now) }; return false
        }
    }
    var nextMaterial: CoachMaterial? {
        guard let p = effectivePreferences, p.enabled, todayAttempts.isEmpty else { return nil }
        let deferredMaterials = Set(lessons.filter { isDeferred($0.id) }.map(\.materialId))
        return materials.filter { allowedMaterialIDs.contains($0.id) && !deferredMaterials.contains($0.id) && dueDate(for: $0) <= now }
            .sorted { let a = dueDate(for: $0), b = dueDate(for: $1); return a == b ? $0.id < $1.id : a < b }.first
    }
    func drafts(for lesson: String) -> [CoachEvent] {
        // Keep every device's draft; never replace a local draft automatically with a remote draft.
        events.filter { if case .draft(let d) = $0.payload { return d.lessonId == lesson }; return false }
    }
}

extension CoachPreferences {
    private enum CodingKeys: String, CodingKey {
        case enabled, goal, timeZone, hour, dailyMinutes, maxDailyCalls, reminderDeviceID, endDate
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone) ?? "UTC"
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 19
        dailyMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyMinutes) ?? 10
        maxDailyCalls = try c.decodeIfPresent(Int.self, forKey: .maxDailyCalls) ?? 1
        reminderDeviceID = try c.decodeIfPresent(String.self, forKey: .reminderDeviceID)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
    }
}
