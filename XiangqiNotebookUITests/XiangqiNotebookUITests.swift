import XCTest

/// UITests target 的烟雾测试。
///
/// 背景（issue #169）：此前 UITests target 内没有任何源文件，导致测试 bundle
/// 编译不出可执行文件，运行时报「未能找到其可执行文件的位置」而整体失败。
/// 这里提供一个最小的启动测试，既给 bundle 提供可执行文件、修复加载错误，
/// 也对「app 能正常启动到前台」做基本验证。
final class XiangqiNotebookUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 注意：UI 测试会接管 app 生命周期，运行时不应有同一 app 的其它实例在跑
    /// （否则 XCUIApplication.launch() 会因无法终止外部实例而失败）。
    @MainActor
    func testAppLaunchesToForeground() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "app 应在 15 秒内启动到前台"
        )
    }
}
