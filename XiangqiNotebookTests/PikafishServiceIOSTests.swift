#if os(iOS)
import Testing
import Foundation
@testable import XiangqiNotebook

struct PikafishServiceIOSTests {

    @Test func testEngineKeyDoesNotCollideWithMacKeys() {
        #expect(PikafishServiceIOS.engineKey.contains("_ios_"))
        #expect(PikafishServiceIOS.engineKey != "Pikafish_dev-20260213-391d491a_d34")
        #expect(PikafishServiceIOS.engineKey != "Pikafish_dev-20260213-391d491a_t3s")
    }

    @Test func testEvaluatePositionReturnsRealBestMove() async {
        let service = PikafishServiceIOS()
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        let result = await service.evaluatePosition(fen: startFen)
        #expect(result != nil)
        #expect((result?.bestMove ?? "").isEmpty == false)
        #expect((result?.depth ?? 0) > 0)
    }
}
#endif
