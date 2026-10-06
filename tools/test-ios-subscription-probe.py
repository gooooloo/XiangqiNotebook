#!/usr/bin/env python3
"""仅运行订阅验证测试；临时排除仓库目前无法在 iOS 编译的其他测试文件。"""
import argparse
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--destination', default='platform=iOS Simulator,name=iPhone 17 Pro')
parser.add_argument('--derived-data', default='/tmp/xiangqi-siwc-build')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
excluded = ' '.join(p.name for p in (root / 'XiangqiNotebookTests').glob('*.swift')
                    if p.name != 'ChatGPTSubscriptionProbeTests.swift')
raise SystemExit(subprocess.call([
    'xcodebuild', 'test', '-project', 'XiangqiNotebook.xcodeproj', '-scheme', 'XiangqiNotebook',
    '-destination', args.destination, '-derivedDataPath', args.derived_data,
    'CODE_SIGNING_ALLOWED=NO', 'EXCLUDED_SOURCE_FILE_NAMES=' + excluded,
    '-only-testing:XiangqiNotebookTests/ChatGPTSubscriptionProbeTests',
], cwd=root))
