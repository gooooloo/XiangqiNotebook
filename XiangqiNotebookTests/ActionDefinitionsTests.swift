import Testing
import Foundation
@testable import XiangqiNotebook

@MainActor
struct ActionDefinitionsTests {

    @Test
    func sequenceWithoutLongerMatchExecutesImmediately() {
        var executed = ""
        let ad = ActionDefinitions()
        ad.registerAction(.deleteMove, text: "t", shortcuts: [.sequence(",d")]) {
            executed = "d"
        }
        _ = ad.handleKeyDown(character: ",")
        _ = ad.handleKeyDown(character: "d")
        #expect(executed == "d")
        #expect(ad.isInSequenceMode == false)
    }

    @Test
    func ambiguousShortMatchYieldsToLongerInput() {
        var executed = ""
        let ad = ActionDefinitions()
        ad.registerAction(.copyFEN, text: "short", shortcuts: [.sequence(",f")]) {
            executed = "f"
        }
        ad.registerAction(.browseGames, text: "long", shortcuts: [.sequence(",fff")]) {
            executed = "fff"
        }
        _ = ad.handleKeyDown(character: ",")
        _ = ad.handleKeyDown(character: "f")
        // Short match registered as pending; not yet executed
        #expect(executed == "")
        _ = ad.handleKeyDown(character: "f")
        _ = ad.handleKeyDown(character: "f")
        #expect(executed == "fff")
        #expect(ad.isInSequenceMode == false)
    }

    @Test
    func ambiguousShortMatchExecutesAfterTimeout() {
        var executed = ""
        let ad = ActionDefinitions()
        ad.registerAction(.copyFEN, text: "short", shortcuts: [.sequence(",f")]) {
            executed = "f"
        }
        ad.registerAction(.browseGames, text: "long", shortcuts: [.sequence(",fff")]) {
            executed = "fff"
        }
        _ = ad.handleKeyDown(character: ",")
        _ = ad.handleKeyDown(character: "f")
        #expect(executed == "")
        // Drive RunLoop past ambiguous timeout (300ms) so the timer fires
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        #expect(executed == "f")
        #expect(ad.isInSequenceMode == false)
    }

    @Test
    func longerSequenceUnreachableWithoutAmbiguityHandling_isNowReachable() {
        // Regression guard: previously ,fix was unreachable because ,f executed first.
        var executed = ""
        let ad = ActionDefinitions()
        ad.registerAction(.copyFEN, text: "short", shortcuts: [.sequence(",f")]) {
            executed = "f"
        }
        ad.registerAction(.fix, text: "long", shortcuts: [.sequence(",fix")]) {
            executed = "fix"
        }
        _ = ad.handleKeyDown(character: ",")
        _ = ad.handleKeyDown(character: "f")
        _ = ad.handleKeyDown(character: "i")
        _ = ad.handleKeyDown(character: "x")
        #expect(executed == "fix")
    }

    @Test
    func nonMatchingFollowupExecutesPendingShortMatch() {
        // Typing ",f" then a non-matching character should execute copyFEN
        // (no longer prefix matches ",fX").
        var executed = ""
        let ad = ActionDefinitions()
        ad.registerAction(.copyFEN, text: "short", shortcuts: [.sequence(",f")]) {
            executed = "f"
        }
        ad.registerAction(.browseGames, text: "long", shortcuts: [.sequence(",fff")]) {
            executed = "fff"
        }
        _ = ad.handleKeyDown(character: ",")
        _ = ad.handleKeyDown(character: "f")
        _ = ad.handleKeyDown(character: "z")  // not a continuation of ,f
        #expect(executed == "f")
    }
}
