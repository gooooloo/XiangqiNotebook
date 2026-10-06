#!/usr/bin/env node
// ChatGPT 订阅桥接：HTTP → 独立 Codex SDK worker → 象棋 MCP。
import { createServer } from "node:http";
import { spawn, execFile } from "node:child_process";
import { randomBytes } from "node:crypto";
import { createInterface } from "node:readline";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PORT = 9217;
const HOST = "127.0.0.1";
const TOKEN_HEADER = "x-codexbridge-token";
/// 心跳间隔：codex 冷启动 + MCP 初始化可能十几秒无事件，而 app 侧片间超时 180 秒，
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
const APP_SUPPORT_DIR = process.env.CODEX_BRIDGE_MANAGED === "1"
  ? join(homedir(), "Library/Application Support/XiangqiNotebook/CodexHelper")
  : join(
  homedir(),
  "Library/Containers/com.gooooloo.XiangqiNotebook/Data/Library/Application Support/XiangqiNotebook",
);
const TOKEN_PATH = join(APP_SUPPORT_DIR, "codex-bridge-token.txt");
/// codex 的工作目录。刻意不用仓库或用户目录：避免 codex 把那里的 AGENTS.md、
/// .codex/ 配置当成项目上下文混进象棋问答
const CODEX_CWD = join(APP_SUPPORT_DIR, "codex-bridge-cwd");

// ---------------------------------------------------------------------------
// codex 可执行文件定位
// ---------------------------------------------------------------------------

/// launchd 环境的 PATH 通常不含 ~/.local/bin，不能只靠 PATH 找
function findCodex() {
  if (process.env.CODEX_PATH) return process.env.CODEX_PATH;
  const candidates = [
    "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
    join(homedir(), ".local/bin/codex"),
    "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
  ];
  return candidates.find((path) => existsSync(path)) ?? "codex";
}
const CODEX_BIN = findCodex();

// ---------------------------------------------------------------------------
// 转录渲染（纯函数）
// ---------------------------------------------------------------------------

/// 多轮对话走无状态重放：app 每次把全部历史发过来，这里渲染成一段文字连同本次
/// 提问经 stdin 交给 codex。不用 --resume 的原因：app 侧 wireMessages 是唯一
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

// /chat：spawn codex 并流式转译
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

  mkdirSync(CODEX_CWD, { recursive: true });
  let child;
  try {
    child = spawn(process.execPath, [join(SCRIPT_DIR, "codex-worker.mjs")], {
      cwd: CODEX_CWD,
      detached: true,
      env: { ...process.env, XIANGQI_CODEX_BIN: CODEX_BIN },
      stdio: ["pipe", "pipe", "pipe"],
    });
  } catch {
    res.writeHead(200, { "Content-Type": "application/x-ndjson" });
    res.end(JSON.stringify({ type: "error", code: "CODEX_NOT_FOUND", message: "本机未找到 codex 命令" }) + "\n");
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
    emit({ type: "error", code: "CODEX_FAILED", message: "单次问答超过 10 分钟，已强制终止" });
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
    emit(obj);
  });

  child.on("error", (err) => {
    emit({
      type: "error",
      code: err?.code === "ENOENT" ? "CODEX_NOT_FOUND" : "CODEX_FAILED",
      message: err?.code === "ENOENT" ? "本机未找到 codex 命令" : String(err?.message ?? err),
    });
    releaseSlot();
    cleanup();
  });

  child.on("close", (code) => {
    if (!finished) {
      emit({
        type: "error",
        code: "CODEX_FAILED",
        message: `codex 异常退出（exit ${code}）` + (stderrTail ? `：${stderrTail.trim().slice(-500)}` : ""),
      });
    }
    releaseSlot();
    cleanup();
  });

  // app 侧取消（URLSession 断开）走到这里：立刻杀 codex，引擎那边由 app 自己停。
  // 飞行槽此时不能放：SIGTERM 到 codex 真正退出有最长 5 秒宽限，提前放槽会让下一个
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

  child.stdin.end(JSON.stringify({ ...payload, question, mcpScript: MCP_SCRIPT }));
}

function kill(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  try { process.kill(-child.pid, "SIGTERM"); } catch {}
  setTimeout(() => {
    if (child.exitCode === null && child.signalCode === null) {
      try { process.kill(-child.pid, "SIGKILL"); } catch {}
    }
  }, KILL_GRACE_MS).unref();
}

// ---------------------------------------------------------------------------
// /health：codex 在不在、登没登录
// ---------------------------------------------------------------------------

function handleHealth(res) {
  execFile(CODEX_BIN, ["login", "status"], { timeout: 10_000 }, (err, stdout, stderr) => {
    const chatGPT = !err && /logged in using chatgpt/i.test(stdout + stderr);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(chatGPT ? { ok: true, loggedIn: true } : {
      ok: false,
      code: err?.code === "ENOENT" ? "CODEX_NOT_FOUND" : "CODEX_NOT_LOGGED_IN",
      message: "请在 app 的 AI 设置中点击“登录 ChatGPT”。",
    }));
  });
}

// app 内的浏览器登录，不把凭据传回 app；仍由 Codex 自己存储和刷新。
let loginChild = null;
let loginState = { state: "idle" };
function handleLogin(res) {
  if (!loginChild) {
    loginState = { state: "pending" };
    const child = spawn(CODEX_BIN, ["login"], { stdio: ["ignore", "ignore", "pipe"], detached: true });
    loginChild = child;
    let errorTail = "";
    child.stderr.on("data", (chunk) => { errorTail = (errorTail + chunk.toString()).slice(-1000); });
    const timeout = setTimeout(() => {
      loginState = { state: "failed", message: "登录超时，请重新点击登录 ChatGPT。" };
      kill(child);
    }, 5 * 60 * 1000);
    child.on("error", () => {
      clearTimeout(timeout);
      loginState = { state: "failed", message: "无法启动 app 内的 ChatGPT 登录组件。" };
      loginChild = null;
    });
    child.on("close", (code) => {
      clearTimeout(timeout);
      if (loginState.state === "pending") loginState = code === 0
        ? { state: "completed" }
        : { state: "failed", message: /address already in use/i.test(errorTail)
            ? "其他程序正在登录 ChatGPT，请完成该登录后重试。" : "ChatGPT 登录未完成，请重试。" };
      loginChild = null;
    });
  }
  res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  res.end(JSON.stringify(loginState));
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------

const authToken = process.env.CODEX_BRIDGE_TOKEN || randomBytes(32).toString("hex");

function writeTokenFile() {
  if (process.env.CODEX_BRIDGE_MANAGED === "1") return;
  mkdirSync(APP_SUPPORT_DIR, { recursive: true });
  writeFileSync(TOKEN_PATH, authToken, { mode: 0o600 });
  console.log(`[codex-bridge] 鉴权 token 已写入 ${TOKEN_PATH}`);
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
    res.end(JSON.stringify({ error: "Missing or invalid X-CodexBridge-Token header" }));
    return;
  }

  if (req.method === "POST" && req.url === "/configure") {
    try {
      const payload = JSON.parse(await readBody(req, 4096));
      if (typeof payload.remoteToken !== "string" || !payload.remoteToken.trim()) throw new Error();
      process.env.XIANGQI_REMOTE_TOKEN = payload.remoteToken.trim();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    } catch {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "缺少 app 分析接口鉴权信息" }));
    }
    return;
  }

  if (req.method === "GET" && req.url === "/ready") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true }));
    return;
  }
  if (req.method === "POST" && req.url === "/login") {
    handleLogin(res);
    return;
  }
  if (req.method === "GET" && req.url === "/login-status") {
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    res.end(JSON.stringify(loginState));
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

// 仅直接运行时启动，XPC 服务退出后清理后台与 SDK 子进程。
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const shutdown = () => {
    if (activeChild) kill(activeChild);
    if (loginChild) kill(loginChild);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), KILL_GRACE_MS + 200).unref();
  };
  for (const signal of ["SIGTERM", "SIGINT"]) process.on(signal, shutdown);
  if (process.env.CODEX_BRIDGE_MANAGED === "1") {
    const owner = process.ppid;
    setInterval(() => {
      try { process.kill(owner, 0); } catch { shutdown(); }
    }, 2000).unref();
  }
  server.listen(PORT, HOST, () => {
    writeTokenFile();
    console.log(`[codex-bridge] listening on http://${HOST}:${PORT}（codex: ${CODEX_BIN}）`);
  });
}
