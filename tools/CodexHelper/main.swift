import Foundation
import Darwin
import XPC
import CFNetwork

@objc protocol CodexHelperProtocol {
    func start(bridgeToken: String, remoteToken: String, reply: @escaping (String?) -> Void)
}

/// 私有 XPC 服务。双方验证代码签名后才传递 localhost token，不开放网络初始化入口。
final class Helper: NSObject, NSXPCListenerDelegate, CodexHelperProtocol {
    private var bridge: Process?
    private var bridgeToken = ""
    private var clients = 0

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        guard let requirement = Bundle.main.object(forInfoDictionaryKey: "AllowedClientRequirement") as? String else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: CodexHelperProtocol.self)
        connection.exportedObject = self
        DispatchQueue.main.async { self.clients += 1 }
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.clients -= 1
                if self.clients == 0 { self.bridge?.terminate() }
            }
        }
        connection.resume()
        return true
    }

    func start(bridgeToken: String, remoteToken: String, reply: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            let resolvedProxy = systemProxy()
            DispatchQueue.main.async {
                if let bridge = self.bridge, bridge.isRunning {
                    reply(self.bridgeToken == bridgeToken ? nil : "后台连接已失效，请退出 app 后重试。")
                    return
                }
                guard bridgeToken.count >= 64, !remoteToken.isEmpty, let resources = Bundle.main.resourceURL else {
                    reply("ChatGPT 组件初始化信息不完整。"); return
                }
                let process = Process()
                process.executableURL = resources.appendingPathComponent("runtime/node")
                process.arguments = [resources.appendingPathComponent("bridge/codex-bridge.mjs").path]
                process.currentDirectoryURL = resources
                var env = ProcessInfo.processInfo.environment
                if let account = getpwuid(getuid()) { env["HOME"] = String(cString: account.pointee.pw_dir) }
                env["CODEX_BRIDGE_MANAGED"] = "1"
                env["CODEX_BRIDGE_TOKEN"] = bridgeToken
                env["XIANGQI_REMOTE_TOKEN"] = remoteToken
                env["CODEX_PATH"] = resources.appendingPathComponent("runtime/codex").path
                env["PATH"] = resources.appendingPathComponent("runtime").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
                if let resolvedProxy {
                    if env["HTTPS_PROXY"] == nil { env["HTTPS_PROXY"] = resolvedProxy }
                    if env["HTTP_PROXY"] == nil { env["HTTP_PROXY"] = resolvedProxy }
                }
                env["NO_PROXY"] = "localhost,127.0.0.1,::1"
                process.environment = env
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    process.terminationHandler = { _ in xpc_transaction_end() }
                    xpc_transaction_begin()
                    do { try process.run() }
                    catch { xpc_transaction_end(); throw error }
                    self.bridge = process
                    self.bridgeToken = bridgeToken
                    reply(nil)
                } catch { reply("无法启动 app 内的 ChatGPT 运行组件：\(error.localizedDescription)") }
            }
        }
    }
}
// CLI 不读取 macOS PAC 设置；用系统 API 解析 ChatGPT 域名后显式传给它。
private final class ProxyResolution {
    var proxies: [[String: Any]] = []
    var finished = false
}
private func systemProxy() -> String? {
    guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
          let target = URL(string: "https://chatgpt.com"),
          var proxies = CFNetworkCopyProxiesForURL(target as CFURL, settings).takeRetainedValue() as? [[String: Any]] else { return nil }
    if let pac = proxies.first,
       pac[kCFProxyTypeKey as String] as? String == kCFProxyTypeAutoConfigurationURL as String,
       let url = pac[kCFProxyAutoConfigurationURLKey as String] as? URL {
        let state = ProxyResolution()
        var context = CFStreamClientContext(version: 0, info: Unmanaged.passUnretained(state).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let source = CFNetworkExecuteProxyAutoConfigurationURL(url as CFURL, target as CFURL, { info, list, _ in
            let state = Unmanaged<ProxyResolution>.fromOpaque(info).takeUnretainedValue()
            state.proxies = list as? [[String: Any]] ?? []
            state.finished = true
        }, &context)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        let deadline = Date().addingTimeInterval(5)
        while !state.finished && Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.1, true) }
        CFRunLoopSourceInvalidate(source)
        proxies = state.proxies
    }
    guard let proxy = proxies.first,
          let type = proxy[kCFProxyTypeKey as String] as? String,
          let host = proxy[kCFProxyHostNameKey as String] as? String,
          let port = proxy[kCFProxyPortNumberKey as String] as? Int else { return nil }
    let scheme: String
    if type == (kCFProxyTypeHTTP as String) || type == (kCFProxyTypeHTTPS as String) { scheme = "http" }
    else if type == (kCFProxyTypeSOCKS as String) { scheme = "socks5h" }
    else { return nil }
    let address = host.contains(":") ? "[\(host)]" : host
    return "\(scheme)://\(address):\(port)"
}
let helper = Helper()
let listener = NSXPCListener.service()
listener.delegate = helper
listener.resume()
RunLoop.current.run()
