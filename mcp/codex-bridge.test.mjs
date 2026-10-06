import test from "node:test";
import assert from "node:assert/strict";
import { createTranslator } from "./codex-events.mjs";

test("MCP 开始与结束使用同一 id，保留工具参数与结果", () => {
  const translate = createTranslator();
  const item = { id: "tool-1", type: "mcp_tool_call", server: "xiangqi-notebook", tool: "evaluate_move", arguments: { move: "炮二平五" } };
  assert.equal(translate({ type: "item.started", item })[0].name, "mcp__xiangqi-notebook__evaluate_move");
  const result = translate({ type: "item.completed", item: { ...item, status: "failed", error: { message: "引擎忙" } } })[0];
  assert.equal(result.id, item.id);
  assert.equal(result.isError, true);
  assert.match(result.content, /引擎忙/);
});

test("最终回答只在成功完成后发出，用量不重复加缓存", () => {
  const translate = createTranslator();
  translate({ type: "item.completed", item: { type: "agent_message", text: "正确应对" } });
  const done = translate({ type: "turn.completed", usage: { input_tokens: 100, cached_input_tokens: 80, output_tokens: 20 } })[0];
  assert.equal(done.result, "正确应对");
  assert.deepEqual(done.usage, { promptTokens: 100, cachedTokens: 80, completionTokens: 20 });
});

test("失败不会把已收到的文字当作成功回答；思考更新不重复", () => {
  const translate = createTranslator();
  const item = { id: "r", type: "reasoning", text: "先分析" };
  assert.equal(translate({ type: "item.updated", item })[0].delta, "先分析");
  assert.deepEqual(translate({ type: "item.completed", item }), []);
  assert.equal(translate({ type: "turn.failed", error: { message: "额度已用完" } })[0].type, "error");
});

test("连接重试不会提前结束问棋，最终失败仍报告", () => {
  const translate = createTranslator();
  assert.deepEqual(translate({ type: "error", message: "Reconnecting... 2/5 (workspace routing discovery timed out)" }), []);
  assert.equal(translate({ type: "error", message: "额度不足" })[0].type, "error");
  assert.equal(translate({ type: "turn.failed", error: { message: "网络超时" } })[0].message, "网络超时");
});
