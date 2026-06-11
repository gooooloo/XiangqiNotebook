# Code Review 修复计划（第二批）

日期：2026-06-12
分支：`code-review-fixes-2`
来源：`docs/code-review-2026-06-10.md` 第一批 PR (#170) 中暂缓的遗留 issue。

约定：每个 issue 一个独立 commit，commit 后运行完整 macOS 测试套件，全部通过才进入下一项。涉及 iOS 代码的改动以 iOS Simulator 构建验证（pre-push hook 同款检查）。

## 修复顺序

按「先 bug 后增强、先低风险后大重构」排序：

### 阶段一：Bug 修复

| 顺序 | Issue | 摘要 | 方案要点 |
|---|---|---|---|
| 1 | #127 | 复习评最后一项时 `reviewQueue[currentReviewIndex]` 越界崩溃 | 两处 `reviewInProgressView`（Mac/iPhone）渲染前做索引防御；越界时不渲染进行中内容 |
| 2 | #155 | `setFilters` 无法显式清除 `specificGameId/specificBookId` | 引入显式语义参数（`.keep`/`.clear`/`.set(id)` 哨兵枚举），`deleteGame`/`deleteBook` 后真正清除 |
| 3 | #157 | 录入棋局「记录对弈时间」开关无效 | `saveGame()` 读取 `hasGameDate`，关闭时不写 `gameDate`（`GameObject.gameDate` 为可空） |
| 4 | #156 | 棋盘残留选中高亮可提交非法局面 | 局面外部变化（导航/加载/筛选切换）时清除 `selectedSquare/highlightedSquares` |
| 5 | #158 | 静默云库查分无在飞去重与退避，导航请求风暴 | fenId 在飞集合去重；限流响应指数退避；导航离开不再追加 queue 请求 |
| 6 | #159 | Pikafish UCI 读取健壮性 | 行缓冲只解析完整行；EOF/进程死亡立即报错跳出；退出等待带超时后 terminate |
| 7 | #160 | 保存后抑制窗口吞掉真实远程变更 | 抑制改为版本 checkpoint 比较：抑制结束时对比磁盘 dataVersion 与保存时记录值，不一致则补发通知 |
| 8 | #128 | ViewModel 缺少 MainActor 隔离，后台线程读 Session 数据竞态 | `ViewModel` 标注 `@MainActor`，适配编译错误；异步 action 的 session 访问自然收敛到主线程 |

### 阶段二：增强（低风险优先）

| 顺序 | Issue | 摘要 | 方案要点 |
|---|---|---|---|
| 9 | #166 | SessionData/DatabaseData 解码健壮性 | SessionData 全字段 `decodeIfPresent`+默认值；DatabaseData 增加 `schemaVersion` |
| 10 | #165 | 走法合法性：送将/自将过滤 | 生成后模拟落子检测将军与对脸，测试钉住语义 |
| 11 | #161 | 引擎分数文件跨设备合并 | 保存前 coordinated read 远端文件按 fenId 合并；加载触发 iCloud 下载 |
| 12 | #163 | 保存路径瘦身 | 去 `.prettyPrinted`；dataVersion sidecar；重试 sleep 移出主线程 |
| 13 | #162 | 随机一局改计数加权随机 | 用 `fenIdToGamePathCount` 加权随机下行，去除全路径物化；合并重复实现 |
| 14 | #164 | 收紧 ViewModel.session 暴露 | session 收紧为 private，违规 View 改走 ViewModel 转发接口 |
| 15 | #167 | 测试基建 | 共享 TestDatabaseBuilder；修伪测试；补关键链路测试 |
| 16 | #168 | 视图层重复消除 | 合并重复视图代码；删死代码 |

视进度执行，未完成项保持 issue 开放并在 PR 描述中说明。

## 完成后

- 创建 PR（包含本文档），**不合并**，等待人工 review。
- 每个 commit 标题引用对应 issue 号。
