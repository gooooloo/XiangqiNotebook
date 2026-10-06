#!/usr/bin/env python3
"""macOS 构建时嵌入独立 helper、Node 和固定版本的 Codex SDK/CLI。"""
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys

if os.environ.get('PLATFORM_NAME') != 'macosx':
    sys.exit(0)
root = pathlib.Path(os.environ['PROJECT_DIR'])
modules = root / 'mcp/node_modules/@openai'
# 构建机装依赖，最终用户无需 npm/Node/Codex。
node_candidates = [os.environ.get('CODEX_NODE_BINARY'), shutil.which('node')]
node_candidates += [str(p) for p in sorted((pathlib.Path.home()/'.nvm/versions/node').glob('*/bin/node'), reverse=True)]
node = None
for candidate in node_candidates:
    if candidate:
        try:
            version = subprocess.check_output([candidate, '--version'], text=True).strip()
            if int(version.lstrip('v').split('.')[0]) >= 20:
                node = pathlib.Path(candidate)
                break
        except (OSError, ValueError, subprocess.CalledProcessError):
            pass
if not node:
    sys.exit('error: 构建 ChatGPT helper 需要 Node 20+；可通过 CODEX_NODE_BINARY 指定构建机 Node 路径。')
if not (modules/'codex-sdk/dist/index.js').exists():
    npm = node.parent/'npm'
    env = dict(os.environ, PATH=str(node.parent)+':'+os.environ.get('PATH',''))
    subprocess.run([str(npm), 'ci', '--prefix', str(root/'mcp')], env=env, check=True)
build_archs = os.environ.get('ARCHS', 'arm64').split()
if len(build_archs) > 1:
    sys.exit('error: ChatGPT runtime 需要按架构打包，请分别用 ARCHS=arm64 或 ARCHS=x86_64 构建。')
arch = 'arm64' if 'arm64' in build_archs else 'x64'
required_node_arch = 'arm64' if arch == 'arm64' else 'x86_64'
if required_node_arch not in subprocess.check_output(['lipo', '-archs', str(node)], text=True).split():
    sys.exit(f'error: Node 架构与 app 不匹配，请用 CODEX_NODE_BINARY 指定 {required_node_arch} Node。')
triple = 'aarch64-apple-darwin' if arch == 'arm64' else 'x86_64-apple-darwin'
native = modules/f'codex-darwin-{arch}'/'vendor'/triple/'bin'
if not (native/'codex').exists():
    sys.exit(f'error: 缺少 {arch} Codex runtime，请在构建机安装对应架构的 @openai/codex-darwin-{arch}。')
app = pathlib.Path(os.environ['TARGET_BUILD_DIR'])/os.environ['CONTENTS_FOLDER_PATH']/'XPCServices/XiangqiCodexHelper.xpc'
resources = app/'Contents/Resources'
(resources/'runtime').mkdir(parents=True, exist_ok=True)
(app/'Contents/MacOS').mkdir(parents=True, exist_ok=True)
identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY') or '-'
inputs = [root/'mcp/package-lock.json', root/'tools/CodexHelper/main.swift', pathlib.Path(__file__)] + list((root/'mcp').glob('*.mjs'))
digest = hashlib.sha256((str(node)+arch+identity).encode())
for path in sorted(inputs):
    digest.update(path.read_bytes())
marker = resources/'build-fingerprint'
if marker.exists() and marker.read_text() == digest.hexdigest():
    sys.exit(0)
for name in ['node']:
    shutil.copy2(node, resources/'runtime'/name)
for name in ['codex', 'codex-code-mode-host']:
    if (native/name).exists(): shutil.copy2(native/name, resources/'runtime'/name)
shutil.copy2(node.resolve().parent.parent/'LICENSE', resources/'runtime/node-LICENSE')
shutil.copy2(modules/'codex-sdk/LICENSE', resources/'runtime/codex-LICENSE')
bridge = resources/'bridge'
bridge.mkdir(exist_ok=True)
for name in ['codex-bridge.mjs', 'codex-worker.mjs', 'codex-launcher.mjs', 'codex-events.mjs', 'xiangqi-notebook-mcp.mjs']:
    shutil.copy2(root/'mcp'/name, bridge/name)
sdk = bridge/'node_modules/@openai/codex-sdk'
sdk.mkdir(parents=True, exist_ok=True)
shutil.copy2(modules/'codex-sdk/package.json', sdk/'package.json')
shutil.copy2(modules/'codex-sdk/LICENSE', sdk/'LICENSE')
shutil.copytree(modules/'codex-sdk/dist', sdk/'dist', dirs_exist_ok=True)
plist = {'CFBundleIdentifier':'com.gooooloo.XiangqiNotebook.CodexHelper', 'CFBundleExecutable':'XiangqiCodexHelper',
         'CFBundleName':'象棋问棋后台', 'CFBundlePackageType':'XPC!', 'CFBundleVersion':'1',
         'CFBundleShortVersionString':'1.0', 'LSMinimumSystemVersion':'15.1',
         'XPCService': {'ServiceType':'Application', 'RunLoopType':'NSRunLoop'},
         'AllowedClientRequirement': 'anchor apple generic and identifier "com.gooooloo.XiangqiNotebook" and certificate leaf[subject.OU] = "'+os.environ.get('DEVELOPMENT_TEAM','')+'"'}
with (app/'Contents/Info.plist').open('wb') as f: plistlib.dump(plist,f)
subprocess.run(['xcrun','swiftc', '-O', '-target', f'{"arm64" if arch == "arm64" else "x86_64"}-apple-macosx15.1',
                str(root/'tools/CodexHelper/main.swift'), '-o',str(app/'Contents/MacOS/XiangqiCodexHelper')], check=True)
# Node 和 Codex 工具宿主的 V8 JIT 需要这些 hardened runtime 权限。
entitlements = resources/'runtime/node.entitlements'
with entitlements.open('wb') as f:
    plistlib.dump({'com.apple.security.cs.allow-jit':True,'com.apple.security.cs.allow-unsigned-executable-memory':True},f)
for binary in (resources/'runtime').iterdir():
    if binary.name not in ['node', 'codex', 'codex-code-mode-host']: continue
    args = ['codesign','--force','--options','runtime','--sign',identity,'--timestamp=none',str(binary)]
    if binary.name in ['node', 'codex-code-mode-host']: args[1:1] = ['--entitlements',str(entitlements)]
    subprocess.run(args,check=True)
marker.write_text(digest.hexdigest())
subprocess.run(['codesign','--force','--options','runtime','--sign',identity,'--timestamp=none',str(app)],check=True)
