# 贡献指南

感谢你对象棋笔记本项目的关注！我们欢迎各种形式的贡献。

## 如何贡献

### 报告问题

如果你发现了 bug 或有功能建议：

1. 在 [GitHub Issues](https://github.com/gooooloo/XiangqiNotebook/issues) 中搜索是否已有相关问题
2. 如果没有，创建新的 issue，请提供：
   - 清晰的问题描述或功能需求
   - 复现步骤（如果是 bug）
   - 预期行为和实际行为
   - 系统环境（macOS/iOS 版本、设备型号等）
   - 相关截图或日志（如果适用）

### 提交代码

#### 开发环境设置

1. Fork 本仓库
2. 克隆你的 fork：
```bash
git clone https://github.com/YOUR_USERNAME/XiangqiNotebook.git
cd XiangqiNotebook
```

3. 打开 Xcode 项目：
```bash
open XiangqiNotebook.xcodeproj
```

4. 在 Xcode 中设置你的 Development Team ID

#### 开发流程

1. **创建分支**：基于 `main` 分支创建新的功能分支
```bash
git checkout -b feature/your-feature-name
```

2. **编写代码**：遵循下面的代码规范

3. **运行测试**：**必须**在提交前运行测试
```bash
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS'
```

4. **提交更改**：
```bash
git add .
git commit -m "简洁明确的提交信息"
```

5. **推送到 GitHub**：
```bash
git push origin feature/your-feature-name
```

6. **创建 Pull Request**：
   - 在 GitHub 上创建 PR
   - 清楚地描述你的更改
   - 关联相关的 issue（如果有）
   - 确保所有测试通过

## 代码规范

### 架构原则

本项目遵循严格的 MVVM 架构，请务必遵守以下原则：

#### 分层访问规则

- **Views 层**：只能访问 ViewModels，**禁止**直接访问 Models
- **ViewModels 层**：作为中介层，协调 Views、Models 和 Services
- **Models 层**：独立的数据层，使用 ObservableObject
- **Services 层**：通过协议抽象实现平台特定功能

#### DatabaseView 使用规范

**重要**：所有 fenId 相关的数据访问**必须**通过 DatabaseView，**禁止**直接访问 DatabaseData：

```swift
// ✅ 正确做法
if let fenObject = databaseView.getFenObject(fenId) {
    // 使用 fenObject
}

// ❌ 错误做法
if let fenObject = databaseData.fenObjects2[fenId] {
    // 直接访问 DatabaseData
}
```

关键方法：
- `contains(_:)` - 检查 fenId 是否在当前视图范围内
- `getFenObject(_:)` - 获取 FenObject
- `getMoves(from:)` - 获取某个位置的所有着法
- `findMove(from:to:)` - 查找特定着法

### Swift 代码风格

1. **命名规范**：
   - 使用清晰描述性的命名
   - 变量和函数使用驼峰命名法
   - 类型使用大驼峰命名法

2. **SwiftUI 最佳实践**：
   - 使用 `@Published` 标记可观察属性
   - 合理使用 `@State`、`@StateObject`、`@ObservedObject`
   - 保持 View 组件简洁，复杂逻辑放在 ViewModel

3. **平台适配**：
   - 使用条件编译处理平台差异：`#if os(macOS)` / `#if os(iOS)`
   - 平台特定功能通过 PlatformService 抽象

### 测试要求

**严格执行测试驱动开发**：

1. **每次代码修改后必须运行测试**
2. **所有测试必须通过才能提交 PR**
3. 如果添加新功能，请同时添加相应的单元测试
4. 如果修复 bug，建议添加回归测试

```bash
# 运行完整测试套件（推荐）
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS'

# 运行特定测试类
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS' -only-testing:XiangqiNotebookTests/TestClassName
```

## 常见陷阱

请避免以下错误：

1. ❌ **跳过测试** - 永远不要在未运行测试的情况下提交代码
2. ❌ **跨层访问** - Views 不能直接访问 Models
3. ❌ **绕过 DatabaseView** - 不要直接访问 `DatabaseData.fenObjects2`
4. ❌ **忘记范围验证** - 访问 fenId 前必须用 `databaseView.contains(_:)` 检查
5. ❌ **忽略平台差异** - 使用平台特定 API 前要检查兼容性

## Pull Request 检查清单

提交 PR 前，请确认：

- [ ] 代码遵循项目的架构规范
- [ ] 所有测试通过
- [ ] 没有引入新的警告
- [ ] 更新了相关文档（如果需要）
- [ ] PR 描述清晰，说明了更改内容和原因
- [ ] 提交信息简洁明确

## 开发文档

更多详细的开发信息，请参考：

- [CLAUDE.md](CLAUDE.md) - 完整的架构文档和开发指南
- [README.md](README.md) - 项目概览和快速开始

## 行为准则

- 尊重所有贡献者
- 欢迎建设性的讨论和反馈
- 保持友善和专业

## 问题与讨论

- 技术问题：在 [GitHub Issues](https://github.com/gooooloo/XiangqiNotebook/issues) 提问
- 功能讨论：在 [GitHub Discussions](https://github.com/gooooloo/XiangqiNotebook/discussions) 讨论（如果启用）

感谢你的贡献！🎉
