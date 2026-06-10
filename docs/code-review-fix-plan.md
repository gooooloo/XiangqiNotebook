# Code Review 修复计划

> 配套报告：[code-review-2026-06-10.md](code-review-2026-06-10.md)
> 分支：`code-review-fixes`，每个修复一个独立 commit，引用对应 issue。
> 验证策略：每个修复后运行全量单元测试（`-only-testing:XiangqiNotebookTests`），全部通过才提交。

## 本分支修复清单（24 项）

按执行顺序排列。顺序考虑了依赖：CR-01（dirty 标记同步化）必须先于 CR-03（自动保存），其余基本独立，按"数据安全 → 崩溃 → 并发 → 功能"排列。

| 序 | Issue | 内容 | 改动文件 |
|----|-------|------|---------|
| 1 | [#131](https://github.com/gooooloo/XiangqiNotebook/issues/131) CR-01 | markDirty/markClean 主线程同步生效，消除版本号多次自增与 save 被跳过 | Database.swift |
| 2 | [#132](https://github.com/gooooloo/XiangqiNotebook/issues/132) CR-02 | 解码失败置 loadFailed 标志；保存前无法确认远端版本时强制弹确认 + 覆盖前自动备份 | Database.swift, DatabaseStorage.swift, ViewModel.swift |
| 3 | [#144](https://github.com/gooooloo/XiangqiNotebook/issues/144) CR-03 | macOS willTerminate / iOS didEnterBackground 自动保存脏数据 | ViewModel.swift |
| 4 | [#133](https://github.com/gooooloo/XiangqiNotebook/issues/133) CR-04 | 路径编辑器删除组/路径后选中索引平移/重置 | MacPathEditorView.swift |
| 5 | [#134](https://github.com/gooooloo/XiangqiNotebook/issues/134) CR-05 | 棋盘 FEN 校验（10×9）入库前拦截；解析函数防御 guard | BoardUtils.swift, Move.swift, PGNParser.swift |
| 6 | [#145](https://github.com/gooooloo/XiangqiNotebook/issues/145) CR-06 | playRandomGame 空路径返回 nil 不崩溃 | Session.swift |
| 7 | [#135](https://github.com/gooooloo/XiangqiNotebook/issues/135) CR-07 | getGamesInBookUnfiltered 改 compactMap | DatabaseView.swift |
| 8 | [#136](https://github.com/gooooloo/XiangqiNotebook/issues/136) CR-08 | iPad actionSheet 改 alert；presenter nil 时回调 completion(nil) | iOSPlatformService.swift |
| 9 | [#137](https://github.com/gooooloo/XiangqiNotebook/issues/137) CR-09 | iPad 补 setViewModel + .alert；presentingViewController 惰性解析 | iPadContentView.swift, iPhoneContentView.swift, iOSPlatformService.swift |
| 10 | [#138](https://github.com/gooooloo/XiangqiNotebook/issues/138) CR-10 | macOS 弹窗整体派发主线程 | MacOSPlatformService.swift |
| 11 | [#146](https://github.com/gooooloo/XiangqiNotebook/issues/146) CR-11 | 僵尸 move：ensureMove 跳过 nil-target 旧映射；删招时清理 moveToId | DatabaseView.swift, Session.swift |
| 12 | [#147](https://github.com/gooooloo/XiangqiNotebook/issues/147) CR-12 | 引擎死进程检测后清理重启 | PikafishService.swift |
| 13 | [#148](https://github.com/gooooloo/XiangqiNotebook/issues/148) CR-13 | cancelAll 后旧任务退出前不启动新任务；取消任务不改共享状态 | EvaluationQueue.swift |
| 14 | [#149](https://github.com/gooooloo/XiangqiNotebook/issues/149) CR-14 | pikafishQuickMove 入口归位主线程 | ViewModel.swift |
| 15 | [#139](https://github.com/gooooloo/XiangqiNotebook/issues/139) CR-15 | PGN 导入回主线程执行 | PGNImportView.swift |
| 16 | [#140](https://github.com/gooooloo/XiangqiNotebook/issues/140) CR-16 | PGN 剥离注释/变着；双头不拆局；FEN 头校验；DateFormatter POSIX | PGNParser.swift |
| 17 | [#141](https://github.com/gooooloo/XiangqiNotebook/issues/141) CR-17 | SM-2 仅 q>=3 更新 easeFactor | SRSData.swift |
| 18 | [#142](https://github.com/gooooloo/XiangqiNotebook/issues/142) CR-18 | makeRandomGame 改显式 setFilters | ViewModel.swift |
| 19 | [#143](https://github.com/gooooloo/XiangqiNotebook/issues/143) CR-19 | autoAddMovesToOpening 改 continue | Session.swift |
| 20 | [#150](https://github.com/gooooloo/XiangqiNotebook/issues/150) CR-20 | 步数限制快捷键改 ,L 解决冲突 | ViewModel.swift |
| 21 | [#151](https://github.com/gooooloo/XiangqiNotebook/issues/151) CR-21 | iCloud 冲突版本比较 modificationDate，仅更新者替换，标记 isResolved | iCloudFileCoordinator.swift |
| 22 | [#152](https://github.com/gooooloo/XiangqiNotebook/issues/152) CR-22 | 转发 EvaluationQueue.objectWillChange 到 ViewModel | ViewModel.swift |
| 23 | [#153](https://github.com/gooooloo/XiangqiNotebook/issues/153) CR-23 | MoveListView/VariantListView 补 scrollTargetLayout | MoveListView.swift, VariantListView.swift |
| 24 | [#154](https://github.com/gooooloo/XiangqiNotebook/issues/154) CR-24 | reload/restoreFromBackup 补 invalidateRealGamesIndex | Database.swift |

## 本分支不修复、已建 issue 跟踪（15 项）

**Bug（需要设计决策或无法夜间安全验证）**：
- [#155](https://github.com/gooooloo/XiangqiNotebook/issues/155) CR-25 setFilters 无法显式清除 specificGameId（API 语义设计）
- [#156](https://github.com/gooooloo/XiangqiNotebook/issues/156) CR-26 棋盘残留选中可提交非法局面（需梳理 Board 状态流）
- [#157](https://github.com/gooooloo/XiangqiNotebook/issues/157) CR-27 "记录对弈时间"开关无效（数据语义确认）
- [#158](https://github.com/gooooloo/XiangqiNotebook/issues/158) CR-28 静默查分请求风暴（去重/退避/取消设计）
- [#159](https://github.com/gooooloo/XiangqiNotebook/issues/159) CR-29 引擎 UCI 读取健壮性二期（截断行/EOF/退出超时）
- [#160](https://github.com/gooooloo/XiangqiNotebook/issues/160) CR-30 保存抑制窗口吞远程变更通知

**Enhancement backlog**：
- [#161](https://github.com/gooooloo/XiangqiNotebook/issues/161) E1 引擎分数跨设备合并
- [#162](https://github.com/gooooloo/XiangqiNotebook/issues/162) E2 路径计数加权随机替代全路径物化
- [#163](https://github.com/gooooloo/XiangqiNotebook/issues/163) E3 保存瘦身与后台化
- [#164](https://github.com/gooooloo/XiangqiNotebook/issues/164) E4 收紧 session 暴露、收敛 MVVM 违规
- [#165](https://github.com/gooooloo/XiangqiNotebook/issues/165) E5 送将/自将合法性过滤
- [#166](https://github.com/gooooloo/XiangqiNotebook/issues/166) E6 SessionData/DatabaseData 解码健壮性与 schemaVersion
- [#167](https://github.com/gooooloo/XiangqiNotebook/issues/167) E7 测试基建与关键链路补测
- [#168](https://github.com/gooooloo/XiangqiNotebook/issues/168) E8 视图层重复消除与死代码清理
- [#169](https://github.com/gooooloo/XiangqiNotebook/issues/169) E9 UITests target 修复 + RemoteControlServer token

## 修复原则

1. **最小改动**：每个修复只解决对应 issue，不顺手重构。
2. **测试先行**：能补单元测试的修复（CR-01、05、06、07、11、16、17、19）随修复补测试钉住行为。
3. **不破坏存档兼容**：不改动任何 Codable 字段与 JSON 格式。
4. **每修复一个 commit**：message 引用 issue（`fixes #N`），测试全绿才提交。
