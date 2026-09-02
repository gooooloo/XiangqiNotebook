# 象棋笔记本（XiangqiNotebook）代码评审报告（第二轮）

> 评审日期：2026-09-02
> 评审范围：以 2026-06-10 评审（`docs/code-review-2026-06-10.md`）为基线，覆盖此后 99 个 commit、约 1.8 万行新增代码（app 内置 AI 问棋、Claude Code 桥接、远程操控 HTTP 服务、iOS 内嵌皮卡鱼、课程视频导入、iPhone/Mac 界面改版等），并逐项核查上一轮 P0/P1 的修复状态。
> 评审方式：四路并行专项精读（数据安全与核心模型、AI 与远程操控、引擎与服务层、视图/测试/工程卫生），关键结论均做了代码级交叉验证；未经证实的推测已剔除。
> 基线状态：工作区干净，`main` 分支 `356233b`。

**总体评价**：上一轮的 P0 大多已实修（`markDirty` 竞态、保存抑制窗口、PGN `[FEN]` 校验、随机一局崩溃、路径编辑器越界、SessionData 容错解码等均核实修好）。架构纪律执行得很好：`Views/` 下没有任何绕过 `private session` 的 workaround，macOS-only API 全部在 `#if` 内，Timer/通知/sink/回调全部弱引用。新增代码里最需要优先处理的是两类问题：

1. **引擎并发互斥不完整**：iOS 内嵌引擎可被重入导致崩溃与永久 ENGINE_BUSY；macOS 多个入口可并发驱动同一管道；引擎死后写 stdin 触发 SIGPIPE。
2. **跨设备数据丢失路径仍在**：崩溃恢复快照会被静默删除、Cmd+Q 不提示且删快照、恢复备份后版本号不抬高触发反向覆盖。

---

## 一、P0 / P1（优先处理）

### 1.1 iOS 内嵌引擎可重入 → 崩溃 + 永久 ENGINE_BUSY 【P0】

`ViewModel.swift:1938`（`aiRespondIOS` 只 `guard !isEvaluatingIOS`）、`ViewModel.swift:1871`（问棋侧只查 `isEvaluatingIOS`）、`PikafishEngineBridge.mm:188-222`、`PikafishServiceIOS.swift`（自身无任何忙碌守卫）。

互斥是单向的：问棋 `evaluate`（默认 3 s）进行中，用户点「AI应招」会对同一个 `Stockfish::Engine` 再次 `setPosition` + `go`。后果链（按引擎源码核实）：

- `setPositionWithFEN` 在主线程 `_pvLines.clear()`，与搜索线程 `on_update_full` 写同一个 `std::map` 数据竞争；
- `set_on_bestmove` 无锁覆盖搜索中的回调；
- 第一次搜索完成调用的是**第二个**回调 → 第一个 `withCheckedContinuation` 永不恢复，`isRemoteAnalyzing` 的 `defer` 永不执行，之后所有问棋恒 ENGINE_BUSY；
- 第二次搜索结束再调一次同一回调 → `CheckedContinuation` 二次 resume，进程 trap。

**修复**：把互斥下沉到 `PikafishServiceIOS` 自身（单个 in-flight 标志，忙则抛 busy），不依赖 ViewModel 两个标志互相记得对方。

### 1.2 macOS `PikafishService` 无内部串行化 【P1】

`ViewModel.swift:1805`（`pikafishQuickMove` 直接调 `service.evaluatePosition`，不入队）、`EvaluationQueue.swift:60-69`（`enqueue` 不检查快速应招/远程分析在飞）、`PikafishService.swift:365-406`。

场景：快速应招 3 s 期间按 `s` 深评 → 队列任务立刻起跑，两个 `waitForResponse` 在两条 GCD 线程上对同一 `FileHandle` 读 `availableData`、无锁 `self.outputBuffer += text`（String 数据竞争），第二方还会 `stop` + 清空缓冲，偷走第一方的 `bestmove`。远程 `/eval` 起跑后再 enqueue 同理（`remoteEngineAnalyze` 只在开头查一次 `queue.isIdle`）。

**修复**：把 `PikafishService` 改成 `actor`（或内部一把「忙碌即抛」的门），409 判定只在 service 一处完成。

### 1.3 引擎死后写 stdin 触发 SIGPIPE，整个 app 被杀 【P1】

`PikafishService.swift:351-355`（`sendCommand` 无 `isRunning` 检查）、`:267`（`stopCurrentSearch`）、`:247`（`analyzePosition` 的 `defer` 在 `engineTerminated` 抛出后仍写管道）。全仓库无 `signal(SIGPIPE, SIG_IGN)`。

场景：引擎崩溃或因 NNUE 校验失败自行 `exit()`，用户点「取消评估」→ `cancelAll` → `stopCurrentSearch` → 向已关闭管道 `write` → SIGPIPE。即便忽略了信号，旧式 `FileHandle.write(_:)` 在 EPIPE 时抛 ObjC 异常，Swift 同样接不住。

**修复**：启动时忽略 SIGPIPE；`sendCommand` 改为 `guard process?.isRunning == true` + `try? write(contentsOf:)`。

### 1.4 崩溃恢复快照在跨设备场景被静默删除 【P1】

`ViewModel.swift:373-380`：`checkForCrashRecovery` 仅当 `snapshotVersion > canonicalVersion` 才提示恢复，否则直接 `clearRecoverySnapshot()`。

场景：设备 A 脏数据（快照 dataVersion = N+1）崩溃；设备 B 在 A 重启前保存一次（写出 N+1 或更高）；A 启动加载到 N+1 → 快照被判「旧快照」静默清掉，A 的全部未保存修改丢失且无任何提示。

**修复**：快照存在就提示（附写入时间），不用 dataVersion 做取舍；或快照另存 baseVersion + mtime 与存档 mtime 比较。

### 1.5 macOS Cmd+Q 有未保存修改时无提示，且顺手删掉唯一的恢复快照 【P1】

`ViewModel.swift:267-276`：`willTerminateNotification` 里 `DatabaseStorage.clearRecoverySnapshot()`；全仓库无 `applicationShouldTerminate`。注释称「干净退出视为主动丢弃」，但用户习惯性 Cmd+Q 就把跑了几小时的评估/编辑连同快照一起抹掉。

另外同一处（`:271-276`）观察者内再开 `Task { @MainActor }` 去 `cancelAll()`/`stop()`，而 `applicationWillTerminate` 返回后 AppKit 直接 `exit()`，主线程不会再转一圈，这段清理实际是死代码，目前靠 pikafish 读到 stdin EOF 自动 `quit` 兜底。

**修复**：加 `NSApplicationDelegate.applicationShouldTerminate`，脏时弹「保存/丢弃/取消」；至少退出时保留快照。观察者已在主队列，清理直接同步调用。

### 1.6 恢复备份 / 恢复快照后 dataVersion 不抬高，触发反向覆盖链 【P1】

`Database.swift:340-363`、`ViewModel.swift:389, 1589`。`restoreFromBackup` 直接采用备份文件的 `dataVersion` 并置脏，不与远端比较（上一轮 1.4 后半仍开放）。

场景：iCloud 存档 v500，本机恢复 v100 备份并确认强存 → 文件变 v100；另一设备收到变更后走 `reloadFromRemote`，`remoteVersion(100) <= currentVersion(500)` 被忽略（`ViewModel.swift:1461`），它下次保存又把恢复结果覆盖回去。

**修复**：恢复时 `dataVersion = max(backup, loadDataVersionFromDefault() ?? 0) + 1`。

### 1.7 问棋取消后 `wireMessages` 被污染，且弹假错误 【P1】

`ChatViewModel.swift:243-247`、`:216-221`、`:186`。`cancel()` 立即 `rollbackToLastUserMessage()`，但正在 `await toolbox.execute(...)`（引擎分析，可达十几秒）的循环体返回后不检查 `Task.isCancelled`，直接 `wireMessages.append(.toolResult(...))`——此时对应的 assistant tool_calls 消息已被回滚删掉，留下一条孤儿 tool 消息，下一次提问会被 OpenAI 兼容服务以「tool 消息无配对 tool_calls」拒绝。同一位置，`client.send` 因 Task 取消抛出的 `URLError.cancelled` 落入 `catch`，被 `transportError` 映射成 `.network("cancelled")` 并 `setError`，用户点「停止」后看到「连不上服务」红条加重试按钮。`ChatViewModelTests` 无任何取消场景覆盖。

**修复**：`await` 之后先 `guard !Task.isCancelled else { return }` 再 append；catch 里 `if Task.isCancelled { return }`。

### 1.8 旧 Task 的收尾会覆盖新一轮的运行状态 【P1】

`ChatViewModel.swift:159-167` vs `:176-187`。`cancel()` 只 `runningTask?.cancel()` 就把 `isRunning` 置 false，用户随即发新问题会起第二个 Task；旧 Task 等引擎返回后继续执行收尾闭包 `isRunning = false; runningTask = nil; clearProgress()`，把新一轮的进行中状态清掉——输入框重新可用、`guard !isRunning` 失守，可再发第三个请求并发跑。

**修复**：收尾前比对 `self?.runningTask === task`，或收尾闭包先查 `Task.isCancelled`。

### 1.9 多窗口下键盘事件串到错误的 ViewModel 【P1】

`XiangqiNotebookApp.swift:9` 用 `WindowGroup` 且未移除 `.newItem`，Cmd+N 会开第二个窗口；`MacContentView.swift:223-266` 每个窗口各装一个 `NSEvent.addLocalMonitorForEvents`，回调只检查 `NSApp.keyWindow?.firstResponder`，从不核对 `event.window`。

场景：开两窗，在窗口 2 按 `l`，先安装的窗口 1 监控先收到并返回 nil 消费掉，窗口 1 走子。此外两个 ViewModel 各自读写同一份 session 文件，后保存者覆盖前者。

**修复**：`CommandGroup(replacing: .newItem) {}` 禁掉多窗，或监控内加 `guard event.window === NSApp.keyWindow`。

### 1.10 路径编辑器 indices + Binding 删除后可能越界 【P1】

`MacPathEditorView.swift:197-214`：`ForEach(pathGroups.indices, id: \.self)` 内构造 `Binding { pathGroups[index] }`，而 `onDelete` 里 `pathGroups.remove(at: index)`。删除最后一组时 SwiftUI 可能对旧行再求一次 getter 触发越界（72-102 行的 `paths[pathIndex]` 同款）。上一轮修的是 stale `selectedGroupIndex`，这是另一条路径。

**修复**：ForEach 直接绑 `$pathGroups`（Identifiable），或 getter 用 `indices.contains(index)` 兜底。

### 1.11 快捷键注册无冲突检测，同类回归已发生两次 【P1】

`ActionDefinitions.swift:325, 352` `shortcutLookup[shortcutKey] = key` 静默覆盖；`0b27345` 修过 `,l` 重复。ViewModel 里 95 处注册全靠人工保证唯一（本次逐一核对过，`,v` 由 `#if os` 隔开，暂无冲突）。

**修复**：注册时 `assert(shortcutLookup[shortcutKey] == nil, ...)`，并在 `ActionDefinitionsTests` 加一条全量唯一性测试。

---

## 二、P2（排期处理）

### 2.1 数据与存储

- **被中途 stop 的半截分析结果按「足额 movetime」入缓存并同步到 iPhone**。`ViewModel+AnalysisToolHost.swift:78-83`，配合 `PikafishService.swift:267-269`、`ChatViewModel.swift:183,166`。`stopRemoteEngineAnalyze()` 让引擎提前吐 `bestmove`，宿主以 `movetimeMs: movetime` 入缓存，取消路径也照样落盘；之后 `findUsableEngineAnalysis` 把 0.5 秒的结果当 5 秒结论秒回，且标 `cached: true`。修复：`analyzePosition` 返回是否被 stop / 实际耗时，被中断的不入缓存。
- **`ensureFenId` 用 `count + 1` 发号，id 空间有空洞时静默覆盖既有局面**。`DatabaseView.swift:57, 123` 不检查 `fenObjects2[newId]` 是否已存在；旧 fen 的 `fenToId` 仍指向该 id → 两个 fen 指向同一对象。修复：`(keys.max() ?? 0) + 1` 或持久化 maxId。
- **保存前版本校验的漏洞与 TOCTOU**。`ViewModel.swift:1334-1370`、`Database.swift:33,44`。(a) `loadFailedAtStartup` 被设置但全仓库无人读取；存档 `data_version` 字节扫描成功但整体解码失败时，启动是空库，保存走「别处被修改过」分支——有确认框但不做自动备份、文案误导。(b) 版本检查 → 用户弹窗 → `saveAsync` 之间无二次校验，异步化后窗口更宽。修复：`loadFailedAtStartup` 为真强制走备份分支；确认后写盘前再读一次远端版本。
- **引擎分数合并在 iCloud 占位文件未下载时失效**。`EngineScoreStorage.swift:31-33, 99-102` 用 `fileExists` 判断，未下载的 `.icloud` 占位返回 nil → 不合并 → 整文件覆盖远端分数。修复：占位存在时先 `startDownloadingUbiquitousItem` 并等待/跳过本次保存。
- **备份 / 恢复失败仍只 print**。`ViewModel.swift:1563-1566, 1594`（上一轮 1.5 项仍开放）。修复：改走 `platformService.showWarningAlert`。
- **iCloud 冲突：输的一方被永久删除且不告知用户**。`iCloudFileCoordinator.swift:131-137` 按 mtime 取新者是对的，但 `removeOtherVersionsOfItem` 直接抹掉另一版本。修复：输方版本先拷贝到本地 `OverwriteBackups/` 再删除，并在 `publishChange` 时提示。
- **`Database.reload()` 仍是异步生效**。`Database.swift:180-186`。`reloadFromRemote`/`checkDataVersion` 在 `try reload()` 返回后立刻弹「数据已更新」，此时 `databaseData` 还没换；`showConflictAlert` 里 `reloadFromRemote()` 后紧跟 `setDataClean()`（`ViewModel.swift:1535-1538`）顺序依赖 runloop。修复：与 `markDirty` 同样改为 `runOnMain` 同步。
- **CourseImportService（新）整体正确**，两点小问题：`ViewModel.swift:2696` `Int(seconds.rounded())` 对超范围 Double 会 trap，`times` 来自外部 JSON 未校验，建议 clamp；各线路 `startFen` 可不同但 `startingFenId` 只取第一条（`CourseImportService.swift:94-95`），其余线路的边会进入 `moveIds` 却从起点不可达，建议要求所有线路同一 startFen 否则抛 `invalidLine`。
- **`Session.currentFenObject` 的 `fatalError` 仍在**（`Session.swift:110`）。启动路径有校验不可达，运行期数据不一致仍会杀进程。

### 2.2 引擎与服务

- **iOS `releaseResources` 并不释放内存**。`PikafishServiceIOS.swift:104-111` 注释称「释放置换表与线程池内存」，但 `Engine::search_clear` 只是 `memset` 置零 TT 并清历史表，64 MB Hash 与线程池全部保留。修复：改为 `setHashMB(1)`/`setThreads(1)` 再 resize，或删掉误导性注释。
- **NNUE 缺失/损坏时 iOS 进程内 `exit(EXIT_FAILURE)`**。`PikafishServiceIOS.swift:40-42` 找不到资源静默跳过 `loadNetwork`，随后 `go` → `verify_networks` 直接 `exit()`。修复：`nnuePath == nil` 时直接返回错误，不调用 `go`。
- **子进程签名缺 `--options runtime`**。`project.pbxproj:580`：主 app `ENABLE_HARDENED_RUNTIME = YES`，而 pikafish 只带 sandbox-inherit 签名。走 App Store 不受影响，若改走 Developer ID 公证会失败；`EXPANDED_CODE_SIGN_IDENTITY` 为空时 `codesign --sign ""` 直接把构建搞挂。修复：加 `--options runtime`，空 identity 时 `exit 0`。
- **`Hash value 4096` 硬编码**。`PikafishService.swift:125`：4 GB 置换表，8 GB 内存 Mac 上深评一局会把系统压进 swap。建议按物理内存比例或降到 1024。
- **两份 Pikafish 引擎并存**。`Resources/pikafish`（0.78 MB）+ `pikafish.nnue`（53.7 MB）被跟踪并以 Process 启动；同时 `project.pbxproj:792,878` 又从 `ThirdParty/Pikafish` 子模块编译进 `PikafishEngineBridge.mm`。两套版本易漂移，建议统一走子模块内嵌版。
- **可读性/最小化**：`PikafishService.EvaluationResult.depth: String?` vs iOS 的 `Int`，两套结构形状不同，上层要各写一份格式化（`EvaluationQueue.formatEvalDetail`）；`Session.displayDeepEngineScore` 两个 `#if` 分支除 key 外完全相同；`formatEvalDetail` 的 `h * 100 / 1000` 就是 `h / 10`；`EvaluationQueueState.elapsedSeconds` 只在状态变更时快照，UI 上不会走动。

### 2.3 远程操控 / MCP / Claude 桥接

- **RemoteControlServer 请求体无上限，鉴权发生在读完整个 body 之后**。`RemoteControlServer.swift:117-153,176`。`receiveHTTPRequest` 无限累加；任何本机进程不带 token 也能让 app 吞任意大 body 后才收到 403。`String(data:encoding:.utf8)` 对非法 UTF-8 恒返回 nil → `hasCompleteHTTPRequest` 恒 false，连接挂到对端主动关闭。token 比较用 `==` 非常量时间（本机模型下影响有限）。修复：累计超过 1 MB 即回 413 并 cancel；头部一到齐就先校验 token。
- **MCP 脚本用 `localhost` 连 9214，与 CLAUDE.md 自己的「一律写 `[::1]`」规则相悖，且 fetch 无超时**。`mcp/xiangqi-notebook-mcp.mjs:27,54`。修复：`BASE_URL = "http://[::1]:9214"`，`fetch(..., { signal: AbortSignal.timeout(90_000) })`。根因侧 `RemoteControlServer.swift:81-84` 可用 `params.requiredLocalEndpoint = .hostPort(host: "::1", port: ...)` 明确只收 v6，或补齐 v4 处理。
- **token 文件权限两边不一致**。`RemoteControlServer.swift:54`（默认 0644）vs `mcp/claude-bridge.mjs:402`（0o600）。修复：写后 `setAttributes([.posixPermissions: 0o600])`。
- **DEBUG 驱动接口在 `DispatchQueue.main.sync` 里同步跑任意 action**。`RemoteControlServer.swift:269-291,328-343`。action 若弹模态，server 串行队列被卡死，后续所有请求（含 Release 也有的 /state）超时，只能重启 app。修复：改 `main.async`，在 action 内部/之后发响应。
- **`/eval`、`/apply` 与 `AnalysisToolbox.execute` 重复实现且已漂移**。`RemoteControlServer.swift:373-385,413-501` vs `AnalysisToolbox.swift:296-302,554-595`。`/eval` 手写返回体缺 `mate`、`cached` 字段；`parseEvalParams` 与 `parseEvalArgs` 上限不同（60000 vs 15000）、参数名不同（`movetime` vs `movetime_ms`），MCP 脚本得为两者各做一次映射（`:196` vs `:207`）；`escapeJSON`（`:535`）与 `AnalysisToolbox.json` 是两套转义。修复：`/eval`、`/apply` 也走 `execute`，只留薄适配层；删掉 `escapeJSON`。
- **桥接在响应关闭时过早释放飞行槽**。`mcp/claude-bridge.mjs:339-349`。`res.on("close")` 里 `cleanup()` 把 `activeChild = null`，而子进程此刻才刚收到 SIGTERM（最长 5 秒宽限）；下一个 `/chat` 会在旧 claude 未退出时再 spawn 一个，两者都去抢 9214 的引擎。修复：`activeChild` 只在 `child.on("close"|"error")` 里清。
- **内置工具靠黑名单枚举**。`claude-bridge.mjs:97-101`。`-p` 模式下默认免确认的只读内置工具（列表外的任何一个）仍可被调用；黑名单会随 CLI 升级失效。棋谱注释（`comment`/`badReason`）是未经处理的用户文本，经工具结果进入模型上下文，注入面存在但目前被工具白名单压到「答错话 / 存错注释」的范围内。修复：查 `claude --help` 是否支持工具白名单开关，有则改用。

### 2.4 视图与 ViewModel

- **356233b 同款「换局重置」仍存在**。`SessionManager.swift:115-121` `setFilters` 在非复习/练习模式强制 `showAllNextMoves = true`，与 356233b 修掉的 `showLastMove` 是同一类「手工拷贝清单」缺陷。根因是新建 `SessionData()` 逐字段抄。修复：给 `SessionData` 加 `copy()`（Codable 往返即可），setFilters 先整体拷贝再覆盖需要重置的字段。
- **View 层直接引用 Model 常量**。`GameBrowserView.swift:90`、`RealGameListView.swift:57`、`iPhoneRealGameListView.swift:88` 直接用 `Session.filterSpecificGame`；`PGNImportView.swift:9,120,162`、`iPhoneImportExportSheets.swift:39` 直读 `UserDefaults`。修复：ViewModel 暴露 `isSpecificGameFilterActive` / 端口偏好属性。
- **攻击点位每帧重算**。`Board.swift:138-141` 在 body 内调 `getRedAttackCounts()/getBlackAttackCounts()`，`BoardViewModel.swift:101-110` 每次都重新解析 FEN 并跑 `MoveRules.getAttackedSquareCounts`，拖子/高亮任何重绘都触发两次全盘扫描。修复：在 `updatePieceViews`/开关变更时算一次缓存。
- **`BoardViewModel.getCurrentTurn` 硬下标**。`BoardViewModel.swift:123` `components[1]`，FEN 无空格即崩（`Board.swift:351` 点击棋子时调用）。目前入库有校验，但 `/apply` 等外部 FEN 入口在增多。修复：`components.count > 1 ? ... : "r"`。
- **分层/依赖注入违规（新增部分）**。`ViewModel+AnalysisToolHost.swift:62, 79, 101-102`、`ViewModel.swift:1749, 1899, 1913` 直接用 `Database.shared`；`Session.swift:2108, 2178` 仍绕过自身 `databaseView`（`deleteGame` 在注入测试库时会读错库的统计）。`fenObjects2` 未见在 Database/DatabaseView 之外被直接访问。
- **视图重复**。`RealGameListView.swift:1-40` vs `iPhoneRealGameListView.swift:1-95`（列表/空态/筛选逻辑）、`PracticeMistakeStatsView.swift:23-38` vs `iPhoneMistakeListView.swift:16-25`（统计聚合）、`iPhoneLibraryView.swift:251-257` 绕开已有 `GameResultColor.swift` 自写配色。`GameBrowserView.swift` 1383 行含 17 个 struct，`AddGameView`(150) 与 `EditGameView`(283) 9 个 @State 完全相同，`626-641`/`1125-1138` 排序逻辑重复且每次 body 重排。
- `DesignTokens.swift:10-48` 全为浅色固定值，无深色适配。

### 2.5 工具脚本

- `tools/import_course_videos.py:42` `open(TOKEN_PATH)` 无 try（app 未运行直接栈回溯），`:49/63-68` 畸形 meta.json 未防护。
- `tools/xq_video2pgn.py:124/138` ffmpeg 退出码被忽略，中途失败静默当「视频结束」；`:771-775` ffprobe 缺失或输出为空未处理。
- 地址 `[::1]`、`ProxyHandler({})`、容器 token 路径都正确。

---

## 三、测试覆盖缺口

- `stepBackward` 零测试；`handleKeyDown` 全量分发链路无测试（`ViewModelTests:736-796` 只查 toggle info）。
- 无 Database.save → 重新 load 的整链路 round-trip（`StorageTests` 只测单文件）。
- 快捷键唯一性无测试（见 1.11）。
- 问棋取消场景无测试（见 1.7、1.8）。
- `AISettingsView`、`copyBoardImage`、iPhone 5 标签页（`IPhoneTab`）、`BoardViewModel` 无测试。
- UI 测试只有一个 15 秒启动烟雾桩（`XiangqiNotebookUITests.swift:18-25`）。
- 脆弱点：`DatabaseViewTests.swift:281,288` 固定 sleep 100ms；`SRSDataTests.swift:408` 无断言。
- 真实路径：测试代码本身干净（temp dir、隔离 UserDefaults suite、钥匙串有测试闸），但 `CourseVideoStorage` 直写 `UserDefaults.standard` 且不可注入，一旦有测试碰 `setVideoPath` 就污染真实数据。

---

## 四、工程卫生

- 仓库 pack 约 100 MB，主因不是 nnue：`refs/codex/turn-diffs/checkpoints/...` 里塞了 2389 个 `DerivedDataScreenshot/` 文件（约 107 MB），不在任何分支上；删 `refs/codex/*` 后 `git gc --prune=now` 即可瘦身。
- `CLAUDE.md:117-126` 文件组织缺 `Models/AI/`（7 文件）、`RemoteControlServer`、`PGNHttpServer`、`CourseImportService`、`ChatViewModel`、`DesignTokens`、`EvaluationQueue`、`PikafishServiceIOS`；`:125` 仍称 PikafishService「仅 macOS」；`:180`「1.0.8 及之前」暗示已升版，但 `Version.xcconfig` 与 CHANGELOG 仍是 1.0.8。
- `mcp/*.mjs:8,11`、`mcp/README.md:34,107` 含 `/Users/qidu` 个人路径。
- `docs/` 三份 2026-06 审查文档已陈旧，可归档。
- `.github/workflows/claude.yml` 任何能评论 issue 的人都可 `@claude` 触发消耗订阅额度（权限只读、无 `pull_request_target`，安全面尚可）。
- `.githooks/pre-push` fail-closed 正确，但未包 `arch -arm64`。
- 已确认干净：无 `DEVELOPMENT_TEAM`（含全部历史）、无 API key、ATS 只对 chessdb.cn 例外、`.gitignore` 覆盖 xcuserdata/DerivedData/Signing.local。

---

## 五、上一轮（2026-06-10）问题状态核查

| 项 | 状态 | 证据 |
|---|---|---|
| 1.1 解码失败→空库→无确认覆盖 | 部分修复 | `Database.swift:38-50` 区分文件存在/不存在；`ViewModel.swift:1349-1367` 版本读不出时确认+自动备份；但 `loadFailedAtStartup` 无人读取，字节扫描能读出版本时走普通确认分支、无备份（见 2.1） |
| 1.2 无自动保存 | 部分修复 | macOS 30 s 快照 `ViewModel.swift:333-364`；iOS 仅进后台时写 `:287-303`，前台崩溃仍全丢；Cmd+Q 无提示且删快照（1.5）；跨设备后快照被静默丢弃（1.4） |
| 1.3 markDirty 竞态 | 已修复 | `Database.swift:77-88` guard 与自增同在 `runOnMain` 临界区；`saveAsync` 用 `mutationCount` 区分保存期间新修改 |
| 1.4 iCloud 冲突 | 部分修复 | `iCloudFileCoordinator.swift:98-146` 按 mtime 取新、经写协调、置 `isResolved`；恢复备份版本号问题仍开放（1.6）；输方版本仍永久删除（2.1） |
| 1.5 保存抑制窗口 | 已修复 | `iCloudFileCoordinator.swift:242-255` 窗口结束比 mtime 补发通知 |
| 1.5 引擎分数合并 | 基本修复 | `EngineScoreStorage.swift:67-102` 按 fenId 合并；占位文件未下载时仍会覆盖（2.1） |
| 1.5 saveToDefault TOCTOU | 仍开放 | `ViewModel.swift:1334-1370`，异步化后窗口更宽 |
| 1.5 备份/恢复错误只 print | 仍开放 | `ViewModel.swift:1563-1566, 1594` |
| 崩溃#1 MacPathEditorView 索引 | 已修复（另有新路径） | `MacPathEditorView.swift:107-112, 168-172, 215-219, 260`；indices + Binding 见 1.10 |
| 崩溃#2 PGN [FEN] 未校验 | 已修复 | `PGNParser.swift:196-197` `isValidBoardFen`；`Move.swift:148` 行长守卫 |
| 崩溃#3 playRandomGame | 已修复 | `Session.swift:1299-1306` 空范围返回 nil |
| 崩溃#4 getGamesInBookUnfiltered 解包 | 已修复 | `DatabaseView.swift:357-361` compactMap |
| 崩溃#6 currentFenObject fatalError | 仍在 | `Session.swift:110` |
| 3.1 僵尸 move | 已修复 | `DatabaseView.swift:112-119, 133-135` |
| setFilters nil 语义 | 已修复 | `SessionManager.swift:70-90` `IdUpdate` 哨兵 |
| SM-2 失败扣 EF | 已修复 | `SRSData.swift:33-38` |
| autoAddMovesToOpening 误用 return | 已修复 | `Session.swift:688, 699` |
| SessionData 容错 / schemaVersion | 已修复 | `SessionData.swift` 全 `decodeIfPresent`；`DatabaseData.swift:62-65` |

---

## 六、做得好的地方

- **MVVM 收紧真正落地**：`Views/` 下没有任何 `sessionManager`/`databaseView`/`*Storage` 引用，也没有绕过 `private session` 的 workaround。
- **平台守卫无一漏网**：NSPasteboard/NSSavePanel/NSWorkspace/NS(UI)ViewRepresentable 全在 `#if` 内，pre-push 的 iOS 构建检查起了作用。
- **引用循环管理到位**：Timer、NotificationCenter、sink、`EvaluationQueue` 回调全部 `[weak self]`，NSEvent 监控在 onDisappear 正确移除；DateFormatter 全部 static 化。
- **分数语义全链一致**：Mac 解析 UCI `cp`，iOS 取 `Score::InternalUnits`，杀棋折算与引擎同一公式；存库统一走子方视角，`Session.adjustScore` 只在显示时翻转，ChessDB 也是同视角。`EnginePVLine` 让 `/eval`、AI 工具、缓存不分平台。
- **UCI 读循环健壮性**（7cc7516）与 **EvaluationQueue 的 flaky 修复是真修**（e279246，`holdEvaluation` 门 + `waitUntil` 取代 sleep；`generation` 代数防旧任务污染）。
- **鉴权与桥接设计扎实**：`SecRandomCopyBytes` 32 字节 token，自定义头逼出 CORS 预检天然挡住浏览器 CSRF，token 在 listener `.ready` 后才落盘；桥接 spawn 没有 `--dangerously-skip-permissions`，`--strict-mcp-config` + 工具白名单、隔离 cwd、`--no-session-persistence`、10 分钟硬上限、SIGTERM→SIGKILL、`readBody` 2 MB 上限。
- **纯函数拆分与测试**：`parseEvent`、`requestBody`、`translateClaudeLine`、`LLMStreamAccumulator` 分片拼装、`negatedScore` 把正负号换算钉在代码里；`AIKeychain.isRunningInTests` 硬闸防测试抹掉真实 key。

---

## 七、建议修复顺序

1. **引擎互斥三件套**（1.1、1.2、1.3）：崩溃与假死，用户可直接触发。
2. **跨设备数据丢失三件套**（1.4、1.5、1.6）：三处改动都很小，但都是「用户以为已保存/已恢复，实际被另一设备静默覆盖」。
3. **问棋取消**（1.7、1.8）并补取消场景测试。
4. **多窗口串台**（1.9）、路径编辑器 Binding（1.10）、快捷键唯一性断言（1.11）。
5. P2 中一行级别的：`ensureFenId` 用 `max + 1`、MCP 脚本改 `[::1]`、token 文件 0600、`getCurrentTurn` 下标守卫、`SessionData.copy()` 消灭换局重置。
6. 其余 P2 与卫生项视进度处理。
