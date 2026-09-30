#!/usr/bin/env node
// 象棋笔记本 Claude Code 桥接（HTTP → claude CLI headless）
//
// app 内 AI 问棋的「Claude Code（订阅）」线路后端：把一次问答翻译成一次
// `claude -p --output-format stream-json` 调用，用本机 Claude Code 的订阅登录跑，
// 并把 claude 的流式输出转译成 app 能读的 NDJSON 事件流。
//
// 为什么必须是独立进程：Mac app 开了 App Sandbox，子进程继承沙盒，
// 读不了 ~/.claude 与钥匙串里的登录凭据——claude 只能在沙盒外跑。
// 本脚本不接触任何凭据，订阅鉴权全部由 claude CLI 自己完成。
//
// 工具调用发生在 claude 进程内部：--mcp-config 挂同目录的 xiangqi-notebook-mcp.mjs，
// 它把 get_position/evaluate/evaluate_move/apply_moves 桥到 app 的 localhost:9214。
//
// 运行方式（Node >= 18，零依赖）：
//   node mcp/claude-bridge.mjs        # 手动
//   或按 mcp/README.md 安装 launchd 常驻服务
//
// 已验证的 claude CLI 版本：2.1.241。stream-json 不是稳定契约，
// 升级 CLI 后若问棋异常，先对照 translateClaudeLine 检查事件形状。

import { createServer } from "node:http";
import { spawn, execFile } from "node:child_process";
import { randomBytes } from "node:crypto";
import { createInterface } from "node:readline";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// 注意：这里**刻意不清除** HTTP(S)_PROXY——spawn 出的 claude 要靠它连
// api.anthropic.com（实测清掉后认证请求发不出去，报 authentication_failed）。
// localhost 劫持问题归各自进程自己解决：xiangqi-notebook-mcp.mjs 在自己进程里
// 清代理，本进程不发任何外部请求。经 launchd 启动时没有 shell 代理变量，
// 网络需要代理的机器要在 plist 的 EnvironmentVariables 里补 HTTPS_PROXY。

const PORT = 9216;
const HOST = "127.0.0.1";
const TOKEN_HEADER = "x-claudebridge-token";
/// 心跳间隔：claude 冷启动 + MCP 初始化可能十几秒无事件，而 app 侧片间超时 180 秒，
/// 15 秒一跳绰绰有余，主要是让「连接还活着」可被观察
const HEARTBEAT_MS = 15_000;
/// 单次问答硬上限，防僵尸进程
const RUN_LIMIT_MS = 10 * 60 * 1000;
/// SIGTERM 后的宽限期，超时 SIGKILL
const KILL_GRACE_MS = 5_000;

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const MCP_SCRIPT = join(SCRIPT_DIR, "xiangqi-notebook-mcp.mjs");

/// app 沙盒容器内的 Application Support 目录。
/// token 写在这里是与 RemoteControlServer 相反的方向：那边是沙盒 app 写、外部工具读；
/// 这边是外部进程写、沙盒 app 读。CSRF 防护原理相同——本机浏览器网页读不到本地文件。
const APP_SUPPORT_DIR = join(
  homedir(),
  "Library/Containers/com.gooooloo.XiangqiNotebook/Data/Library/Application Support/XiangqiNotebook",
);
const TOKEN_PATH = join(APP_SUPPORT_DIR, "claude-bridge-token.txt");
/// claude 的工作目录。刻意不用仓库或用户目录：避免 claude 把那里的 CLAUDE.md、
/// .claude/ 配置当成项目上下文混进象棋问答
const CLAUDE_CWD = join(APP_SUPPORT_DIR, "claude-bridge-cwd");

// ---------------------------------------------------------------------------
// claude 可执行文件定位
// ---------------------------------------------------------------------------

/// launchd 环境的 PATH 通常不含 ~/.local/bin，不能只靠 PATH 找
function findClaude() {
  const candidates = [
    join(homedir(), ".local/bin/claude"),
    "/opt/homebrew/bin/claude",
    "/usr/local/bin/claude",
  ];
  for (const path of candidates) {
    if (existsSync(path)) return path;
  }
  return "claude"; // 交给 PATH；找不到时 spawn 报 ENOENT，映射成 CLAUDE_NOT_FOUND
}

const CLAUDE_BIN = findClaude();

// ---------------------------------------------------------------------------
// spawn 参数
// ---------------------------------------------------------------------------

/// 只放行四个象棋 MCP 工具。screenshot 也不给：app 内问棋的工具集就这四个
/// （见 AnalysisToolbox.toolSpecs），两条线路保持同一份语义。
const ALLOWED_TOOLS = [
  "mcp__xiangqi-notebook__get_position",
  "mcp__xiangqi-notebook__evaluate",
  "mcp__xiangqi-notebook__evaluate_move",
  "mcp__xiangqi-notebook__apply_moves",
].join(",");

/// 内置工具全部禁用：问棋不需要文件系统与网络，攻击面越小越好。
/// 主开关是 claudeArgs 里的 `--tools ""`（按白名单语义关掉全部内置工具，MCP 工具不受影响，
/// 已实测）；下面这份黑名单只是对旧版 CLI 的兜底，会随 CLI 升级失效，不要依赖它。
/// headless 下未预批准的工具调用会被直接拒绝并把结果喂回模型，不会挂起等确认。
const DISALLOWED_TOOLS = [
  "Bash", "Read", "Write", "Edit", "Glob", "Grep",
  "WebFetch", "WebSearch", "NotebookEdit", "Task", "TodoWrite",
  "mcp__xiangqi-notebook__screenshot",
].join(",");

function claudeArgs({ systemPrompt, model }) {
  const args = [
    "-p",
    "--output-format", "stream-json",
    "--include-partial-messages",
    "--verbose",
    "--no-session-persistence",
    "--strict-mcp-config",
    "--mcp-config", JSON.stringify({
      mcpServers: {
        "xiangqi-notebook": { command: process.execPath, args: [MCP_SCRIPT] },
      },
    }),
    "--tools", "",
    "--allowedTools", ALLOWED_TOOLS,
    "--disallowedTools", DISALLOWED_TOOLS,
  ];
  if (systemPrompt) args.push("--system-prompt", systemPrompt);
  if (model) args.push("--model", model);
  return args;
}

// ---------------------------------------------------------------------------
// 转录渲染（纯函数）
// ---------------------------------------------------------------------------

/// 多轮对话走无状态重放：app 每次把全部历史发过来，这里渲染成一段文字连同本次
/// 提问经 stdin 交给 claude。不用 --resume 的原因：app 侧 wireMessages 是唯一
/// 真相源，取消/失败后直接剪本地数组即可回滚；有状态 session 会与它漂移。
export function renderPrompt(transcript, question) {
  if (!Array.isArray(transcript) || transcript.length === 0) return question;
  const lines = ["（以下是本轮问棋此前的对话记录，供延续上下文；其中结论可直接引用）", ""];
  for (const turn of transcript) {
    lines.push(turn.role === "assistant" ? "你此前的回答：" : "用户：");
    lines.push(String(turn.text ?? ""));
    lines.push("");
  }
  lines.push("（历史记录结束）现在用户接着问：");
  lines.push(question);
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// claude stream-json → 桥接 NDJSON 事件（纯函数）
// ---------------------------------------------------------------------------

/// 工具结果只做界面留痕，太长没意义还拖慢流
const TOOL_RESULT_PREVIEW_LIMIT = 2000;

/// 把 claude stream-json 的一行转译成 0..n 个桥接事件。
/// 对未知形状一律返回空数组——CLI 升级改了格式时尽量不断流，宁可少显示。
export function translateClaudeLine(obj) {
  switch (obj?.type) {
    case "stream_event": {
      const delta = obj.event?.delta;
      if (obj.event?.type !== "content_block_delta" || !delta) return [];
      if (delta.type === "text_delta" && delta.text) return [{ type: "text", delta: delta.text }];
      if (delta.type === "thinking_delta" && delta.thinking) {
        return [{ type: "thinking", delta: delta.thinking }];
      }
      return [];
    }

    case "assistant": {
      // 登录失效等 API 层错误也以 assistant 消息形态出现（实测 2.1.241）
      if (obj.is_api_error_message || obj.error) {
        const raw = String(obj.error ?? textOfContent(obj.message?.content) ?? "认证或 API 错误");
        const code = raw.includes("authentication") ? "CLAUDE_NOT_LOGGED_IN" : "CLAUDE_FAILED";
        return [{ type: "error", code, message: raw }];
      }
      const blocks = Array.isArray(obj.message?.content) ? obj.message.content : [];
      // 正文与思考走 stream_event 增量，这里只取工具调用
      return blocks
        .filter((block) => block?.type === "tool_use")
        .map((block) => ({
          type: "tool_use",
          id: String(block.id ?? ""),
          name: String(block.name ?? ""),
          input: block.input ?? {},
        }));
    }

    case "user": {
      const blocks = Array.isArray(obj.message?.content) ? obj.message.content : [];
      return blocks
        .filter((block) => block?.type === "tool_result")
        .map((block) => ({
          type: "tool_result",
          id: String(block.tool_use_id ?? ""),
          content: String(textOfContent(block.content) ?? "").slice(0, TOOL_RESULT_PREVIEW_LIMIT),
          isError: block.is_error === true,
        }));
    }

    case "result": {
      if (obj.is_error) {
        // 未登录也走这条路（实测文案 "Not logged in · Please run /login"）
        const raw = String(obj.result ?? obj.error ?? "claude 执行失败");
        const code = /not logged in|login|authentication/i.test(raw)
          ? "CLAUDE_NOT_LOGGED_IN" : "CLAUDE_FAILED";
        return [{ type: "error", code, message: raw }];
      }
      const usage = obj.usage ?? {};
      const input = usage.input_tokens ?? 0;
      const cacheRead = usage.cache_read_input_tokens ?? 0;
      const cacheCreation = usage.cache_creation_input_tokens ?? 0;
      return [{
        type: "done",
        result: String(obj.result ?? ""),
        usage: {
          // app 约定 promptTokens 含缓存部分，而 Anthropic 的 input_tokens 不含，这里补齐
          promptTokens: input + cacheRead + cacheCreation,
          cachedTokens: cacheRead,
          completionTokens: usage.output_tokens ?? 0,
        },
      }];
    }

    default:
      return []; // system/init 等一律忽略
  }
}

/// 从 content（字符串或 content block 数组）里抠出纯文本
function textOfContent(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return null;
  return content
    .filter((block) => block?.type === "text" && typeof block.text === "string")
    .map((block) => block.text)
    .join("\n");
}

// ---------------------------------------------------------------------------
// /chat：spawn claude 并流式转译
// ---------------------------------------------------------------------------

/// 单飞行槽：下游引擎（9214 /eval）本身互斥，多路复用没有意义，
/// 一个槽让取消与 kill 的语义最简单。占用中再来请求直接 409。
let activeChild = null;

function handleChat(payload, res) {
  if (activeChild) {
    res.writeHead(409, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "已有一个问答在进行" }));
    return;
  }
  const question = typeof payload?.question === "string" ? payload.question.trim() : "";
  if (!question) {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "缺少 question 字段" }));
    return;
  }

  mkdirSync(CLAUDE_CWD, { recursive: true });
  let child;
  try {
    child = spawn(CLAUDE_BIN, claudeArgs(payload), {
      cwd: CLAUDE_CWD,
      stdio: ["pipe", "pipe", "pipe"],
    });
  } catch {
    res.writeHead(200, { "Content-Type": "application/x-ndjson" });
    res.end(JSON.stringify({ type: "error", code: "CLAUDE_NOT_FOUND", message: "本机未找到 claude 命令" }) + "\n");
    return;
  }
  activeChild = child;

  res.writeHead(200, {
    "Content-Type": "application/x-ndjson",
    "Cache-Control": "no-store",
  });

  let finished = false; // 已发过 done/error 终结事件
  // 完整 assistant 消息按 content block 逐条出现（实测），同一 tool_use 理论上只出现
  // 一次；这里按 id 去重做保险，重复留痕比漏掉更扰人
  const seenToolUseIds = new Set();
  const emit = (event) => {
    if (res.writableEnded) return;
    if (event.type === "done" || event.type === "error") {
      if (finished) return;
      finished = true;
    }
    if (event.type === "tool_use" && event.id) {
      if (seenToolUseIds.has(event.id)) return;
      seenToolUseIds.add(event.id);
    }
    res.write(JSON.stringify(event) + "\n");
  };

  const heartbeat = setInterval(() => {
    if (!res.writableEnded) res.write(JSON.stringify({ type: "ping" }) + "\n");
  }, HEARTBEAT_MS);

  const hardLimit = setTimeout(() => {
    emit({ type: "error", code: "CLAUDE_FAILED", message: "单次问答超过 10 分钟，已强制终止" });
    kill(child);
  }, RUN_LIMIT_MS);

  let stderrTail = "";
  child.stderr.on("data", (chunk) => {
    stderrTail = (stderrTail + chunk.toString()).slice(-4096);
  });

  createInterface({ input: child.stdout, terminal: false }).on("line", (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    let obj;
    try {
      obj = JSON.parse(trimmed);
    } catch {
      return; // 非 JSON 行（横幅之类）忽略
    }
    for (const event of translateClaudeLine(obj)) emit(event);
  });

  child.on("error", (err) => {
    emit({
      type: "error",
      code: err?.code === "ENOENT" ? "CLAUDE_NOT_FOUND" : "CLAUDE_FAILED",
      message: err?.code === "ENOENT" ? "本机未找到 claude 命令" : String(err?.message ?? err),
    });
    releaseSlot();
    cleanup();
  });

  child.on("close", (code) => {
    if (!finished) {
      emit({
        type: "error",
        code: "CLAUDE_FAILED",
        message: `claude 异常退出（exit ${code}）` + (stderrTail ? `：${stderrTail.trim().slice(-500)}` : ""),
      });
    }
    releaseSlot();
    cleanup();
  });

  // app 侧取消（URLSession 断开）走到这里：立刻杀 claude，引擎那边由 app 自己停。
  // 飞行槽此时不能放：SIGTERM 到 claude 真正退出有最长 5 秒宽限，提前放槽会让下一个
  // /chat 在旧进程还活着时再 spawn 一个，两者去抢 9214 的引擎
  res.on("close", () => {
    if (!res.writableEnded) kill(child);
    cleanup();
  });

  /// 子进程确认退出（close/error）后才释放飞行槽
  function releaseSlot() {
    if (activeChild === child) activeChild = null;
  }

  function cleanup() {
    clearInterval(heartbeat);
    clearTimeout(hardLimit);
    if (!res.writableEnded) res.end();
  }

  child.stdin.end(renderPrompt(payload.transcript, question));
}

function kill(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  setTimeout(() => {
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
  }, KILL_GRACE_MS).unref();
}

// ---------------------------------------------------------------------------
// /health：claude 在不在、登没登录
// ---------------------------------------------------------------------------

function handleHealth(res) {
  execFile(CLAUDE_BIN, ["auth", "status", "--json"], { timeout: 10_000 }, (err, stdout) => {
    const reply = (body) => {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(body));
    };
    if (err && err.code === "ENOENT") {
      reply({ ok: false, code: "CLAUDE_NOT_FOUND", message: "本机未找到 claude 命令" });
      return;
    }
    let status = null;
    try {
      status = JSON.parse(stdout);
    } catch {}
    // 登录态字段名以实测为准，做点防御；退出码非零一律当未登录
    const loggedIn = status?.loggedIn ?? status?.logged_in ?? false;
    if (err || !loggedIn) {
      reply({ ok: false, code: "CLAUDE_NOT_LOGGED_IN", message: "claude 尚未登录" });
      return;
    }
    reply({
      ok: true,
      loggedIn: true,
      subscriptionType: status?.subscriptionType ?? status?.subscription_type ?? null,
    });
  });
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------

const authToken = randomBytes(32).toString("hex");

function writeTokenFile() {
  mkdirSync(APP_SUPPORT_DIR, { recursive: true });
  writeFileSync(TOKEN_PATH, authToken, { mode: 0o600 });
  console.log(`[claude-bridge] 鉴权 token 已写入 ${TOKEN_PATH}`);
}

function readBody(req, limit = 2 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

const server = createServer(async (req, res) => {
  // 与 RemoteControlServer 相同的 CSRF 防线：自定义头 + 本地文件里的随机 token
  if (req.headers[TOKEN_HEADER] !== authToken) {
    res.writeHead(403, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Missing or invalid X-ClaudeBridge-Token header" }));
    return;
  }

  if (req.method === "GET" && req.url === "/health") {
    handleHealth(res);
    return;
  }

  if (req.method === "POST" && req.url === "/chat") {
    let payload;
    try {
      payload = JSON.parse(await readBody(req));
    } catch {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "请求体不是合法 JSON" }));
      return;
    }
    handleChat(payload, res);
    return;
  }

  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "Unknown endpoint" }));
});

// 仅在直接运行时启动（被 import 时只导出纯函数，供测试）
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  writeTokenFile();
  server.listen(PORT, HOST, () => {
    console.log(`[claude-bridge] listening on http://${HOST}:${PORT}（claude: ${CLAUDE_BIN}）`);
  });
}
