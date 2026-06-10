# 象棋笔记本（XiangqiNotebook）全面代码评审报告

> 评审日期：2026-06-10
> 评审方式：人工精读核心业务中枢（ViewModel、Session、SessionManager、Database、DatabaseView、Move、FenObject、GameOperations、ActionDefinitions、BoardViewModel 等约 8000 行），并行 5 个专项审查（Views 层 44 个文件全读、存储与并发、Services 与网络、测试套件、象棋领域逻辑），关键结论均做了代码级交叉验证。
> 基线状态：单元测试全部通过；UITests target 可执行文件缺失无法加载（本身已损坏）。

**总体评价**：这是一个架构意图清晰的项目——DatabaseView 过滤抽象、严格分层规则、Codable 兼容性处理（如 `reviewItems` 的 `decodeIfPresent` 范例）、棋子动画的 ID 复用设计都体现了良好的设计品味，近期的并发修复（#126/#130）方向也正确。但存在三类系统性风险：

1. "异步标记脏/版本号"体系有根本性竞态，iCloud 同步的数据安全防线有多处可被击穿；
2. 若干用户可直接触发的崩溃和静默失败；
3. Session/ViewModel 两个巨型类承担过多职责，加上核心交互路径零测试覆盖，回归风险持续累积。

---

## 一、P0：数据丢失风险（最优先处理）

### 1.1 解码失败 → 静默空库 → 可无确认覆盖 iCloud 真实数据 【CRITICAL】

`Database.swift:32-41` + `ViewModel.swift:1025-1040`。启动时只要 iCloud 文件未下载完、JSON 损坏、或新老版本 schema 不兼容（`DatabaseData.swift:42-51` 多数字段是必需 `decode`），`loadDatabaseFromDefault()` 返回 nil 就**静默创建空库**。此时若按下保存，由于 `loadDataVersionFromDefault()` 同样读不出版本号，`saveToDefault()` 走 else 分支**不弹任何确认**，空库直接覆盖云端真实数据。

**修复**：区分"文件不存在"与"读取/解码失败"；解码失败进入只读报错状态；写入前无法确认远端版本时强制弹确认；覆盖前自动留备份。

### 1.2 没有任何自动保存 【HIGH】

`ViewModel.swift:157-165` 的 `willTerminateNotification` 只停引擎进程，不保存数据；macOS 无 `applicationShouldTerminate` 拦截，iOS 无 `scenePhase` 后台保存。Cmd+Q、崩溃、iOS 被系统杀掉，所有未按 `w` 的修改（包括跑了几小时的引擎评估结果）静默丢失。

**修复**：退出/进后台时保存脏数据，或至少弹"有未保存修改"确认。

### 1.3 `markDirty()` 竞态破坏整个版本仲裁体系 【HIGH】

`Database.swift:59-69`：`guard !isDirty` 同步检查，但 `isDirty = true; dataVersion += 1` 在 `DispatchQueue.main.async` 里执行。同一个 runloop 内一次走子会触发 `ensureFenId` + `ensureMove` 两次 `markDirty`，两次都通过 guard → 版本号 +2。后果链：

- `currentCheckpointDataVersion = dataVersion - 1`（`Session.swift:371`）的假设被打破 → `checkDataVersion` 弹虚假的"存档文件版本不对"，引导用户 reload 丢弃本地修改；
- `reloadFromRemote` 的 `remoteVersion <= currentVersion` guard（`ViewModel.swift:1116`）因本地版本虚高而**静默忽略其他设备的真实更新**，下次保存反向覆盖——last-writer-wins 数据丢失；
- mutation 后同一 runloop 内调用 `save()` 会因 `guard isDirty`（`Database.swift:83`）静默跳过。

**修复**：`markDirty` 要求主线程调用，guard 与自增放进同一个同步临界区。一行级别的修复，收益极大。

### 1.4 iCloud 冲突处理：无脑覆盖 + 永久删除其他版本 【HIGH】

`iCloudFileCoordinator.swift:85-105`：注释说"选择最新版本"，实际从不比较 `modificationDate`，凡是 gained 的冲突版本（可能更旧）直接 `replaceItem` 覆盖当前文件，再 `removeOtherVersionsOfItem` 把被覆盖的版本永久删除，且未经 coordinated write、强制解包 `presentedItemURL!`、未设置 `isResolved`。

另外：强制保存/恢复备份写出的 `dataVersion` 可能低于远端（`Database.swift:225-245` 直接采用备份的版本号），同样触发 1.3 的反向覆盖链。**修复**：恢复/强保前读远端版本，写出 `max(local, remote) + 1`。

### 1.5 其他数据安全缺口

- 保存后 1 秒的自我通知抑制窗口会**永久吞掉**期间到达的真实远程变更（`iCloudFileCoordinator.swift:68-73, 199-204`），无补偿机制；`resetFileChangeFlag` 与新通知存在丢事件竞态。
- 引擎分数文件整文件覆盖、跨设备不合并、iCloud 占位文件未触发下载（`EngineScoreStorage.swift:31-33`）——本机保存会抹掉另一台设备的评估结果。分数是 append-only 字典，按 fenId 合并是安全且简单的。
- `saveToDefault` 版本检查与写入之间隔着用户弹窗，存在 TOCTOU 窗口。
- 备份/恢复失败只 `print` 不告知用户（`ViewModel.swift:1204, 1233`）。

---

## 二、P0：崩溃类 bug

| # | 位置 | 触发方式 |
|---|------|---------|
| 1 | `MacPathEditorView.swift:203-209, 100-110`（已验证） | 路径编辑器中先选中后面的组/路径，再删除前面的 → stale index，`pathGroups[selectedGroupIndex]` 越界崩溃。iPad 也使用此视图 |
| 2 | `BoardUtils.swift:15, 26` + `Move.swift:146-155` | 导入 PGN 的 `[FEN]` 头未经任何校验入库：空串或某行超 9 列 → 解析/显示着法列表时越界崩溃。**用户可用一份畸形 PGN 文件触发** |
| 3 | `Session.swift:1240-1242` | `playRandomGame` 强制解包 + `Int.random(in: 0..<0)`：黑方开局库为空的新用户按"随机一局"（约 50% 概率随机到黑方筛选）直接崩溃 |
| 4 | `DatabaseView.swift:337` | `getGamesInBookUnfiltered` 强制解包 `gameObjects[$0]!`：一个棋局同时挂在两本书下、删除其中一本书后（`deleteBook` 会删 game 对象但不清理另一本书的 gameIds）→ 崩溃 |
| 5 | `iOSPlatformService.swift:101-105, 182-186` | iPad 上 `.actionSheet` 未设 popover 锚点，present 即抛 `NSGenericException` |
| 6 | `Session.swift:103` | `currentFenObject` 兜底失败走 `fatalError`——数据不一致时直接杀进程，建议降级为重置到起始局面 |
| 7 | `MacOSPlatformService.swift:11-43` | `queryFenScore`/`pikafishQuickMove` 的 catch 分支从后台线程调 `showWarningAlert` → `NSApp.stopModal`/`orderOut` 离主线程操作 AppKit |

---

## 三、P1：功能性 bug（用户可感知）

### 3.1 删招后的"僵尸 move"——同一招法永远加不回来（已验证全链路）

`Move.markAsRemoved()` 只把 `targetFenId` 置 nil（`Move.swift:70-72`），但 `moveToId[[source, target]]` 映射不清除。之后重新走这步棋：`ensureMove`（`DatabaseView.swift:110-125`）查到映射返回僵尸 move → `addMoveIfNeeded` 因 target 为 nil 拒绝（`FenObject.swift:199-207`）→ `autoExtendGame` 因 `move(from:to:) == nil` 拒绝扩展（`GameOperations.swift:39`）→ **棋子无声弹回，无任何提示，且本会话内无法恢复**。重启后 `rebuildIndexes()` 把僵尸排除在 `moveToId` 外（`DatabaseData.swift:64-70`）才能重新创建。僵尸对象还会永久残留在存档 JSON 里。`formatMoveList` 里的 `"nil_bug"` 占位符（`GameOperations.swift:223`）说明此类症状已被见过。

**修复**：`removeMove` 时同步清除 `moveToId` 条目（或 `ensureMove` 遇到 nil-target 的旧 move 时创建新 move）。

### 3.2 引擎评估子系统

- **引擎崩溃后永久失效**：`PikafishService.start()` 的 `guard process == nil`（`PikafishService.swift:83`）对"已死但非 nil"的进程直接 return，`evaluatePosition` 的重启逻辑形同虚设，之后每次评估都 10 秒超时。无 `terminationHandler`。
- **`cancelAll()` 不等待在飞任务**（`EvaluationQueue.swift:81-92`）：立即置 nil `processingTask`，重新入队即产生第二个处理任务，两个 `evaluatePosition` 在无锁的 `@unchecked Sendable` service 上并发交错 UCI 命令、竞争 `outputBuffer`（`PikafishService.swift:6,13`）。被取消任务的收尾还会污染新队列的 `dedupSet`。
- `waitForResponse` 按子串匹配 `bestmove`，管道半行送达时解析出截断的着法（`:310` + `:167-175`）；引擎死亡时 poll 热循环空转直到 120 秒超时；`stop()` 在主线程 `waitUntilExit` 无超时，可挂死退出流程。
- `pikafishQuickMove` 整段跑在非 MainActor 的 unstructured Task 上，惰性创建 service/queue 的 ivar 写入与主线程竞争（`ViewModel.swift:309, 1341-1398`）。
- **评估进度条不刷新**：`StatusBarView.swift:146` 读 `viewModel.evaluationQueue.state`，但没人观察这个 ObservableObject，取消评估后进度条悬挂到下一次无关刷新。

### 3.3 iPad 弹窗全部静默失效（已验证）

`iPadContentView` 创建 `IOSPlatformService` 后从不调用 `setViewModel`（全仓库只有 iPhone 调了），也没挂 `.alert` modifier → 练习模式的"棋谱结束/没有着法"等所有提示在 iPad 上无声消失。另外 iPhone/iPad 的 `rootViewController` 在 `init` 时机解析，scene 大概率还不是 `foregroundActive`，`presentingViewController` 永远为 nil → 文件选择器静默不弹；`recoverFromUserChoice` 的 continuation 因 completion 永不回调而**永久泄漏**（`ViewModel.swift:1215-1242`）。

### 3.4 走法规则：没有"送将/自将"检测（两个独立审查确认）

`MoveRules.getLegalDestinationSquares` 只做单子几何走法；除了将帅自己移动时的对脸检查，**任何子力都可以送将、走开后暴露将帅对脸、王可以走进对方攻击线**。对一个用于背谱学习的工具，这意味着练习时可以录入非法局面。没有任何测试钉住这是有意取舍还是缺陷。建议：几何走法后模拟落子做将军检测过滤（数据规模小，性能无忧），至少加注释+测试声明设计意图。

### 3.5 PGN 导入

- **后台线程改数据**：`PGNImportView.swift:119-125, 157-160` 在 `PGNHttpServer` 私有队列和 `DispatchQueue.global` 上直接调 `viewModel.importPGNFile` → 改 Database + 切 `@Published dataChanged`，正是 #130 修过的那类 data race。
- 不剥离 `{}` 注释和 `()` 变着：注释里形如坐标的 4 字符 token 会被**当真实着法插进主线**，静默污染棋局（`PGNParser.swift:90-107`）。
- 同时含 `[Game]` 和 `[Event]` 头的标准 PGN 每局被拆成两局（`:43-49`）；中文纵线记号静默丢弃；`1.h2e2` 紧贴序号的 token 整体丢弃；着法零合法性校验（吃己方子、连走两步都接受）；`DateFormatter` 未设 `en_US_POSIX` locale。

### 3.6 其他确认的逻辑 bug

- **`makeRandomGame` 的 toggle 语义错误**（`ViewModel.swift:1530-1542`）：已在红方开局筛选时，随机到红方会把筛选**关掉**，在全库上随机——意图是"设置筛选"，实现成了"切换筛选"。
- **`autoAddMovesToOpening` 循环中误用 `return`**（`Session.swift:671-672`）：遇到一个数据缺失的局面就放弃处理剩余全部局面，且无提示。应为 `continue`。
- **`,l` 快捷键注册冲突**（`ViewModel.swift:436` vs `:606`）：`toggleStepLimitation` 与 `toggleShowLastMove` 同键，字典后者覆盖前者，步数限制快捷键静默失效。
- **`setFilters(specificGameId: nil)` 清不掉**（`SessionManager.swift:111`）：`specificGameId ?? 旧值` 使"显式清除"无效。`deleteGame` 想清掉已删棋局的 id 清不掉，之后还能 toggle 回一个指向已删棋局的 specificGame 视图。API 需要区分"nil=保留"与"nil=清除"。
- **SM-2 偏离标准**（`SRSData.swift:34-37`）：失败评分（q<3）也扣 easeFactor，失败项双重惩罚后 EF 速降钉死 1.3，间隔再也长不起来；失败项被排到明天而非当日重学；到期判定锚定时刻而非日历日。
- **棋盘 stale selection**（`Board.swift:15-16, 273-299`）：选中棋子后用键盘导航换局面，旧高亮不清除，点旧蓝点会经无合法性检查的 `getNewFenAfterMove` 提交任意局面。
- `MoveListView.swift:72` `.scrollPosition(id:)` 缺配套 `.scrollTargetLayout()`，着法列表不会跟随当前步自动滚动；`GameInputView` 的"记录对弈时间"开关从未被读取。
- 同线双子（叠车等）中文记号无"前/后"消歧（`Move.swift:423-441`）。
- `reload()`/`restoreFromBackup()` 不失效实战索引（`Database.swift:98-108, 225-245`），同步后反查表指向旧数据；且 `markDirty` 失效索引后**没有任何重建触发点**（只在启动时建一次），编辑过一次后实战列表永远走线性扫描慢路径。
- 静默云库查分无在飞去重/退避（`ViewModel.swift:1318-1336`）：按住方向键扫过未评分线路会瞬间发出几十个并发请求，"unknown" 响应还会追加 `queue` 请求，全部不可取消。

---

## 四、设计与架构问题

### 4.1 异步 dirty/version 标记体系是脆弱性的根源

`notifyDataChanged`、`markDirty`、`markClean`、`reload` 全部经 `DispatchQueue.main.async` 异步生效，造成"修改已发生但标记还没生效"的窗口。`ViewModel.setCurrentFenInRedOpening` 里的**双重嵌套 async** hack（`ViewModel.swift:899-903`，注释自述"避免与 Session.notifyDataChanged 的 async 竞态"）就是这套体系的症状。所有调用本就要求主线程，**同步化这套标记**可一次性消除版本竞态、save 跳过、双 async hack 三类问题，是性价比最高的架构修缮。

### 4.2 巨型类与职责扩散

- `Session.swift`（2247 行）混合了导航、走子、实战统计、SRS、书签、路径生成、开局库批量工具、棋书初始化——建议按 extension 文件拆分，统计/SRS/路径生成可下沉为独立类型。
- `ViewModel.swift`（2279 行）约 100 个一行转发属性 + 动作注册 + iCloud 协调 + 引擎编排。动作注册（400 行）和 iCloud 同步流程（200 行）各自值得一个独立类型。
- `GameBrowserView.swift` 1397 行装了 15 个 view 类型，应按面板拆分。

### 4.3 单例耦合与隐藏依赖

`Session` 内部多处直接引用 `Database.shared`（`Session.swift:951, 1880, 2002, 2072`），绕过了自己持有的 `databaseView`，破坏了依赖注入和可测性。

### 4.4 MVVM 违规

- `PracticeMistakeStatsView.swift:24, 61, 82`：View 直达 `session.databaseView` 并调用 `resetPracticeMistakes()` + 手动 toggle `dataChanged`。
- `GameBrowserView.swift:86-115, 1234-1239`：直写 `session.sessionData.gameBrowser*`，**绕过 dirty 标记**——浏览器状态可能不被保存。
- `CommentView.swift:110-185`：View 直调 `CourseVideoStorage` 并自起 `NSOpenPanel`/`NSAlert`，三层穿透。
- 根因：`ViewModel.swift:26` 公开暴露 `var session: Session`，等于给所有 View 发了 Model 直通卡。建议收紧为 `private`，按需开转发接口。

### 4.5 重复与脆弱约定

- `Move.stringifyMove` 与 `extractPieceMove` 重复约 200 行 diff 推导逻辑（`Move.swift:126-258` vs `260-445`）——前者应基于后者实现。
- `generateAllGamePaths` 在 `Session.swift:1669` 和 `GameOperations.swift:111` 两份实现；`withLock`/`withStepLimit` 完全相同（`DatabaseView.swift:753-777`）。
- 起始局面 FEN 字符串硬编码散落 ≥3 处。
- `ensureFenId`/`ensureMove` 用 `count + 1` 发号（`DatabaseView.swift:57, 119`）——当前因"从不删除"而安全，但这是个无人声明的隐含约定，建议改持久化 maxId。
- iOS/Mac 视图层大面积复制（result 颜色 ×4、复习面板 ×3、`MacContentView` 里逐字节相同的两个模式分支等）。
- 死代码：`Utils.swift` 的 `makeDiff`/`isEqual`/`hashString`/`stringify` 全无调用方；多处死 `@State` 和无效 modifier。
- `xiangqiyashiuBookId` 拼写（雅趣应为 yaqu）；`bookmarkList` 用 `compactMap` 做 `map` 的事。

### 4.6 健壮性

- `SessionData` 多数字段必需 `decode`（`SessionData.swift:68-82`），任一字段缺失 → 整个会话状态静默重置。应全部 `decodeIfPresent` + 默认值。
- `DatabaseData` 无独立 schemaVersion，新老版本互开易触发 1.1 空库链。
- `RemoteControlServer`（DEBUG）`acceptLocalOnly` 正确，但无 token/Origin 校验，本机浏览器页面可 CSRF 触发 `deleteMove` 等动作；建议加每次启动随机 token。
- ViewModel ↔ ActionDefinitions 闭包强引用循环（单实例 app 影响小，但堵死未来多窗口回收）。

---

## 五、性能

1. **DFS 全路径物化**（`Session.generateAllGamePaths` / `GameOperations.makeRandomGameDFS`）：开局库是含大量换序的 DAG，简单路径数指数增长，大库上"随机一局/上局/下局"会卡死或耗尽内存。路径**计数**已有 `fenIdToGamePathCount`，随机抽取可按叶子数加权随机下行，无需物化所有路径——最值得做的算法改造。
2. **主线程同步 iCloud I/O**：保存/加载/版本检查全在主线程做协调读写 + 全量 JSON 编解码，`coordinatedWrite` 失败还 `Thread.sleep(0.5)` × 3 纯阻塞（`DatabaseStorage.swift:92-99`）。库越大卡顿越明显。
3. 全量保存用 `.prettyPrinted`（体积约翻倍，iCloud 上传更慢）；`loadDataVersionFromDefault` 名为只读版本号，实际协调读整个文件，且在每次文件变更通知和保存前都跑一遍。
4. `specificGame` 视图的 `fenIdFilter` 每次调用线性扫描棋局所有 moveIds，BFS/路径生成等循环里是 O(n²) 级。
5. `GameBrowserView.totalGameCount` 每次渲染递归数整棵子树。

---

## 六、测试体系

单元测试全绿，Model 层 Codable 往返、六种基础视图过滤、PGN 镜像归一、GameOperations 纯函数覆盖扎实。但：

- **最危险的代码恰好零覆盖**：iCloud 同步/冲突全链路、`playNewBoardFen`、锁机制、增量实战统计、`specificGame`/`specificBook` 视图（**近期两次 crash 修复 #117/#119 的发源地**）、`withStepLimit`/`withLock`/`combined` 组合视图、iCloudFileCoordinator 整类。
- **4 个无法失败的伪测试**（如 `testCurrentVariationIndex` 断言 `>= 0` 而实现 `?? 0` 兜底；`testJumpToNextOpeningGap` 的断言包在条件 if 里）。
- **EvaluationQueueTests 用固定 sleep 等 MainActor 任务 + 非 MainActor 调用主线程 API**——既 flaky 又自带 data race。
- 每个 Session init 静默导入 550 局《适情雅趣》，全套件 100+ 次重复支付，且测试假设"fenId 999 未占用"已被挤到 ~560 边缘，极脆弱。
- `EngineScoreStorageTests` 名为 Storage 测试却从未调用 Storage API。
- `createTestDatabase()` 在 10 个文件中各自复制且互有差异——建一个共享 `TestDatabaseBuilder` 是基建优先项。
- 规则测试缺口：蹩马腿只测上方一条腿、塞象眼只测一个方向、无黑方王/底线兵用例、无"送将是否合法"的行为钉子。

---

## 七、改进路线图（按投入产出排序）

**第一批（数据安全 + 崩溃，每项都小而关键）**
1. `markDirty`/`markClean` 同步化（一处改动，消除版本竞态、save 跳过、双 async hack）
2. 解码失败只读模式 + 保存前无版本可比时强制确认 + 覆盖前自动备份
3. 退出/进后台自动保存
4. 修 5 处崩溃：MacPathEditorView 索引、FEN 入库校验、`playRandomGame` 空路径、`getGamesInBookUnfiltered` 解包、iPad actionSheet
5. 冲突版本按时间戳比较 + 不删除其他版本

**第二批（高频功能正确性）**
6. 僵尸 move 修复（`removeMove` 同步清理 `moveToId`）
7. 引擎自愈（`start()` 清理死进程 + `terminationHandler`）+ `cancelAll` 等待在飞任务
8. 线程归位：ViewModel 标 `@MainActor`（或至少 `pikafishQuickMove`/alert 服务/PGN 导入回主线程）
9. iPad `setViewModel` + alert modifier；`rootViewController` 惰性解析
10. PGN 解析剥离注释/变着 + FEN/着法校验
11. `,l` 快捷键、`makeRandomGame` toggle 语义、`autoAddMovesToOpening` 的 return、SM-2 失败不扣 EF

**第三批（架构与性能）**
12. 路径计数代替全路径物化；保存瘦身（去 prettyPrinted、版本号 sidecar、后台编码）
13. `session` 收紧为 private，收敛 4 处 MVVM 违规；Session 按职责拆文件
14. `setFilters` 的 id 清除语义重设计；实战索引失效后的重建触发
15. `SessionData` 全 `decodeIfPresent`；DatabaseData 加 schemaVersion

**第四批（长期健康）**
16. 共享 `TestDatabaseBuilder` + 补 iCloud 同步链路与 specificGame/Book 视图测试 + 删 4 个伪测试
17. 消重（stringifyMove/extractPieceMove、iOS/Mac 视图、双份 DFS）；删 Utils 死代码
18. 修 UITests target；RemoteControlServer 加随机 token
