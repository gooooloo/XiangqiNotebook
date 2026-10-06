// 独立 worker 便于取消时终止 SDK 及其 CLI/MCP 子进程。
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { renderPrompt } from "./codex-bridge.mjs";
import { createTranslator } from "./codex-events.mjs";

const emit = (event) => process.stdout.write(JSON.stringify(event) + "\n");
try {
  let raw = "";
  for await (const chunk of process.stdin) raw += chunk;
  const payload = JSON.parse(raw);
  const bin = process.env.XIANGQI_CODEX_BIN;
  if (!payload.model?.trim() || !["low", "medium", "high", "xhigh", "max"].includes(payload.reasoningEffort)) {
    throw new Error("请在 AI 设置中明确选择模型和 reasoning effort。");
  }
  // 此线路明确使用订阅；API-key 登录不能悄悄切成按量付费。
  const login = spawnSync(bin, ["login", "status"], { encoding: "utf8", timeout: 10000 });
  if (login.status !== 0 || !/logged in using chatgpt/i.test(login.stdout + login.stderr)) {
    emit({ type: "error", code: login.error?.code === "ENOENT" ? "CODEX_NOT_FOUND" : "CODEX_NOT_LOGGED_IN", message: "请在 app 的 AI 设置中点击“登录 ChatGPT”" });
    process.exit(0);
  }
  const { Codex } = await import("@openai/codex-sdk");
  const env = { ...process.env, PATH: `${dirname(process.execPath)}:${process.env.PATH ?? ""}` };
  delete env.OPENAI_API_KEY;
  delete env.CODEX_API_KEY;
  const codex = new Codex({ codexPathOverride: join(dirname(fileURLToPath(import.meta.url)), "codex-launcher.mjs"), env, config: {
    forced_login_method: "chatgpt",
    project_doc_max_bytes: 0,
    developer_instructions: payload.systemPrompt ?? "请用中文回答象棋问题。",
    features: { shell_tool: false },
    mcp_servers: { "xiangqi-notebook": {
      command: process.execPath, args: [payload.mcpScript],
      env_vars: ["XIANGQI_REMOTE_TOKEN"],
      default_tools_approval_mode: "approve",
      enabled_tools: ["get_position", "evaluate", "evaluate_move", "apply_moves"],
    } },
  } });
  const thread = codex.startThread({
    workingDirectory: process.cwd(), skipGitRepoCheck: true,
    sandboxMode: "read-only", approvalPolicy: "never", webSearchMode: "disabled",
    model: payload.model.trim(), modelReasoningEffort: payload.reasoningEffort,
  });
  const translate = createTranslator();
  const { events } = await thread.runStreamed(renderPrompt(payload.transcript, payload.question));
  for await (const event of events) for (const output of translate(event)) emit(output);
} catch (error) {
  emit({ type: "error", code: error.code === "ERR_MODULE_NOT_FOUND" ? "CODEX_NOT_FOUND" : "CODEX_FAILED", message: error.message });
}
