# iOS ChatGPT 订阅验证

2026-10-08：已接入正式问棋。手机复用原有钥匙串登录，通过 Responses 调用本地皮卡鱼工具并支持追问。Mac 原有 Codex SDK / XPC 线路保留。

## 官方依据

- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://auth.openai.com/.well-known/openid-configuration

官方允许 OSS / locally hosted 客户端动态登记，无 client secret / API key。要求 HTTP `127.0.0.1` `/auth/callback` 回调、PKCE S256、state、nonce、issued client ID、验证 ID token 签名及 `chatgpt.tokens.use.direct` scope。公开推理端点为 `https://api.openai.com/v1/responses`，必须 `store:false`、`stream:true`，并等待 `response.completed`。

本实现使用 SFSafariViewController 系统 Safari 页面，手机进程使用 NWListener，仅绑定 127.0.0.1 动态端口；没有 WKWebView、私有 backend-api、假冒客户端、外置 CLI 或 Mac 中转。系统 Safari 页面能否完成这次 OAuth loopback 回调必须实际验证，官方 OpenAI 文档未明确保证 iOS 支持。

## 真机操作

1. 在 Xcode 选择已连接并解锁、开启开发者模式的 iPhone，安装运行 XiangqiNotebook。
2. 打开问棋的 AI 设置，选择「ChatGPT（订阅）」→「ChatGPT 登录与连接测试」。
3. 确认模型 `gpt-6.1-sol`、reasoning effort `low`，点击 `Continue with ChatGPT`。
4. 用户本人在系统 Safari 页面登录、审阅并授权订阅使用。最多等待 180 秒，可取消。
5. 回调、交换 token 和身份校验成功后，登录按钮置灰。点击「获取一句回答」。收到完整回答后，返回 AI 设置并点击「完成」，回到问棋输入问题，例如「分析当前局面」。
6. 记录实际失败的阶段、HTTP 状态、公开错误码或 Safari 的回调错误；不要记录 token、code、完整 callback URL 或密码。

凭据存手机 ThisDeviceOnly 钥匙串；刷新串行执行并整体替换 rotating refresh token。当前验证入口仅保存一个账号登记，问棋使用同一份凭据；暂不提供完整多账号管理。返回账号必须匹配已验证 subject/client ID。失效凭据需要重新登录，推理前支持刷新。登录/测试取消及超时均停止任务。

## 验证边界及后续

- 模拟器编译不能证明真机 OAuth、账户授权、Pro 额度或云端推理已成功。
- 已接入 `LLMClientFactory` 和现有 `AnalysisToolbox`，由手机本地皮卡鱼执行工具。原始 Responses output（含加密推理内容）保留在对话内存中，随工具结果回传，清空对话或取消回滚时一并清理。
- 订阅 Responses 的工具需放 namespace 或 additional_tools，不能直接照搬 Chat Completions tools；完整历史放 input，HTTP 不使用 previous_response_id；instructions/developer 替代 explicit system item。
- 不自动转收费 API key 方案。固定请求 gpt-6.1-sol；账号不支持或拒绝请求时显示错误，不替换模型。

## 已完成的本地检查（2026-10-07）

- iOS Simulator app 构建通过。
- macOS app 构建通过。
- iOS 模拟器独立测试两项通过：真实 HTTP loopback + state/拒绝授权；RSA token 验签 + nonce/audience/issuer/expiry/nbf/篡改拒绝。
- 标准 iOS test 命令被既有 PikafishServiceTests、PikafishServiceIOSTests 等编译问题阻挡。独立命令使用临时 EXCLUDED_SOURCE_FILE_NAMES，不改存量测试或项目配置：

```sh
python3 tools/test-ios-subscription-probe.py --destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

2026-10-08 用户已提供手机登录成功截图。正式问棋的真实订阅推理与引擎循环仍需在安装新版后验证。

## 问棋接入检查（2026-10-08）

- iOS Simulator 与 macOS app 构建通过。
- 订阅测试覆盖真实 loopback 拒绝授权、ID token 验签、namespace 工具请求及结果/加密推理上下文回传、完整回答与无效输出拒绝。
- 正式问棋和连接测试使用同一个 Responses 客户端，固定 gpt-6.1-sol，思考力度由 AI 设置保存；过期 access token 自动刷新，刷新请求合并避免重复使用 rotating refresh token。
- 以上检查不包含用户真实账号的云端问棋；需要安装新版后在 iPhone 验证。
