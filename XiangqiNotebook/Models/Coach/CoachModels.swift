import Foundation

struct CoachPreferences: Codable, Equatable {
    var enabled = false
    var goal = "理解教材中的思路，并能独立运用"
    var timeZone = TimeZone.current.identifier
    var hour = 19
    var dailyMinutes = 10
    var maxDailyCalls = 3
}

struct CoachMaterial: Codable, Identifiable {
    let id: String
    let title: String
    let locator: String
    let fen: String
    let note: String
    let objective: String
    var dueAt: String?
    var intervalDays: Int?
}

struct CoachLesson: Codable, Identifiable {
    struct Content: Codable {
        let sourceId: String
        let title: String
        let question: String
        let explanation: String
        let hint: String
    }
    let id: String
    let materialId: String
    let createdAt: String
    let completedAt: String?
    let reason: String
    let content: Content
    let minutes: Int
    let provenance: String
    let model: String
}

struct CoachAttempt: Codable, Identifiable {
    let id: String
    let lessonId: String
    let materialId: String
    let answer: String
    let rating: String
    let revealed: Bool
    let basis: String
    let kind: String
    let createdAt: String
}

struct CoachDiscussion: Codable, Identifiable {
    let id: String
    let lessonId: String
    let question: String
    let answer: String
    let createdAt: String
    let provenance: String
}

struct CoachSnapshot: Decodable {
    struct Capabilities: Decodable { let generator: Bool; let push: Bool }
    let revision: Int
    let preferences: CoachPreferences
    let materials: [CoachMaterial]
    let lessons: [CoachLesson]
    let attempts: [CoachAttempt]
    let activeLesson: CoachLesson?
    let lastError: String?
    let capabilities: Capabilities
    let deliveryStatus: String
    let draft: CoachDraft?
    var discussions: [CoachDiscussion] = []
    var devicesEpoch: Int?
    var preferencesRevision: Int?
}

struct CoachDraft: Codable {
    var lessonId: String
    var answer = ""
    var revealed = false
    var revision: Int?
}
