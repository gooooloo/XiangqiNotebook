#!/usr/bin/env node
// SDK 没有 ignore-user-config / ephemeral 选项，启动时补齐，保留原有登录凭据。
import { spawn } from "node:child_process";
const args = process.argv.slice(2);
if (args[0] === "exec") args.splice(1, 0, "--ignore-user-config", "--ignore-rules", "--ephemeral");
const child = spawn(process.env.XIANGQI_CODEX_BIN, args, { stdio: "inherit" });
child.on("error", (error) => { console.error(error.message); process.exitCode = 1; });
child.on("exit", (code) => { process.exitCode = code ?? 1; });
