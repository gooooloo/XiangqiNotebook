#!/usr/bin/env python3
"""
xq_video2pgn.py — 从象棋讲课视频（软件棋盘录屏）识别棋谱，导出 XiangqiNotebook 可导入的 PGN。

零第三方依赖：ffmpeg 输出 rawvideo RGB24 像素流，纯 Python 做模板匹配。

流程：
  1. 标定：在视频开头找一帧标准开局局面，检测 32 个棋子白色圆底 → 拟合 9x10 网格，
     并从已知初始摆放裁出全部 14 种棋子字形模板。
  2. 逐帧（默认 4fps）扫描 90 个交叉点的占用/颜色，连续 2 帧一致视为稳定局面。
  3. 相邻稳定局面 diff 出着法（含吃子），走法合法性校验；讲课中的回退/变着形成棋谱树。
  4. 树上每条根到叶路径导出为一局（多局共享前缀，app 导入时图结构自动合并），
     并输出每步的视频时间戳（供课程视频关联使用）。

用法： python3 xq_video2pgn.py <video.mp4> [--fps 4] [--out-dir out]
"""
import argparse
import json
import os
import subprocess
import sys

# ---------------------------------------------------------------- 常量与几何

FRAME_W, FRAME_H = 1280, 720

# 颜色阈值（由 probe.py 实测：白底~217，背景 min~153，红字 r-g~100，黑字 ~49）
WHITE_MIN = 170          # min(r,g,b) >= 170 → 棋子白底
RED_R, RED_DIFF = 170, 50  # r>=170 且 r-g、r-b >= 50 → 红字形
BLACK_MAX = 130          # max(r,g,b) <= 130 → 黑字形
COLOR_MIN_FRAC = 0.04    # 字形像素最低占比（低于则该格颜色不确定）


def is_occupied(nw, nr, nb, n):
    """字形密的棋子（如馬）白底占比可低至三成，故用白+字形合计判占用；
    单靠白色会把木框高光误判，故再要求白底下限"""
    return nw + nr + nb >= 0.6 * n and nw >= 0.15 * n


import math
RING_OFFS = sorted({(round(27 * math.cos(a * math.pi / 18)),
                     round(27 * math.sin(a * math.pi / 18))) for a in range(36)})


def ring_dark_frac(px, cx, cy):
    """棋子圆底有一圈深色边框；空点上的木框高光/角落花纹/起点小方框没有。
    深色判据 sum<=380 恰好排除格线（sum~393）"""
    nd = 0
    for dx, dy in RING_OFFS:
        o = ((cy + dy) * FRAME_W + (cx + dx)) * 3
        if px[o] + px[o + 1] + px[o + 2] <= 380:
            nd += 1
    return nd / len(RING_OFFS)

# 采样偏移：占用扫描用步长 3 的圆盘（r<=18），字形匹配用步长 1 的圆盘（r<=19）
SCAN_OFFS = [(dx, dy) for dy in range(-18, 19, 3) for dx in range(-18, 19, 3)
             if dx * dx + dy * dy <= 324]
GLYPH_OFFS = [(dx, dy) for dy in range(-19, 20) for dx in range(-19, 20)
              if dx * dx + dy * dy <= 361]
SHIFTS = [(sx, sy) for sy in (-2, 0, 2) for sx in (-2, 0, 2)]

RED_KINDS = "KABNRCP"
BLACK_KINDS = "kabnrcp"

# 标准开局（UCI 坐标：file 0-8 = a-i，rank 0 = 红方底线）
def start_board():
    b = {}
    back = "RNBAKBNR"  # 部分：a0..d0,e0, f0..i0 镜像
    layout = ["R", "N", "B", "A", "K", "A", "B", "N", "R"]
    for f, k in enumerate(layout):
        b[(f, 0)] = k
        b[(f, 9)] = k.lower()
    for f in (1, 7):
        b[(f, 2)] = "C"
        b[(f, 7)] = "c"
    for f in (0, 2, 4, 6, 8):
        b[(f, 3)] = "P"
        b[(f, 6)] = "p"
    return b

START_BOARD = start_board()

# 模板来源格（视频坐标 (row, col)，红在上）：标准开局中每种棋子取一个代表
TEMPLATE_CELLS = {
    "K": (0, 4), "A": (0, 3), "B": (0, 2), "N": (0, 1), "R": (0, 0),
    "C": (2, 1), "P": (3, 0),
    "k": (9, 4), "a": (9, 3), "b": (9, 2), "n": (9, 1), "r": (9, 0),
    "c": (7, 1), "p": (6, 0),
}

PIECE_CN = {"K": "帅", "A": "仕", "B": "相", "N": "马", "R": "车", "C": "炮", "P": "兵",
            "k": "将", "a": "士", "b": "象", "n": "马", "r": "车", "c": "炮", "p": "卒"}
RED_NUM = "一二三四五六七八九"


def cell_to_sq(rv, cv):
    """视频格（红在上，row 0 顶部）→ UCI 格 (file, rank)"""
    return (8 - cv, rv)


def sq_to_cell(f, r):
    return (r, 8 - f)


def fmt_t(t):
    return f"{int(t) // 60:02d}:{int(t) % 60:02d}"


# ---------------------------------------------------------------- ffmpeg

def ffmpeg_frame_rgb(video, t):
    """取单帧 RGB24 裸像素"""
    cmd = ["ffmpeg", "-v", "error", "-ss", str(t), "-i", video,
           "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    out = subprocess.run(cmd, capture_output=True, check=True).stdout
    if len(out) != FRAME_W * FRAME_H * 3:
        raise RuntimeError(f"帧尺寸不符: {len(out)}")
    return out


def stream_frames(video, fps):
    cmd = ["ffmpeg", "-v", "error", "-i", video, "-vf", f"fps={fps}",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    n = FRAME_W * FRAME_H * 3
    idx = 0
    while True:
        buf = b""
        while len(buf) < n:
            chunk = proc.stdout.read(n - len(buf))
            if not chunk:
                break
            buf += chunk
        if len(buf) < n:
            break
        yield idx, buf
        idx += 1
    proc.wait()


# ---------------------------------------------------------------- 标定

def find_white_clusters(px):
    """泛洪找白色连通块（限定棋盘大致区域），返回 [(cx, cy, area, bw, bh)]"""
    x0, x1, y0, y1 = 330, 1005, 20, 700
    visited = bytearray(FRAME_W * FRAME_H)
    clusters = []
    for y in range(y0, y1, 2):          # 步长 2 起点扫描足以命中直径 50+ 的圆
        base = y * FRAME_W
        for x in range(x0, x1, 2):
            i = base + x
            if visited[i]:
                continue
            o = i * 3
            if min(px[o], px[o + 1], px[o + 2]) < WHITE_MIN:
                continue
            # BFS
            stack = [i]
            visited[i] = 1
            sx = sy = area = 0
            minx = maxx = x
            miny = maxy = y
            while stack:
                j = stack.pop()
                jy, jx = divmod(j, FRAME_W)
                sx += jx; sy += jy; area += 1
                if jx < minx: minx = jx
                if jx > maxx: maxx = jx
                if jy < miny: miny = jy
                if jy > maxy: maxy = jy
                for dj in (-1, 1, -FRAME_W, FRAME_W):
                    nj = j + dj
                    ny, nx = divmod(nj, FRAME_W)
                    if not (x0 <= nx < x1 and y0 <= ny < y1) or visited[nj]:
                        continue
                    no = nj * 3
                    if min(px[no], px[no + 1], px[no + 2]) >= WHITE_MIN:
                        visited[nj] = 1
                        stack.append(nj)
            # 只收形状完好的棋子圆底（正方形包围盒）；被木框高光切割/
            # 合并的聚类直接丢弃，网格拟合不需要 32 子全齐
            if 1000 <= area <= 1700 and 44 <= maxx - minx <= 56 and 44 <= maxy - miny <= 56:
                clusters.append((sx / area, sy / area, area))
    return clusters


def group_1d(vals, gap=30):
    vals = sorted(vals)
    groups = [[vals[0]]]
    for v in vals[1:]:
        if v - groups[-1][-1] > gap:
            groups.append([])
        groups[-1].append(v)
    return [sum(g) / len(g) for g in groups]


def fit_linear(idx_vals):
    """最小二乘拟合 index → 像素坐标"""
    n = len(idx_vals)
    si = sum(i for i, _ in idx_vals)
    sv = sum(v for _, v in idx_vals)
    sii = sum(i * i for i, _ in idx_vals)
    siv = sum(i * v for i, v in idx_vals)
    d = n * sii - si * si
    slope = (n * siv - si * sv) / d
    inter = (sv - slope * si) / n
    return inter, slope


class Grid:
    def __init__(self, xs, ys):
        self.xs = xs  # 视频列 0-8 的中心 x
        self.ys = ys  # 视频行 0-9 的中心 y
        # 边缘格的扫描盘会扫到木框（高光近白、木纹深色，均会造成误判），
        # 朝框一侧截掉超出 6px 的采样点；有棋子时圆底盖住木框，不受影响
        self.scan_offs = {}
        self.quick_offs = {}
        for rv in range(10):
            for cv in range(9):
                offs = [(dx, dy) for dx, dy in SCAN_OFFS
                        if not (cv == 0 and dx < -6) and not (cv == 8 and dx > 6)
                        and not (rv == 0 and dy < -6) and not (rv == 9 and dy > 6)]
                self.scan_offs[(rv, cv)] = offs
                self.quick_offs[(rv, cv)] = offs[::3]

    def center(self, rv, cv):
        return self.xs[cv], self.ys[rv]


def cell_scan(px, cx, cy, offs):
    """返回 (白底数, 红字数, 黑字数, 总采样数)"""
    nw = nr = nb = 0
    for dx, dy in offs:
        o = ((cy + dy) * FRAME_W + (cx + dx)) * 3
        r, g, b = px[o], px[o + 1], px[o + 2]
        if r >= RED_R and r - g >= RED_DIFF and r - b >= RED_DIFF:
            nr += 1
        elif max(r, g, b) <= BLACK_MAX:
            nb += 1
        elif min(r, g, b) >= WHITE_MIN:
            nw += 1
    return nw, nr, nb, len(offs)


def glyph_bits(px, cx, cy, is_red):
    """把字形二值化为 bitboard int（顺序按 GLYPH_OFFS）"""
    bits = 0
    if is_red:
        for dx, dy in GLYPH_OFFS:
            o = ((cy + dy) * FRAME_W + (cx + dx)) * 3
            r = px[o]
            bits <<= 1
            if r >= RED_R and r - px[o + 1] >= RED_DIFF and r - px[o + 2] >= RED_DIFF:
                bits |= 1
    else:
        for dx, dy in GLYPH_OFFS:
            o = ((cy + dy) * FRAME_W + (cx + dx)) * 3
            bits <<= 1
            if px[o] <= BLACK_MAX and px[o + 1] <= BLACK_MAX and px[o + 2] <= BLACK_MAX:
                bits |= 1
    return bits


def calibrate(px):
    clusters = find_white_clusters(px)
    if len(clusters) < 20:
        raise RuntimeError(f"完好白色圆底数不足: {len(clusters)}")
    cols = group_1d([c[0] for c in clusters])
    rows = group_1d([c[1] for c in clusters])
    if len(cols) != 9 or len(rows) != 6:
        raise RuntimeError(f"网格分组异常: {len(cols)} 列 / {len(rows)} 行")
    x0, dx = fit_linear(list(enumerate(cols)))
    y0, dy = fit_linear(list(zip([0, 2, 3, 6, 7, 9], rows)))
    grid = Grid([round(x0 + dx * i) for i in range(9)],
                [round(y0 + dy * i) for i in range(10)])

    # 校验该帧确为标准开局（红在上）
    for (f, r), pc in START_BOARD.items():
        rv, cv = sq_to_cell(f, r)
        nw, nr, nb, n = cell_scan(px, *grid.center(rv, cv), grid.scan_offs[(rv, cv)])
        if not is_occupied(nw, nr, nb, n):
            raise RuntimeError(f"标定帧 ({rv},{cv}) 应有棋子但未检出")
        if (nr > nb) != pc.isupper():
            raise RuntimeError(f"标定帧 ({rv},{cv}) 颜色不符，可能红方不在上方")

    # 裁模板
    templates = {}
    for pc, (rv, cv) in TEMPLATE_CELLS.items():
        cx, cy = grid.center(rv, cv)
        templates[pc] = glyph_bits(px, cx, cy, pc.isupper())
    return grid, templates


# ---------------------------------------------------------------- 识别

def frame_obs(px, grid):
    """返回 90 元组：0 空 / 1 红 / 2 黑；含不确定格则返回 None"""
    obs = []
    occupied = 0
    for rv in range(10):
        for cv in range(9):
            cx, cy = grid.center(rv, cv)
            # 快速判空：稀疏子集里白底极少则直接判空
            nw = 0
            quick = grid.quick_offs[(rv, cv)]
            for dx, dy in quick:
                o = ((cy + dy) * FRAME_W + (cx + dx)) * 3
                if min(px[o], px[o + 1], px[o + 2]) >= WHITE_MIN:
                    nw += 1
            if nw <= len(quick) * 0.15:
                obs.append(0)
                continue
            nw, nr, nb, n = cell_scan(px, cx, cy, grid.scan_offs[(rv, cv)])
            if not is_occupied(nw, nr, nb, n) or ring_dark_frac(px, cx, cy) < 0.5:
                obs.append(0)
                continue
            if max(nr, nb) < n * COLOR_MIN_FRAC:
                return None  # 有棋子但字形被遮挡等，本帧不可信
            obs.append(1 if nr > nb else 2)
            occupied += 1
    if occupied < 2:
        return None  # 无棋盘（片头片尾等）
    return tuple(obs)


def classify_cell(px, grid, templates, rv, cv, is_red):
    """模板匹配单格棋子种类，返回 (piece, score)"""
    cx, cy = grid.center(rv, cv)
    kinds = RED_KINDS if is_red else BLACK_KINDS
    best, best_d = None, 1 << 30
    for sx, sy in SHIFTS:
        bits = glyph_bits(px, cx + sx, cy + sy, is_red)
        for k in kinds:
            d = (bits ^ templates[k]).bit_count()
            if d < best_d:
                best, best_d = k, d
    return best, best_d


def full_classify(px, grid, templates, obs):
    """整盘识别 → board dict；王数量异常返回 None"""
    board = {}
    for rv in range(10):
        for cv in range(9):
            v = obs[rv * 9 + cv]
            if v == 0:
                continue
            pc, _ = classify_cell(px, grid, templates, rv, cv, v == 1)
            board[cell_to_sq(rv, cv)] = pc
    if sum(1 for p in board.values() if p == "K") != 1 or \
       sum(1 for p in board.values() if p == "k") != 1:
        return None
    return board


def obs_of_board(board):
    obs = [0] * 90
    for (f, r), pc in board.items():
        rv, cv = sq_to_cell(f, r)
        obs[rv * 9 + cv] = 1 if pc.isupper() else 2
    return tuple(obs)


def board_str(board):
    """fen 棋盘部分（rank 9 → 0）"""
    rows = []
    for r in range(9, -1, -1):
        row, empty = "", 0
        for f in range(9):
            pc = board.get((f, r))
            if pc is None:
                empty += 1
            else:
                if empty:
                    row += str(empty)
                    empty = 0
                row += pc
        if empty:
            row += str(empty)
        rows.append(row)
    return "/".join(rows)


# ---------------------------------------------------------------- 走法规则

def in_palace(f, r, red):
    return 3 <= f <= 5 and (r <= 2 if red else r >= 7)


def count_between(board, frm, to):
    f0, r0 = frm
    f1, r1 = to
    n = 0
    if f0 == f1:
        for r in range(min(r0, r1) + 1, max(r0, r1)):
            if (f0, r) in board:
                n += 1
    else:
        for f in range(min(f0, f1) + 1, max(f0, f1)):
            if (f, r0) in board:
                n += 1
    return n


def legal(board, frm, to, pc):
    f0, r0 = frm
    f1, r1 = to
    df, dr = f1 - f0, r1 - r0
    if df == 0 and dr == 0:
        return False
    red = pc.isupper()
    tgt = board.get(to)
    if tgt and tgt.isupper() == red:
        return False
    k = pc.upper()
    if k in ("R", "C"):
        if df != 0 and dr != 0:
            return False
        n = count_between(board, frm, to)
        return n == 0 if k == "R" else n == (1 if tgt else 0)
    if k == "N":
        if sorted((abs(df), abs(dr))) != [1, 2]:
            return False
        leg = (f0 + df // 2, r0) if abs(df) == 2 else (f0, r0 + dr // 2)
        return leg not in board
    if k == "B":
        if abs(df) != 2 or abs(dr) != 2 or (f0 + df // 2, r0 + dr // 2) in board:
            return False
        return r1 <= 4 if red else r1 >= 5
    if k == "A":
        return abs(df) == 1 and abs(dr) == 1 and in_palace(f1, r1, red)
    if k == "K":
        return abs(df) + abs(dr) == 1 and in_palace(f1, r1, red)
    if k == "P":
        fwd = 1 if red else -1
        if df == 0 and dr == fwd:
            return True
        crossed = r0 >= 5 if red else r0 <= 4
        return crossed and dr == 0 and abs(df) == 1
    return False


# ---------------------------------------------------------------- 着法记法

def gen_moves(board, red):
    """生成一方全部合法着法（不考虑将军，仅走子规则）"""
    out = []
    for (f, r), pc in list(board.items()):
        if pc.isupper() != red:
            continue
        for tf in range(9):
            for tr in range(10):
                if legal(board, (f, r), (tf, tr), pc):
                    out.append(((f, r), (tf, tr), pc))
    return out


def board_single_move(b1, b2):
    """b1 恰好一步到 b2 则返回 (frm, to, pc)"""
    diffs = [sq for sq in set(b1) | set(b2) if b1.get(sq) != b2.get(sq)]
    if len(diffs) != 2:
        return None
    src = dst = None
    for sq in diffs:
        if sq in b1 and sq not in b2:
            src = sq
        elif sq in b2:
            dst = sq
    if src is None or dst is None:
        return None
    pc = b1[src]
    if b2[dst] != pc or not legal(b1, src, dst, pc):
        return None
    return src, dst, pc


def pgn_coord(frm, to):
    """PGN 坐标着法（列 a-i 左→右、行 0 在黑方顶部，与 PGNParser 一致）"""
    c = "abcdefghi"
    return f"{c[frm[0]]}{9 - frm[1]}{c[to[0]]}{9 - to[1]}"


def cn_num(f, red):
    return RED_NUM[8 - f] if red else str(f + 1)


def cn_move(board, frm, to, pc):
    red = pc.isupper()
    f0, r0 = frm
    f1, r1 = to
    name = PIECE_CN[pc]
    # 同列同种多子 → 前/中/后
    group = sorted([r for (f, r), q in board.items() if q == pc and f == f0],
                   reverse=red)  # 排首位 = 前（靠近敌方）
    if len(group) >= 2:
        pos = group.index(r0)
        tag = ["前", "中", "后"][pos] if len(group) == 3 else ("前" if pos == 0 else "后")
        head = tag + name
    else:
        head = name + cn_num(f0, red)
    if r1 == r0:
        return head + "平" + cn_num(f1, red)
    fwd = (r1 > r0) == red
    verb = "进" if fwd else "退"
    if pc.upper() in "RCPK":
        steps = abs(r1 - r0)
        return head + verb + (RED_NUM[steps - 1] if red else str(steps))
    return head + verb + cn_num(f1, red)


# ---------------------------------------------------------------- 棋谱树

class Tree:
    def __init__(self):
        self.nodes = []       # {board, side, obs, first_t, edges: [(frm,to,pc,child,t)]}
        self.by_board = {}    # board_str → [node_id]
        self.warnings = []
        self.cur = None
        self.has_incoming = set()

    def warn(self, t, msg):
        self.warnings.append(f"[{fmt_t(t)}] {msg}")

    def _find_node(self, key, side):
        for nid in self.by_board.get(key, []):
            if self.nodes[nid]["side"] == side:
                return nid
        return None

    def get_or_create(self, board, side, t):
        key = board_str(board)
        for nid in self.by_board.get(key, []):
            n = self.nodes[nid]
            if n["side"] == side or n["side"] == "?" or side == "?":
                if n["side"] == "?":
                    n["side"] = side
                return nid
        nid = len(self.nodes)
        self.nodes.append({"board": dict(board), "side": side, "obs": obs_of_board(board),
                           "first_t": t, "edges": []})
        self.by_board.setdefault(key, []).append(nid)
        return nid

    def advance(self, nid, frm, to, pc, t):
        node = self.nodes[nid]
        mover = "r" if pc.isupper() else "b"
        if node["side"] not in ("?", mover):
            self.warn(t, f"连续同色走子: {cn_move(node['board'], frm, to, pc)}（按变着记录）")
        if node["side"] == "?":
            node["side"] = mover
        newboard = dict(node["board"])
        del newboard[frm]
        newboard[to] = pc
        child = self.get_or_create(newboard, "b" if mover == "r" else "r", t)
        for e in node["edges"]:
            if e[0] == frm and e[1] == to:
                self.cur = child
                return
        node["edges"].append((frm, to, pc, child, t))
        self.has_incoming.add(child)
        self.cur = child

    def single_move_from(self, nid, obs):
        """node 的局面到 obs 若恰为一步棋，返回 (frm, to, pc)"""
        node = self.nodes[nid]
        diffs = [i for i in range(90) if node["obs"][i] != obs[i]]
        if len(diffs) != 2:
            return None
        src = dst = None
        for i in diffs:
            if obs[i] == 0 and node["obs"][i] != 0:
                src = i
            elif obs[i] != 0:
                dst = i
        if src is None or dst is None:
            return None
        frm = cell_to_sq(src // 9, src % 9)
        to = cell_to_sq(dst // 9, dst % 9)
        pc = node["board"][frm]
        if (1 if pc.isupper() else 2) != obs[dst]:
            return None
        if not legal(node["board"], frm, to, pc):
            return None
        return frm, to, pc

    def process(self, obs, t, px, grid, templates):
        if self.cur is not None:
            if obs == self.nodes[self.cur]["obs"]:
                return
            mv = self.single_move_from(self.cur, obs)
            if mv:
                frm, to, pc = mv
                # 落点字形复核，防止漏帧导致的错误归并
                rv, cv = sq_to_cell(*to)
                kind, _ = classify_cell(px, grid, templates, rv, cv, pc.isupper())
                if kind == pc:
                    mover = "r" if pc.isupper() else "b"
                    cnode = self.nodes[self.cur]
                    if cnode["side"] not in ("?", mover):
                        # 轮次冲突。重复局面演示会产生同盘面不同走方的兄弟节点，
                        # 优先改从轮到 mover 的兄弟节点出发
                        alt = self._find_node(board_str(cnode["board"]), mover)
                        if alt is not None:
                            self.advance(alt, frm, to, pc, t)
                            return
                        # 也可能是"悔棋"反向走子：目标局面已存在 → 当作导航跳转
                        newboard = dict(cnode["board"])
                        del newboard[frm]
                        newboard[to] = pc
                        key = board_str(newboard)
                        back = self._find_node(key, mover)
                        if back is None:
                            back = (self.by_board.get(key) or [None])[0]
                        if back is not None:
                            self.cur = back
                            return
                    self.advance(self.cur, frm, to, pc, t)
                    return
        # 非单步：整盘识别后尝试跳转 / 挂接
        board = full_classify(px, grid, templates, obs)
        if board is None:
            return  # 拖拽中间态（少一子/王异常），忽略
        key = board_str(board)
        if key in self.by_board:
            self.cur = self.by_board[key][0]
            return
        candidates = []
        for nid in range(len(self.nodes)):
            mv = self.single_move_from(nid, obs)
            if mv and self.nodes[nid]["board"].get(mv[0]) == mv[2] and board.get(mv[1]) == mv[2]:
                mover = "r" if mv[2].isupper() else "b"
                candidates.append((0 if self.nodes[nid]["side"] == mover else 1, nid, mv))
        if candidates:
            candidates.sort()
            _, nid, (frm, to, pc) = candidates[0]
            if len(candidates) > 1:
                self.warn(t, f"多个可挂接父局面，取时间最早方（{len(candidates)} 个候选）")
            self.advance(nid, frm, to, pc, t)
            return
        # 两步桥接：讲课节奏快时中间局面可能一帧未稳定，尝试从当前节点两步到达
        if self.cur is not None:
            cnode = self.nodes[self.cur]
            side0 = cnode["side"]
            bridges = []
            for order in (("r", "b"), ("b", "r")) if side0 == "?" else ((side0, "br".replace(side0, "")),):
                for frm1, to1, pc1 in gen_moves(cnode["board"], order[0] == "r"):
                    b1 = dict(cnode["board"])
                    del b1[frm1]
                    b1[to1] = pc1
                    mv2 = board_single_move(b1, board)
                    if mv2 and (mv2[2].isupper() == (order[1] == "r")):
                        bridges.append(((frm1, to1, pc1), mv2))
            if bridges:
                (frm1, to1, pc1), (frm2, to2, pc2) = bridges[0]
                if len(bridges) > 1:
                    self.warn(t, f"两步桥接有 {len(bridges)} 种可能，取第一种")
                base = self.cur
                self.warn(t, f"两步桥接补上中间着法: "
                             f"{cn_move(self.nodes[base]['board'], frm1, to1, pc1)}")
                self.advance(base, frm1, to1, pc1, t)
                self.advance(self.cur, frm2, to2, pc2, t)
                return
        side = "r" if board == START_BOARD else "?"
        nid = self.get_or_create(board, side, t)
        if board != START_BOARD:
            self.warn(t, f"出现无法与已知局面衔接的新局面（作为独立起点，{len(board)} 子）")
        self.cur = nid


# ---------------------------------------------------------------- 导出

def collect_games(tree):
    roots = [nid for nid in range(len(tree.nodes)) if nid not in tree.has_incoming]
    roots.sort(key=lambda n: tree.nodes[n]["first_t"])
    games = []

    def dfs(nid, path, onpath):
        node = tree.nodes[nid]
        edges = sorted(node["edges"], key=lambda e: e[4])
        if not edges:
            if path:
                games.append(list(path))
            return
        for frm, to, pc, child, t in edges:
            if child in onpath:
                continue  # 循环（重复局面）截断
            path.append((nid, frm, to, pc, child, t))
            onpath.add(child)
            dfs(child, path, onpath)
            onpath.discard(child)
            path.pop()

    for root in roots:
        dfs(root, [], {root})
    return roots, games


def export(tree, video, out_dir, fps):
    base = os.path.splitext(os.path.basename(video))[0]
    os.makedirs(out_dir, exist_ok=True)
    roots, games = collect_games(tree)

    pgn_lines = []
    txt_lines = []
    meta_games = []
    for gi, path in enumerate(games, 1):
        root = tree.nodes[path[0][0]]
        pgn_lines.append(f'[Game "{gi}"]')
        pgn_lines.append(f'[Event "{base}"]')
        pgn_lines.append(f'[Round "{gi}"]')
        pgn_lines.append('[Result "*"]')
        start_fen = None
        if root["board"] != START_BOARD:
            side = "w" if root["side"] in ("r", "?") else "b"
            start_fen = board_str(root["board"]) + " " + side
            pgn_lines.append(f'[FEN "{start_fen}"]')
        moves = []
        cns = []
        plies = []
        for nid, frm, to, pc, child, t in path:
            board = tree.nodes[nid]["board"]
            moves.append(pgn_coord(frm, to))
            cns.append(f"{cn_move(board, frm, to, pc)}({fmt_t(t)})")
            child_side = tree.nodes[child]["side"]
            plies.append({
                "move": pgn_coord(frm, to),
                "cn": cn_move(board, frm, to, pc),
                "t": round(t, 2),
                "fen": board_str(tree.nodes[child]["board"]) + " " +
                       ("r" if child_side in ("r", "?") else "b"),
            })
        body = ""
        for i in range(0, len(moves), 2):
            body += f"{i // 2 + 1}. " + " ".join(moves[i:i + 2]) + " "
        pgn_lines.append(body + "*")
        pgn_lines.append("")

        txt_lines.append(f"—— 第 {gi} 局（{fmt_t(path[0][5])} 起，{len(moves)} 步）——")
        for i in range(0, len(cns), 2):
            txt_lines.append(f"  {i // 2 + 1}. " + "  ".join(cns[i:i + 2]))
        txt_lines.append("")
        meta_games.append({"index": gi, "start_fen": start_fen, "plies": plies})

    pgn_path = os.path.join(out_dir, base + ".pgn")
    txt_path = os.path.join(out_dir, base + ".lines.txt")
    meta_path = os.path.join(out_dir, base + ".meta.json")
    with open(pgn_path, "w") as f:
        f.write("\n".join(pgn_lines))
    with open(txt_path, "w") as f:
        f.write("\n".join(txt_lines))
    with open(meta_path, "w") as f:
        json.dump({"video": os.path.abspath(video), "fps": fps,
                   "games": meta_games, "warnings": tree.warnings},
                  f, ensure_ascii=False, indent=1)
    return pgn_path, txt_path, meta_path, roots, games


# ---------------------------------------------------------------- 主流程

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--fps", type=int, default=4)
    ap.add_argument("--out-dir", default="out")
    ap.add_argument("--calib-times", default="10,5,15,20,30")
    ap.add_argument("--calib-video", default=None,
                    help="本视频找不到标准开局帧时，借用该视频做网格/模板标定（同一课程录制布局一致）")
    args = ap.parse_args()

    global FRAME_W, FRAME_H
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0", args.video],
        capture_output=True, text=True, check=True).stdout.strip().split(",")
    FRAME_W, FRAME_H = int(probe[0]), int(probe[1])

    grid = templates = None
    sources = [args.video] + ([args.calib_video] if args.calib_video else [])
    for src in sources:
        for t in args.calib_times.split(","):
            try:
                px = ffmpeg_frame_rgb(src, float(t))
                grid, templates = calibrate(px)
                print(f"标定成功 @ {os.path.basename(src)} {t}s: 列x={grid.xs} 行y={grid.ys}")
                break
            except (RuntimeError, subprocess.CalledProcessError) as e:
                print(f"标定 @ {os.path.basename(src)} {t}s 失败: {e}")
        if grid is not None:
            break
    if grid is None:
        sys.exit("无法标定棋盘（找不到标准开局帧）")

    tree = Tree()
    prev_obs, run_len, run_start = None, 0, 0
    n_frames = n_valid = 0
    for fidx, px in stream_frames(args.video, args.fps):
        n_frames += 1
        obs = frame_obs(px, grid)
        if obs is None:
            prev_obs, run_len = None, 0
            continue
        n_valid += 1
        if obs == prev_obs:
            run_len += 1
        else:
            prev_obs, run_len, run_start = obs, 1, fidx
        if run_len == 2:
            tree.process(obs, run_start / args.fps, px, grid, templates)

    pgn_path, txt_path, meta_path, roots, games = export(
        tree, args.video, args.out_dir, args.fps)

    print(f"\n帧: {n_frames}（有效 {n_valid}） 局面节点: {len(tree.nodes)} "
          f"根: {len(roots)} 导出棋局: {len(games)}")
    if tree.warnings:
        print(f"警告 {len(tree.warnings)} 条:")
        for w in tree.warnings:
            print("  " + w)
    print(f"\n输出:\n  {pgn_path}\n  {txt_path}\n  {meta_path}")


if __name__ == "__main__":
    main()
