# mcp/ — Claude 相关的桥接脚本

两个零依赖 Node（≥18）脚本，服务于两条「问棋」链路：

| 脚本 | 作用 | 方向 |
|---|---|---|
| `xiangqi-notebook-mcp.mjs` | MCP server（stdio），把 get_position / evaluate / evaluate_move / apply_moves / screenshot 桥接到 app 的远程分析接口（localhost:9214） | 外部 Claude（Claude Code / Claude Desktop）→ app |
| `claude-bridge.mjs` | HTTP 桥接（127.0.0.1:9216），把 app 内 AI 问棋的一次提问翻译成一次 `claude -p` headless 调用，用本机 Claude Code 的**订阅**登录跑 | app →（沙盒外）claude CLI |

两者可以叠加：app 内问棋选「Claude Code（订阅）」线路时，请求经 claude-bridge 到
claude CLI，claude 再经 xiangqi-notebook-mcp 调回 app 的分析接口取局面、跑引擎。

```
app（ClaudeCodeClient）
  │ HTTP + NDJSON（127.0.0.1:9216，X-ClaudeBridge-Token）
  ▼
claude-bridge.mjs（launchd 常驻，沙盒外）
  │ spawn: claude -p --output-format stream-json …
  ▼
Claude Code CLI（订阅鉴权）
  │ --mcp-config（stdio MCP）
  ▼
xiangqi-notebook-mcp.mjs
  │ HTTP（localhost:9214，X-RemoteControl-Token）
  ▼
app RemoteControlServer（/state /eval /eval_move /apply）
```

## claude-bridge：安装（launchd 常驻，推荐）

前提：本机装有 Claude Code 且已完成订阅登录（终端跑一次 `claude` 即可确认）。

```bash
cd /Users/qidu/dev/XiangqiNotebook   # 换成你的仓库路径

# 1. 用本机路径填模板（node 路径用 which node 查；nvm 用户注意别用 shim 之外的版本路径失效）
sed -e "s|__NODE_PATH__|$(which node)|" \
    -e "s|__REPO_PATH__|$(pwd)|" \
    mcp/com.gooooloo.xiangqi.claude-bridge.plist \
    > ~/Library/LaunchAgents/com.gooooloo.xiangqi.claude-bridge.plist

# 2. 装载（登录后自动常驻、崩溃自动拉起）
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gooooloo.xiangqi.claude-bridge.plist

# 卸载
launchctl bootout gui/$(id -u)/com.gooooloo.xiangqi.claude-bridge
rm ~/Library/LaunchAgents/com.gooooloo.xiangqi.claude-bridge.plist
```

不装 launchd 也能用：需要时手动 `node mcp/claude-bridge.mjs`（Ctrl-C 退出）。

日志在 `/tmp/xiangqi-claude-bridge.log`。

## claude-bridge：手测

```bash
BTOKEN=$(cat ~/Library/Containers/com.gooooloo.XiangqiNotebook/Data/Library/Application\ Support/XiangqiNotebook/claude-bridge-token.txt)

# 健康检查：claude 在不在、登没登录
curl --noproxy '*' -H "X-ClaudeBridge-Token: $BTOKEN" http://127.0.0.1:9216/health

# 一次问答（NDJSON 流式；工具要能跑通需 app 正在运行）
curl --noproxy '*' -N -H "X-ClaudeBridge-Token: $BTOKEN" -X POST http://127.0.0.1:9216/chat \
  -d '{"systemPrompt":"你是象棋教练","transcript":[],"question":"当前局面轮谁走？","model":"sonnet"}'
```

`/chat` 请求体：`{systemPrompt?, transcript: [{role:"user"|"assistant", text}], question, model?}`。
响应为 NDJSON 事件流：

| 事件 | 含义 |
|---|---|
| `{"type":"text","delta"}` / `{"type":"thinking","delta"}` | 正文 / 思考增量 |
| `{"type":"tool_use","id","name","input"}` | claude 开始调一个 MCP 工具 |
| `{"type":"tool_result","id","content","isError"}` | 工具结果（截断到 2KB，只做界面留痕） |
| `{"type":"ping"}` | 15 秒心跳，防客户端片间超时误判 |
| `{"type":"done","result","usage"}` | 终稿（权威）与 token 用量 |
| `{"type":"error","code","message"}` | 终结错误：`CLAUDE_NOT_FOUND` / `CLAUDE_NOT_LOGGED_IN` / `CLAUDE_FAILED` / `BUSY` |

行为约定：同一时刻只允许一个对话（撞上返回 409）；客户端断开连接即杀 claude 子进程；
单次问答硬上限 10 分钟。

## 故障排查

- **app 里报「连不上 Claude 桥接服务」**：桥接没在跑。`launchctl list | grep xiangqi` 看
  是否装载；看 `/tmp/xiangqi-claude-bridge.log`。
- **health 报 CLAUDE_NOT_LOGGED_IN**：在**终端**跑一次 `claude` 完成登录。launchd 环境
  首次访问钥匙串可能弹授权框，建议先手动 `node mcp/claude-bridge.mjs` 验证一遍再装常驻。
- **health 报 CLAUDE_NOT_FOUND**：桥接按 `~/.local/bin` → `/opt/homebrew/bin` →
  `/usr/local/bin` → PATH 的顺序找 claude；装在别处就在 claude-bridge.mjs 的
  `findClaude()` 里补一条。
- **curl 挂起**：本机 shell 若设了 HTTP(S)_PROXY（v2ray），发往 localhost 的请求会被
  劫持，务必带 `--noproxy '*'`。
- **问答报 authentication_failed 但 /health 正常**：spawn 出的 claude 连不上
  api.anthropic.com。网络需要代理的机器（v2ray）要保证 claude 子进程带上代理变量：
  手动跑桥接时 shell 里的 HTTPS_PROXY 会自然继承；launchd 常驻则要在 plist 的
  `EnvironmentVariables` 里补 HTTPS_PROXY（模板里有注释示例）。桥接刻意**不**清除
  代理变量（清 localhost 劫持是 xiangqi-notebook-mcp.mjs 在自己进程里做的事）。
- **问答中工具全部失败**：app 没在运行（9214 不通），或 app 是 1.0.8 及更早的正式版
  （彼时只读接口仅 DEBUG 构建启用）。
- **stream-json 形状变了**（升级 Claude Code 后问棋异常）：对照 `claude-bridge.mjs` 的
  `translateClaudeLine` 检查事件形状；已验证版本 2.1.241。

## 注册 MCP server（外部 Claude 问棋）

```bash
# Claude Code
claude mcp add xiangqi-notebook -- node /Users/qidu/dev/XiangqiNotebook/mcp/xiangqi-notebook-mcp.mjs
```

Claude Desktop 在 `~/Library/Application Support/Claude/claude_desktop_config.json` 的
`mcpServers` 中加入 `{"command": "node", "args": ["<仓库路径>/mcp/xiangqi-notebook-mcp.mjs"]}`。
