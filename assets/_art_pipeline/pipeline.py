#!/usr/bin/env python3
"""萌象棋美术管线：AI 源图 → 抠图 → 合成棋子 → 派生动画帧 → 棋盘/按钮/特效纹理。

用法（在 default venv 下）：
    python pipeline.py prepare     # rembg 抠图 source/ -> clean/
    python pipeline.py compose     # 合成 14 棋子静帧 -> composed/
    python pipeline.py frames      # 派生 5状态x12帧 -> 直接写入 assets/themes/cats/pieces/
    python pipeline.py anim        # 胜利/战败 12 帧 -> assets/themes/cats/anim/
    python pipeline.py buttons     # 加速按钮 -> assets/themes/cats/ui/
    python pipeline.py board       # 正式棋盘 -> assets/board/
    python pipeline.py fxtex       # 特效粒子纹理 -> assets/themes/cats/fx/
    python pipeline.py all         # 以上全部

仅用于资源处理，不承载游戏逻辑（AGENTS.md 约束）。
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = "/Users/shen/Studio/Code/MoeChess"
SRC = os.path.join(ROOT, "assets/_art_pipeline/source")
CLEAN = os.path.join(ROOT, "assets/_art_pipeline/clean")
COMPOSED = os.path.join(ROOT, "assets/_art_pipeline/composed")
THEME = os.path.join(ROOT, "assets/themes/cats")
BOARD_DIR = os.path.join(ROOT, "assets/board")

FRAME = 256          # 棋子帧尺寸（与占位版一致）
FRAMES_PER_STATE = 12
ANIM_SIZE = 1024     # 胜负动画帧尺寸（与占位版一致）

# 源图文件名前缀 -> 规范名
SOURCE_MAP = {
    "Adorable_chubby_orange_tabby": "cat_orange",
    "Adorable_chubby_black_cat": "cat_black",
    "Small_royal_golden_crown": "prop_crown",
    "Small_round_knight_shield": "prop_shield",
    "Cute_elephant_head_hat": "prop_elephant_hat",
    "Small_wooden_rocking_horse": "prop_wooden_horse",
    "Miniature_ancient_Chinese_war": "prop_chariot",
    "Small_cute_cannon_barrel": "prop_cannon",
    "Small_ancient_Chinese_soldier": "prop_soldier_hat",
    "Cute_chubby_black_clay_cat_sit": "defeat_visual",
    "Group_of_cute_chubby_clay_cats": "victory_visual",
    "Flat_top_down_view_of_plain_wa": "board_wood",
    # 两个表情按钮按修改时间区分：先生成的是着急(12)，后生成的是悠闲(13)
    "Cute_orange_tabby_cat_face_clo_2026-07-29T08-58-12": "button_fast",
    "Cute_orange_tabby_cat_face_clo_2026-07-29T08-58-13": "button_idle",
}

# 棋子类型 -> 道具名
PIECE_PROPS = {
    "king": "prop_crown",
    "advisor": "prop_shield",
    "elephant": "prop_elephant_hat",
    "horse": "prop_wooden_horse",
    "chariot": "prop_chariot",
    "cannon": "prop_cannon",
    "pawn": "prop_soldier_hat",
}

# 道具摆放方式：head=头顶、front=身前右下、mount=坐骑（猫坐在上面）
PROP_MODE = {
    "prop_crown": "head",
    "prop_elephant_hat": "head",
    "prop_soldier_hat": "head",
    "prop_shield": "front",
    "prop_cannon": "front",
    "prop_wooden_horse": "mount",
    "prop_chariot": "mount",
}

SIDES = {"red": "cat_orange", "black": "cat_black"}
DISC_COLORS = {  # (主色, 深色描边, 高光)
    "red": ((217, 79, 61), (158, 45, 32), (240, 128, 110)),
    "black": ((70, 70, 82), (40, 40, 50), (110, 110, 128)),
}


# ---------- 工具 ----------

def load_clean(name):
    p = os.path.join(CLEAN, name + ".png")
    return Image.open(p).convert("RGBA")


def trim(im, threshold=8):
    """按 alpha 裁掉透明边。"""
    alpha = im.getchannel("A")
    bbox = alpha.point(lambda a: 255 if a > threshold else 0).getbbox()
    return im.crop(bbox) if bbox else im


def fit_height(im, h):
    w = int(im.width * h / im.height)
    return im.resize((w, h), Image.LANCZOS)


def fit_width(im, w):
    h = int(im.height * w / im.width)
    return im.resize((w, h), Image.LANCZOS)


def paste_center(canvas, im, cx, bottom_y):
    """把 im 以水平居中、底部对齐 bottom_y 粘贴。"""
    canvas.alpha_composite(im, (int(cx - im.width / 2), int(bottom_y - im.height)))


# ---------- prepare：rembg 抠图 ----------

def _local_remove_bg(im):
    """纯 PIL/numpy 背景移除（rembg 模型不可达时的本地方案）。

    源图背景为浅灰渐变 + 右下角半透明水印。算法：
    1. HSV 规则标记背景候选（低饱和 + 高亮度）
    2. 从四边 BFS 区域生长，只保留与边框连通的背景
    3. 前景只保留最大连通域，去除水印残留碎块
    4. 边缘 1px 腐蚀 + 轻羽化
    """
    import numpy as np
    from collections import deque

    rgb = np.asarray(im.convert("RGB")).astype(np.float32) / 255.0
    h, w = rgb.shape[:2]
    # 边框颜色中位数作为背景基准（全局包络用）
    border = np.concatenate([
        rgb[0, :, :], rgb[-1, :, :], rgb[:, 0, :], rgb[:, -1, :]
    ])
    med = np.median(border, axis=0)
    # 局部梯度游走洪泛：从四边出发，仅当与"来路像素"色差极小时才继续，
    # 平滑渐变（含暗灰、暖白、接触阴影）会被吞掉，主体边缘对比处停止。
    LOCAL_TOL = 0.055
    ENVELOPE = 0.35
    bg = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        src = rgb[y, x]
        for ny, nx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
            if 0 <= ny < h and 0 <= nx < w and not bg[ny, nx]:
                tgt = rgb[ny, nx]
                if (np.abs(tgt - src) < LOCAL_TOL).all() and \
                   (np.abs(tgt - med) < ENVELOPE).all():
                    bg[ny, nx] = True
                    q.append((ny, nx))
    fg = ~bg
    # 最大连通域（4 连通，简单两次扫描可能漏，这里用 BFS 标号）
    labels = np.zeros((h, w), np.int32)
    cur = 0
    best_label, best_size = 0, 0
    ys, xs = np.nonzero(fg)
    for sy0, sx0 in zip(ys[::7], xs[::7]):  # 抽样找种子，提速
        if labels[sy0, sx0] or not fg[sy0, sx0]:
            continue
        cur += 1
        size = 0
        q.append((sy0, sx0))
        labels[sy0, sx0] = cur
        while q:
            y, x = q.popleft()
            size += 1
            for ny, nx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
                if 0 <= ny < h and 0 <= nx < w and fg[ny, nx] and labels[ny, nx] == 0:
                    labels[ny, nx] = cur
                    q.append((ny, nx))
        if size > best_size:
            best_label, best_size = cur, size
    keep = labels == best_label
    return keep


def _local_remove_bg_safe(im):
    """_local_remove_bg 的无 scipy 包装。"""
    import numpy as np
    keep = _local_remove_bg(im)
    arr = np.asarray(im.convert("RGBA")).copy()
    # 腐蚀 1px：邻域内任一像素不保留则透明
    k = keep
    eroded = k.copy()
    eroded[:-1, :] &= k[1:, :]
    eroded[1:, :] &= k[:-1, :]
    eroded[:, :-1] &= k[:, 1:]
    eroded[:, 1:] &= k[:, :-1]
    alpha = arr[..., 3]
    alpha = np.where(eroded, alpha, 0).astype(np.uint8)
    arr[..., 3] = alpha
    out = Image.fromarray(arr, "RGBA")
    # 轻羽化边缘
    a = out.getchannel("A").filter(ImageFilter.GaussianBlur(0.8))
    out.putalpha(a)
    return out


def cmd_prepare():
    os.makedirs(CLEAN, exist_ok=True)
    model = os.path.expanduser("~/.u2net/u2net.onnx")
    # u2net.onnx 完整约 168MB；下载中的残文件不能用
    use_rembg = os.path.exists(model) and os.path.getsize(model) > 100 * 1024 * 1024
    remover = None
    if use_rembg:
        try:
            from rembg import remove
            remover = remove
            print("使用 rembg")
        except Exception as e:
            print("rembg 不可用，回退本地抠图:", e)
    else:
        print("未找到 u2net 模型，使用本地抠图")
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith(".png"):
            continue
        name = None
        for prefix, canon in SOURCE_MAP.items():
            if fn.startswith(prefix):
                name = canon
                break
        if name is None:
            print("跳过未识别文件:", fn)
            continue
        src_path = os.path.join(SRC, fn)
        im = Image.open(src_path).convert("RGBA")
        if name == "board_wood":
            out = im  # 棋盘底图不透明，无需抠图
        elif remover is not None:
            out = remover(im)
        else:
            out = _local_remove_bg_safe(im)
        out.save(os.path.join(CLEAN, name + ".png"))
        print("clean:", name)


# ---------- compose：棋子静帧合成 ----------

def make_disc(side):
    """黏土质感圆盘底座，256x256 画布，中心 (128, 200)。"""
    im = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    main, rim, hi = DISC_COLORS[side]
    cx, cy, rx, ry = 128, 200, 104, 30
    # 底部软阴影
    d.ellipse([cx - rx, cy - ry + 10, cx + rx, cy + ry + 14], fill=(0, 0, 0, 60))
    # 盘体（下沿深色做厚度）
    d.ellipse([cx - rx, cy - ry + 8, cx + rx, cy + ry + 8], fill=rim + (255,))
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=main + (255,))
    # 顶部高光
    d.ellipse([cx - rx + 18, cy - ry + 4, cx + rx - 40, cy - ry + 16], fill=hi + (90,))
    return im


def compose_piece(side, ptype):
    """合成单个棋子静帧：底座 + (坐骑) + 猫本体 + 道具。"""
    canvas = make_disc(side)
    body = trim(load_clean(SIDES[side]))
    body = fit_height(body, 178)
    prop_name = PIECE_PROPS[ptype]
    prop = trim(load_clean(prop_name))
    mode = PROP_MODE[prop_name]
    cx = 128
    disc_top_y = 196  # 猫脚底落在盘面上

    if mode == "mount":
        mount = fit_width(prop, 220)
        paste_center(canvas, mount, cx, disc_top_y + 24)
        # 猫坐在坐骑上：脚底抬升
        paste_center(canvas, body, cx, disc_top_y - int(mount.height * 0.35))
    else:
        paste_center(canvas, body, cx, disc_top_y)
        bw, bh = body.width, body.height
        body_top = disc_top_y - bh
        if mode == "head":
            ratio = {"prop_crown": 0.58, "prop_elephant_hat": 0.80, "prop_soldier_hat": 0.66}[prop_name]
            overlap = {"prop_crown": 0.02, "prop_elephant_hat": 0.20, "prop_soldier_hat": 0.08}[prop_name]
            hat = fit_width(prop, int(bw * ratio))
            # 帽子底部落在 body_top + overlap*bh（略压头顶）
            paste_center(canvas, hat, cx, body_top + int(bh * overlap))
        elif mode == "front":
            held = fit_width(prop, int(bw * 0.52))
            px = cx + int(bw * 0.30)
            py = disc_top_y - int(bh * 0.28)
            canvas.alpha_composite(held, (int(px - held.width / 2), int(py - held.height / 2)))
    return canvas


def cmd_compose():
    os.makedirs(COMPOSED, exist_ok=True)
    for side in ("red", "black"):
        for ptype in PIECE_PROPS:
            im = compose_piece(side, ptype)
            im.save(os.path.join(COMPOSED, f"{side}_{ptype}.png"))
            print("composed:", side, ptype)


# ---------- frames：5 状态 x 12 帧派生 ----------

def anchor_transform(base, scale_x=1.0, scale_y=1.0, angle=0.0, dx=0.0, dy=0.0, alpha=1.0):
    """以脚底锚点 (128, 226) 做缩放/旋转/位移/透明度变换。"""
    ax, ay = 128, 226
    w = max(1, int(FRAME * scale_x))
    h = max(1, int(FRAME * scale_y))
    im = base.resize((w, h), Image.LANCZOS)
    if abs(angle) > 0.01:
        im = im.rotate(angle, Image.BICUBIC, expand=True)
    if alpha < 1.0:
        a = im.getchannel("A").point(lambda v: int(v * alpha))
        im.putalpha(a)
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    # 变换后图像底部中心对齐脚底锚点
    ox = ax + dx - im.width / 2
    oy = ay + dy - im.height
    canvas.alpha_composite(im, (int(ox), int(oy)))
    return canvas


def derive_frames(base):
    """从静帧派生 5 状态帧序列，返回 {state: [Image x12]}。"""
    out = {}
    n = FRAMES_PER_STATE
    idle, selected, moving, killing, killed = [], [], [], [], []
    for i in range(n):
        t = i / n
        s = math.sin(2 * math.pi * t)
        # idle：呼吸浮动
        idle.append(anchor_transform(base, 1.0, 1.0 + 0.02 * s, dy=-3 * s))
        # selected：放大 + 快速小抖动（2 个周期）
        selected.append(anchor_transform(base, 1.06, 1.06, dx=2.5 * math.sin(4 * math.pi * t)))
        # moving：挤压拉伸 + 一次弹跳 + 前倾
        hop = -20 * math.sin(math.pi * t)
        sy = 1.0 - 0.10 * math.sin(2 * math.pi * t)
        sx = 1.0 + 0.08 * math.sin(2 * math.pi * t)
        moving.append(anchor_transform(base, sx, sy, angle=-6 * math.sin(2 * math.pi * t), dy=hop))
        # killing：蓄力后猛扑再回弹
        if i < 4:
            ldx = -8 * (i / 3.0)
        elif i < 8:
            ldx = -8 + 30 * ((i - 3) / 4.0)
        else:
            ldx = 22 * (1 - (i - 7) / 5.0)
        lsx = 1.0 + (0.12 if 4 <= i < 8 else 0.0)
        killing.append(anchor_transform(base, lsx, 1.0, dx=ldx))
        # killed：旋转倒地 + 渐隐
        ang = -80 * min(1.0, i / 7.0)
        fade = 1.0 - 0.35 * min(1.0, i / 9.0)
        killed.append(anchor_transform(base, 1.0, 1.0, angle=ang, dy=6 * min(1.0, i / 7.0), alpha=fade))
    out["idle"], out["selected"], out["moving"] = idle, selected, moving
    out["killing"], out["killed"] = killing, killed
    return out


def cmd_frames():
    for side in ("red", "black"):
        for ptype in PIECE_PROPS:
            key = f"{side}_{ptype}"
            base = Image.open(os.path.join(COMPOSED, key + ".png")).convert("RGBA")
            seqs = derive_frames(base)
            out_dir = os.path.join(THEME, "pieces", key)
            os.makedirs(out_dir, exist_ok=True)
            for state, frames in seqs.items():
                for idx, fr in enumerate(frames, 1):
                    fr.save(os.path.join(out_dir, f"{state}_{idx:03d}.png"))
            print("frames:", key)


# ---------- anim：胜利/战败全队动画帧 ----------

def cmd_anim():
    for name, kind in (("victory_visual", "victory"), ("defeat_visual", "defeat")):
        src_im = trim(load_clean(name))
        base = Image.new("RGBA", (ANIM_SIZE, ANIM_SIZE), (0, 0, 0, 0))
        body = fit_height(src_im, int(ANIM_SIZE * 0.82))
        paste_center(base, body, ANIM_SIZE // 2, int(ANIM_SIZE * 0.92))
        for i in range(FRAMES_PER_STATE):
            t = i / FRAMES_PER_STATE
            if kind == "victory":
                dy = -34 * abs(math.sin(2 * math.pi * t))
                sc = 1.0 + 0.03 * math.sin(2 * math.pi * t)
                fr = _anim_transform(base, sc, sc, 0, dy)
            else:
                ang = 4 * math.sin(2 * math.pi * t)
                fr = _anim_transform(base, 1.0, 0.97, ang, 0)
            fr.save(os.path.join(THEME, "anim", f"{kind}_{i+1:03d}.png"))
        print("anim:", kind)


def _anim_transform(base, sx, sy, angle, dy):
    ax, ay = ANIM_SIZE // 2, int(ANIM_SIZE * 0.92)
    w, h = int(ANIM_SIZE * sx), int(ANIM_SIZE * sy)
    im = base.resize((w, h), Image.LANCZOS)
    if abs(angle) > 0.01:
        im = im.rotate(angle, Image.BICUBIC, expand=True)
    canvas = Image.new("RGBA", (ANIM_SIZE, ANIM_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(im, (int(ax - im.width / 2), int(ay + dy - im.height)))
    return canvas


# ---------- buttons：加速按钮 ----------

def cmd_buttons():
    ref = Image.open(os.path.join(THEME, "ui", "speed_button_idle.png"))
    size = ref.size[0]
    for name in ("button_idle", "button_fast"):
        face = trim(load_clean(name))
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(canvas)
        ring = (217, 79, 61) if name == "button_fast" else (90, 140, 200)
        d.ellipse([4, 4, size - 4, size - 4], fill=(250, 244, 232, 255), outline=ring + (255,), width=max(4, size // 42))
        f = fit_width(face, int(size * 0.82))
        canvas.alpha_composite(f, ((size - f.width) // 2, (size - f.height) // 2 + int(size * 0.02)))
        canvas.save(os.path.join(THEME, "ui", name.replace("button", "speed_button") + ".png"))
        print("button:", name)


# ---------- board：正式棋盘（纹理 + 程序网格，对齐 BoardPerspective） ----------

BG_W, BG_H = 1080, 1280
CENTER_X = BG_W / 2.0
NEAR_Y, FAR_Y = 1220.0, 60.0
NEAR_HW, FAR_HW = 496.0, 345.0
ROWS, COLS = 10, 9


def _y_at(t):
    return NEAR_Y + (FAR_Y - NEAR_Y) * t


def _hw_at(t):
    return NEAR_HW + (FAR_HW - NEAR_HW) * t


def _pt(col, row, flipped):
    t = row / (ROWS - 1)
    if flipped:
        t = 1.0 - t
    half = _hw_at(t)
    x = CENTER_X + half * (col / (COLS - 1) * 2 - 1)
    return (x, _y_at(t))


def draw_board(flipped):
    wood = Image.open(os.path.join(CLEAN, "board_wood.png")).convert("RGB")
    # 裁中央木质区（去掉 AI 图自带边框 14%），重采样到目标尺寸
    cx0, cy0 = int(wood.width * 0.14), int(wood.height * 0.14)
    inner = wood.crop((cx0, cy0, wood.width - cx0, wood.height - cy0)).resize((BG_W, BG_H), Image.LANCZOS)
    im = inner.convert("RGBA")
    d = ImageDraw.Draw(im)
    # 圆角黏土外框
    d.rounded_rectangle([10, 10, BG_W - 10, BG_H - 10], radius=36, outline=(120, 78, 42, 255), width=14)
    d.rounded_rectangle([26, 26, BG_W - 26, BG_H - 26], radius=26, outline=(160, 110, 64, 255), width=5)
    line = (96, 62, 34, 255)
    lw = 5
    # 横线：row 0..9
    for r in range(ROWS):
        p0 = _pt(0, r, flipped)
        p1 = _pt(COLS - 1, r, flipped)
        d.line([p0, p1], fill=line, width=lw)
    # 竖线：col 0..8，中间列在河界处断开
    river_a, river_b = 4, 5  # 河界在 row4 与 row5 之间
    for c in range(COLS):
        if c in (0, COLS - 1):
            d.line([_pt(c, 0, flipped), _pt(c, ROWS - 1, flipped)], fill=line, width=lw)
        else:
            d.line([_pt(c, 0, flipped), _pt(c, river_a, flipped)], fill=line, width=lw)
            d.line([_pt(c, river_b, flipped), _pt(c, ROWS - 1, flipped)], fill=line, width=lw)
    # 九宫斜线
    for top_r, bot_r in ((0, 2), (7, 9)):
        d.line([_pt(3, top_r, flipped), _pt(5, bot_r, flipped)], fill=line, width=lw)
        d.line([_pt(5, top_r, flipped), _pt(3, bot_r, flipped)], fill=line, width=lw)
    # 炮位/兵位小标记
    marks = [(1, 2), (7, 2), (1, 7), (7, 7)] + [(c, 3) for c in (0, 2, 4, 6, 8)] + [(c, 6) for c in (0, 2, 4, 6, 8)]
    for c, r in marks:
        x, y = _pt(c, r, flipped)
        g = 10 + 3 * (1 - abs(r - 4.5) / 5)  # 近大远小
        for sx in (-1, 1):
            for sy in (-1, 1):
                if (c == 0 and sx < 0) or (c == COLS - 1 and sx > 0):
                    continue
                d.line([(x + sx * g, y + sy * g * 2), (x + sx * g * 2.6, y + sy * g * 2)], fill=line, width=3)
                d.line([(x + sx * g * 2, y + sy * g), (x + sx * g * 2, y + sy * g * 2.6)], fill=line, width=3)
    # 河界文字
    try:
        font = ImageFont.truetype("/System/Library/Fonts/STHeiti Light.ttc", 64)
    except Exception:
        font = ImageFont.load_default()
    y_river = (_y_at(_t_row(4, flipped)) + _y_at(_t_row(5, flipped))) / 2
    for text, fx in (("楚  河", 0.28), ("漢  界", 0.72)):
        bb = d.textbbox((0, 0), text, font=font)
        d.text((CENTER_X + (fx - 0.5) * 2 * _hw_at(0.5) - (bb[2] - bb[0]) / 2, y_river - (bb[3] - bb[1]) / 2),
               text, font=font, fill=(120, 78, 42, 220))
    return im


def _t_row(row, flipped):
    t = row / (ROWS - 1)
    return 1.0 - t if flipped else t


def cmd_board():
    player = draw_board(flipped=False)
    player.convert("RGB").save(os.path.join(BOARD_DIR, "board_player.png"))
    opponent = draw_board(flipped=True)
    opponent.convert("RGB").save(os.path.join(BOARD_DIR, "board_opponent.png"))
    print("board: player/opponent")


# ---------- fxtex：特效粒子纹理 ----------

def cmd_fxtex():
    fx_dir = os.path.join(THEME, "fx")
    os.makedirs(fx_dir, exist_ok=True)
    # 星星（击杀）
    star = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(star)
    cx, cy, R, r = 32, 32, 28, 12
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = R if i % 2 == 0 else r
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    d.polygon(pts, fill=(255, 205, 70, 255), outline=(220, 140, 30, 255))
    star.save(os.path.join(fx_dir, "star_particle.png"))
    # 肉球（被击杀）
    paw = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(paw)
    pink = (244, 160, 170, 255)
    d.ellipse([16, 28, 48, 56], fill=pink)
    for fx, fy in ((14, 18), (26, 10), (38, 10), (50, 18)):
        d.ellipse([fx - 6, fy - 6, fx + 6, fy + 6], fill=pink)
    paw.save(os.path.join(fx_dir, "paw_particle.png"))
    print("fxtex: star/paw")


COMMANDS = {
    "prepare": cmd_prepare,
    "compose": cmd_compose,
    "frames": cmd_frames,
    "anim": cmd_anim,
    "buttons": cmd_buttons,
    "board": cmd_board,
    "fxtex": cmd_fxtex,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS and sys.argv[1] != "all":
        print(__doc__)
        return
    if sys.argv[1] == "all":
        for name in ("prepare", "compose", "frames", "anim", "buttons", "board", "fxtex"):
            COMMANDS[name]()
    else:
        COMMANDS[sys.argv[1]]()


if __name__ == "__main__":
    main()
