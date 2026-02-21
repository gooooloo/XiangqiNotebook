# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中工作时提供指导。

## 项目理念

这个项目不追求酷炫的界面交互。相反的，我们追求清晰简明、符合直觉的界面和操作逻辑；追求代码的简明和最少化、易读性和长期可维护性、可扩展性，追求架构的稳定性；追求极客的快捷操作感受。总的定位是：这是一个很高效的学习象棋的工具软件。

## 项目概述

象棋笔记本 (XiangqiNotebook) 是一个使用 SwiftUI 构建的跨平台中国象棋学习与笔记应用，支持 iPhone、iPad 和 macOS。功能包括路径标记、局面评分、书签、注释，以及练习模式，用于棋谱学习和复习。

## 构建与测试命令

这是一个 Xcode 项目。常用开发操作：

- **构建**: `xcodebuild -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook build`
- **运行测试**: `xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS'`
- **运行单个测试**: `xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS' -only-testing:XiangqiNotebookTests/TestClassName/testMethodName`
- **在 iOS 上运行测试**: 使用 `-destination 'platform=iOS Simulator,name=iPhone 15'` 或类似参数

**ARM64 注意事项**: 在 Apple Silicon Mac 上运行测试时，需用 `arch -arm64 /bin/bash -c '...'` 包裹命令以确保正确的架构。

## 架构概述

### MVVM 模式与严格分层
- **Views**: 只访问 ViewModels，不直接访问 Models
- **ViewModels**: 协调 Views、Models 和 Services 之间的交互
- **Models**: 独立的数据层，使用 ObservableObject
- **Services**: 通过协议实现平台抽象

### 核心数据流
```
Views ↔ ViewModels ↔ Session ↔ DatabaseView ↔ Database
           ↕                         ↕
    Platform Services          DatabaseData
           ↕
  Storage Layer (DatabaseStorage/SessionStorage)
           ↕
    iCloudFileCoordinator (singleton)
```

### 核心组件

**DatabaseData 与 SessionData**:
- `DatabaseData`: 核心棋谱数据（局面、着法、棋局、棋书、书签、统计）
  - 由 `Database` 管理业务逻辑
  - 由 `DatabaseStorage` 负责文件读写持久化
- `SessionData`: UI 状态与会话信息（当前棋局、UI 设置、导航状态）
  - 由 `SessionManager` 管理业务逻辑
  - 由 `SessionStorage` 负责文件读写持久化
- DatabaseData 中的核心数据结构：
  - `fenObjects2`: 字典，fenId → FenObject（棋局局面）
  - `moveObjects`: 字典，moveId → Move（着法）
  - `gameObjects`: 字典，完整棋局
  - `bookObjects`: 字典，棋书组织结构
- 数据变更通知通过 `@Published dataChanged: Bool`

**ViewModel.swift**:
- 主要的业务逻辑协调器
- 持有 `@Published private(set) var sessionManager: SessionManager`
- 通过 `sessionManager.currentSession` 访问当前会话
- 管理 UI 状态和用户交互
- 所有数据操作都通过 SessionManager 和 Session 进行

**SessionManager**:
- 管理多个 Session 实例（主会话和练习会话）
- 通过创建带有对应 DatabaseView 的新 Session 来处理筛选范围切换
- 协调不同视图之间的切换（全库、先手开局、后手开局等）
- 工厂方法：`.create(from:database:)` 从 SessionData 创建 SessionManager
- 确保会话切换时的数据一致性

**DatabaseView**（数据筛选层）:
- 根据范围（先手/后手开局、实战棋局、专项练习等）提供 Database 的筛选视图
- 内部封装所有基于 fenId 的筛选逻辑
- 核心方法强制执行严格的筛选语义（起点和终点都必须在范围内）：
  - `getFenObject(_:)`: 如果 fenId 在范围内则返回 FenObject
  - `containsFenId(_:)`: 检查 fenId 是否属于当前范围
  - `moves(from:)`: 返回起点和终点都在范围内的着法
  - `move(from:to:)`: 查找两个端点都在范围内的着法
- 对不需要筛选的数据提供直接透传（fenToId、moveObjects、bookObjects 等）
- 通过工厂方法构造（`.full()`、`.redOpening()`、`.blackOpening()` 等）
- Session 持有并管理当前的 DatabaseView 实例

**存储层**:
- `DatabaseStorage`: 数据库文件读写的静态方法，处理数据库文件的 iCloud 协调
- `SessionStorage`: 会话文件读写的静态方法，处理会话文件的 iCloud 协调
- `iCloudFileCoordinator`: 管理 iCloud 同步的文件协调单例
  - 提供 `coordinatedRead()` 和 `coordinatedWrite()` 实现安全的并发访问
  - 跟踪保存操作以防止自触发的文件变更通知
  - 被 DatabaseStorage 和 SessionStorage 共同使用

**平台服务**:
- `iOSPlatformService.swift` 和 `MacOSPlatformService.swift`
- 抽象平台特定功能（弹窗、文件操作等）

### 文件组织
- `Models/`: 核心数据模型与存储层
  - 数据模型: `FenObject`、`Move`、`GameObject`、`DatabaseData`、`SessionData`
  - 业务逻辑: `MoveRules`、`GameOperations`、`Database`、`SessionManager`
  - 数据视图层: `DatabaseView`（筛选与范围化访问 Database）
  - 存储: `DatabaseStorage`、`SessionStorage`、`iCloudFileCoordinator`
- `Views/`: UI 组件，按平台拆分（iOS/、Mac/、board/）
- `ViewModels/`: 业务逻辑与视图状态管理
- `Services/`: 平台抽象层
- `Resources/`: 棋谱资源（棋盘和棋子图片，PNG/SVG 格式）

### 主要系统功能
- **练习模式**: 自动跟踪练习次数、限步扩展棋局、隐藏路径显示
- **筛选系统**: 先手/后手开局筛选，动态棋盘方向
- **锁定机制**: 步骤锁定防止误操作，支持历史导航
- **路径管理**: 使用 DFS 算法自动生成所有可能路径，路径计数统计
- **书签系统**: 保存重要局面以便快速导航和分类管理
- **数据持久化**: 完整的 Codable 实现用于数据序列化/反序列化
- **iCloud 同步**: 使用 NSFileCoordinator 实现自动文件协调和安全并发访问

### 测试覆盖
测试位于 `XiangqiNotebookTests/`，覆盖以下内容：
- 核心棋局逻辑（MoveRules、GameOperations）
- 数据模型（FenObject、DatabaseData、SessionData）
- 着法验证与棋盘状态管理
- DatabaseView 筛选与范围逻辑
- 存储层操作

### 测试命令速查
```bash
# 运行全部测试（代码修改后必须执行）
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS'

# 运行指定测试类
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS' -only-testing:XiangqiNotebookTests/TestClassName

# 运行单个测试方法
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS' -only-testing:XiangqiNotebookTests/TestClassName/testMethodName
```
