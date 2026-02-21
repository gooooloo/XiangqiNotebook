# 代码规范

- 遵循代码库中现有的 Swift/SwiftUI 模式
- 在 ViewModels 中使用 `@Published` 声明可观察属性
- 严格维护分层：Views → ViewModels → Models → Storage
- 平台服务使用基于协议的抽象
- 棋局逻辑应放在 Models 层，保持平台无关
- 存储层使用静态方法进行文件读写
- 所有 iCloud 文件操作必须通过 `iCloudFileCoordinator.shared`

## 常见错误与注意事项

1. **修改代码后必须运行测试** — 绝不能在未运行并通过相关测试的情况下标记任务完成
2. **Views 禁止直接访问 Models** — 必须通过 ViewModels 中转
3. **禁止绕过 DatabaseView** — 不得直接访问 `DatabaseData.fenObjects2`；必须使用 `DatabaseView.getFenObject(_:)`
4. **不要忘记范围验证** — 访问基于 fenId 的数据前，始终先检查 `databaseView.containsFenId(_:)`
5. **禁止绕过 iCloudFileCoordinator** — 所有 iCloud 文件操作必须使用该协调器
