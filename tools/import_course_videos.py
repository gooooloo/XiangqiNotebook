#!/usr/bin/env python3
"""
import_course_videos.py — 把 xq_video2pgn.py 识别出的课程棋谱批量导入 app。

前置条件：
  1. 用 xq_video2pgn.py 逐视频识别，得到 <out-dir>/*.meta.json
  2. DEBUG 版 app 正在运行（/import_course 是 DEBUG 专属接口）
  3. 目标课程棋书已在 app 内建好（如 课程/李享堃/半途列炮）

用法：
  python3 import_course_videos.py <out-dir> --book 李享堃 半途列炮

每个视频导入为目标棋书中的一个棋局（多条线路合并为一棵着法树），
并自动关联视频文件路径与各局面的视频时间戳。同名棋局已存在时跳过，可安全重跑。

注意：curl/请求发往 localhost:9214 时须绕过 shell 代理；在 Claude Code
沙箱中运行时需要放行 localhost 网络（或关闭沙箱），否则连接被拒。
"""
import argparse
import glob
import json
import os
import re
import sys
import urllib.request

TOKEN_PATH = os.path.expanduser(
    "~/Library/Containers/com.gooooloo.XiangqiNotebook/Data/"
    "Library/Application Support/XiangqiNotebook/remote-control-token.txt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", help="xq_video2pgn.py 的输出目录（含 *.meta.json）")
    ap.add_argument("--book", nargs="+", required=True,
                    help="课程棋书路径（「课程」之下），如: --book 李享堃 半途列炮")
    ap.add_argument("--name", default=None,
                    help="短名前缀：棋局命名为 <前缀>-<编号>（编号取视频文件名开头数字），"
                         "如 --name 李-半途列炮 → 李-半途列炮-001。省略则用完整文件名")
    args = ap.parse_args()

    token = open(TOKEN_PATH).read().strip()
    metas = sorted(glob.glob(os.path.join(args.out_dir, "*.meta.json")))
    if not metas:
        sys.exit(f"{args.out_dir} 下没有 meta.json")

    failures = 0
    for path in metas:
        meta = json.load(open(path))
        base = os.path.basename(path).replace(".meta.json", "")
        if args.name:
            m = re.match(r"(\d+)", base)
            if not m:
                print(f"{base[:20]:22s} ✗ 文件名无编号前缀，无法用 --name 命名")
                failures += 1
                continue
            name = f"{args.name}-{m.group(1)}"
        else:
            name = base
        payload = {
            "bookPath": args.book,
            "name": name,
            "videoPath": meta["video"],
            "lines": [
                {"startFen": g["start_fen"],
                 "moves": [p["move"] for p in g["plies"]],
                 "times": [p["t"] for p in g["plies"]]}
                for g in meta["games"]
            ],
        }
        # 服务端 NWListener 只在 IPv6 上可达：连 127.0.0.1 会挂起，必须用 [::1]
        req = urllib.request.Request(
            "http://[::1]:9214/import_course",
            data=json.dumps(payload, ensure_ascii=False).encode(),
            headers={"X-RemoteControl-Token": token,
                     "Content-Type": "application/json"})
        # 本机直连，绕开环境里的 HTTP 代理
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            resp = json.load(opener.open(req, timeout=120))
        except OSError as e:
            print(f"{name[:20]:22s} 请求失败: {e}")
            failures += 1
            continue
        if resp.get("ok"):
            print(f"{name[:20]:22s} ✓ 线路 {resp['lines']:2d} 着法 {resp['moves']:3d} "
                  f"时间戳 {resp['timestamps']}")
        else:
            print(f"{name[:20]:22s} ✗ {resp.get('error')}")
            failures += 1
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
