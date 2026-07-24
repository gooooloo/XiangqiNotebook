#!/usr/bin/env node
// 象棋笔记本 MCP server（stdio）
//
// 一个零依赖的薄桥：把 MCP tool 调用翻译成对 XiangqiNotebook 远程操控
// HTTP 服务（localhost:9214，仅 DEBUG 构建）的请求。
//
// 注册到 Claude Code:
//   claude mcp add xiangqi-notebook -- node /Users/qidu/dev/XiangqiNotebook/mcp/xiangqi-notebook-mcp.mjs
// 注册到 Claude Desktop（claude_desktop_config.json）:
//   { "mcpServers": { "xiangqi-notebook": { "command": "node",
//     "args": ["/Users/qidu/dev/XiangqiNotebook/mcp/xiangqi-notebook-mcp.mjs"] } } }
//
// 要求 Node >= 18（内建 fetch）。

import { createInterface } from "node:readline";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

// 本机可能设了 HTTP(S)_PROXY（如 v2ray），会劫持发往 localhost 的 fetch 导致连不上。
// MCP server 由 GUI（Claude Desktop）启动时会继承这些环境变量，故在此显式清除——
// 本进程只跟 localhost:9214 通信，不需要任何代理。
for (const key of ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy"]) {
  delete process.env[key];
}

const BASE_URL = "http://localhost:9214";
// App Sandbox 容器内路径；token 每次 app 启动都会变，所以每个请求都重新读
const TOKEN_PATH = join(
  homedir(),
  "Library/Containers/com.gooooloo.XiangqiNotebook/Data/Library/Application Support/XiangqiNotebook/remote-control-token.txt",
);

const SERVER_INFO = { name: "xiangqi-notebook", version: "1.0.0" };

// ---------------------------------------------------------------------------
// HTTP 桥
// ---------------------------------------------------------------------------

async function readToken() {
  try {
    return (await readFile(TOKEN_PATH, "utf8")).trim();
  } catch {
    throw new Error(
      "读不到远程操控 token 文件。请确认象棋笔记本（DEBUG 构建）正在运行。",
    );
  }
}

async function api(path, { method = "GET", body, binary = false } = {}) {
  const token = await readToken();
  let res;
  try {
    res = await fetch(BASE_URL + path, {
      method,
      headers: { "X-RemoteControl-Token": token },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new Error(
      "连不上象棋笔记本（localhost:9214）。请确认 app（DEBUG 构建）正在运行。",
    );
  }
  if (binary) {
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return Buffer.from(await res.arrayBuffer());
  }
  const text = await res.text();
  if (!res.ok) {
    let message = text;
    try {
      message = JSON.parse(text).error ?? text;
    } catch {}
    throw new Error(`HTTP ${res.status}: ${message}`);
  }
  return text;
}

// ---------------------------------------------------------------------------
// 工具定义
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "get_position",
    description:
      "获取象棋笔记本 app 当前打开的局面。返回 JSON：fen（局面，格式为「棋盘 r|b」，r=红方走）、" +
      "step/maxStep（步数）、comment/moveComment（用户笔记）、score（云库分）、engineScore（引擎分）、" +
      "nextMoves（笔记本中记录的后续着法，中文）、variants（本步其他变着）等。" +
      "用户问「当前局面 / 这一步」时先调用它。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "evaluate",
    description:
      "用本地皮卡鱼（Pikafish）引擎对局面做 MultiPV 分析，返回前 N 条候选着法线路，" +
      "每条含 scoreCp（厘兵分，【走子方视角】，正=走子方优；杀棋折算为 ±30000 附近）、depth、" +
      "pvUci（UCI 着法序列）、pvChinese（中文着法序列）。" +
      "省略 fen 则分析 app 当前局面。分析耗时约 movetime_ms 毫秒。" +
      "对比两个着法优劣的方法：本工具的候选列表若同时包含两者可直接对比；" +
      "否则先用 apply_moves 走出目标着法得到新 fen，再对新 fen 调用本工具" +
      "（注意新局面轮对方走，分数视角随之翻转）。",
    inputSchema: {
      type: "object",
      properties: {
        fen: {
          type: "string",
          description:
            "要分析的局面，格式「棋盘 r|b」（如 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r'）。省略则用 app 当前局面",
        },
        multipv: {
          type: "integer",
          description: "返回的候选线路数，1-10，默认 3",
        },
        movetime_ms: {
          type: "integer",
          description: "引擎思考时间（毫秒），500-60000，默认 5000。要更深的结论用 10000+",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "apply_moves",
    description:
      "把一串 UCI 着法（如 ['h2e2','h9g7']）依次应用到局面上，返回每步的中文着法名和走完后的 fen。" +
      "用于沿着引擎给出的变化（pvUci）或假想着法往下走，再把 finalFen 交给 evaluate 分析。" +
      "坐标系：列 a-i 从红方左侧起，行 0-9 从红方底线起（如 h2e2 = 炮二平五）。" +
      "注意：只做机械移动（起点须有子），不校验象棋规则，调用方需保证着法合理。",
    inputSchema: {
      type: "object",
      properties: {
        fen: { type: "string", description: "起始局面，格式「棋盘 r|b」" },
        moves: {
          type: "array",
          items: { type: "string" },
          description: "UCI 着法序列，按走棋顺序（红黑交替）",
        },
      },
      required: ["fen", "moves"],
      additionalProperties: false,
    },
  },
  {
    name: "screenshot",
    description: "截取象棋笔记本 app 当前窗口的截图（PNG），用于直观查看棋盘和界面状态。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
];

async function callTool(name, args = {}) {
  switch (name) {
    case "get_position":
      return textContent(await api("/state"));

    case "evaluate": {
      const body = {};
      if (args.fen !== undefined) body.fen = args.fen;
      if (args.multipv !== undefined) body.multipv = args.multipv;
      if (args.movetime_ms !== undefined) body.movetime = args.movetime_ms;
      return textContent(await api("/eval", { method: "POST", body }));
    }

    case "apply_moves":
      return textContent(
        await api("/apply", {
          method: "POST",
          body: { fen: args.fen, moves: args.moves },
        }),
      );

    case "screenshot": {
      const png = await api("/screenshot", { binary: true });
      return {
        content: [
          { type: "image", data: png.toString("base64"), mimeType: "image/png" },
        ],
      };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

function textContent(text) {
  return { content: [{ type: "text", text }] };
}

// ---------------------------------------------------------------------------
// JSON-RPC over stdio（MCP stdio transport：每行一条 JSON 消息）
// ---------------------------------------------------------------------------

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

function sendResult(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function sendError(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

async function handleRequest(req) {
  const { id, method, params } = req;
  switch (method) {
    case "initialize":
      sendResult(id, {
        protocolVersion: params?.protocolVersion ?? "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: SERVER_INFO,
      });
      break;

    case "ping":
      sendResult(id, {});
      break;

    case "tools/list":
      sendResult(id, { tools: TOOLS });
      break;

    case "tools/call": {
      try {
        const result = await callTool(params?.name, params?.arguments);
        sendResult(id, result);
      } catch (err) {
        // 工具执行失败按 MCP 规范返回 isError 内容，而不是协议层错误
        sendResult(id, {
          content: [{ type: "text", text: String(err?.message ?? err) }],
          isError: true,
        });
      }
      break;
    }

    default:
      sendError(id, -32601, `Method not found: ${method}`);
  }
}

const rl = createInterface({ input: process.stdin, terminal: false });
rl.on("line", (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let req;
  try {
    req = JSON.parse(trimmed);
  } catch {
    return; // 非法 JSON 直接忽略
  }
  if (req.id === undefined || req.id === null) return; // notification，无需响应
  handleRequest(req).catch((err) => {
    sendError(req.id, -32603, String(err?.message ?? err));
  });
});
// stdin 关闭后不强退：让在飞的 tools/call 完成、事件循环自然排空后进程自行退出
