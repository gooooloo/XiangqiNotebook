// Codex SDK events → app bridge NDJSON。每轮由 app 重放历史，成功终稿只在 turn.completed 发出。
export function createTranslator() {
  let answer = "";
  const thinking = new Map();
  return (event) => {
    const item = event.item;
    if (event.type === "turn.completed") {
      const u = event.usage ?? {};
      return [{ type: "done", result: answer, usage: {
        promptTokens: u.input_tokens ?? 0,
        cachedTokens: u.cached_input_tokens ?? 0,
        completionTokens: u.output_tokens ?? 0,
      } }];
    }
    // CLI 将可恢复的连接重试也发成 error；让它完成重试，终结失败仍正常报错。
    if (event.type === "error" && /^Reconnecting\.\.\. \d+\/\d+\b/.test(event.message ?? "")) return [];
    if (event.type === "turn.failed" || event.type === "error") {
      return [{ type: "error", code: "CODEX_FAILED", message: event.error?.message ?? event.message ?? "Codex 请求失败" }];
    }
    if (!item) return [];
    if (item.type === "agent_message" && event.type === "item.completed") {
      answer = item.text;
      return [{ type: "text", delta: item.text }];
    }
    if (item.type === "reasoning") {
      const previous = thinking.get(item.id) ?? "";
      const text = item.text ?? "";
      thinking.set(item.id, text);
      return text.length > previous.length ? [{ type: "thinking", delta: text.slice(previous.length) }] : [];
    }
    if (item.type === "mcp_tool_call") {
      if (event.type === "item.started") return [{ type: "tool_use", id: item.id,
        name: `mcp__${item.server}__${item.tool}`, input: item.arguments ?? {} }];
      if (event.type === "item.completed") return [{ type: "tool_result", id: item.id,
        content: (item.result?.structured_content != null
          ? JSON.stringify(item.result.structured_content)
          : item.result?.content?.filter((block) => block.type === "text").map((block) => block.text).join("\n")
            ?? item.error?.message ?? "").slice(0, 2000),
        isError: item.status === "failed" }];
    }
    return [];
  };
}
