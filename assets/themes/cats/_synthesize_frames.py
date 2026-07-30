#!/usr/bin/env python3
## 猫猫棋子帧序列合成器（正式美术）
## 关联：assets/README.md、docs/plans/2026-07-28-moechess-design.md §8、docs/experience-library/README.md EX-007
##
## 用途：从 _keyframes/{piece}.png（AI 生成的绿幕关键帧）合成 5 状态 × 12 帧 = 60 张 PNG/棋子，
##       覆盖 pieces/{piece}/{state}_{frame:03}.png 占位图。
##
## 流程：
##   1. 读取绿幕关键帧，chroma-key 抠除绿色背景 → RGBA
##   2. despill 去除边缘绿色溢出
##   3. 裁剪到主体 bbox + 边距，缩放到 BASE_FIT(460) 居中放到 512×512 透明画布 → base
##   4. 从 base 合成 5 状态 × 12 帧：
##        idle     呼吸缩放（scale 1.0↔1.02，循环）
##        selected 提亮+饱和+轻微上跳
##        moving   横向摇摆 ±6px + 微旋 ±2°（循环）
##        killing  前冲 tx 0→8→0 + 闪光
##        killed   旋转 0→75° + 淡出 α 1.0→0.25 + 去饱和
##   5. 覆盖写入 pieces/{piece}/{state}_{frame:03}.png
##
## 运行：python3 _synthesize_frames.py [piece_key ...]  （无参数=全部 14 片）
import os, sys, math
import numpy as np
from PIL import Image, ImageFilter

THEME_DIR = os.path.dirname(os.path.abspath(__file__))
KEY_DIR   = os.path.join(THEME_DIR, "_keyframes")
PIECES_DIR= os.path.join(THEME_DIR, "pieces")

OUT_SIZE   = 512      # 输出帧尺寸
BASE_FIT   = 460      # 主体缩放到此尺寸（留 26px 边距给 scale-up 不裁切）
FRAMES     = 12       # 每状态帧数
STATES     = ["idle", "selected", "moving", "killing", "killed"]

PIECE_KEYS = [
    "red_king","red_advisor","red_elephant","red_horse","red_chariot","red_cannon","red_pawn",
    "black_king","black_advisor","black_elephant","black_horse","black_chariot","black_cannon","black_pawn",
]

# ---------- chroma key ----------
def chroma_key_green(rgb_np):
    """rgb_np: HxWx3 uint8. 返回 HxWx4 uint8 RGBA，绿色背景→透明。"""
    r = rgb_np[:,:,0].astype(int); g = rgb_np[:,:,1].astype(int); b = rgb_np[:,:,2].astype(int)
    # 绿色判定：g 显著大于 r 和 b
    green_dom = (g > 90) & (g > r + 25) & (g > b + 25)
    # 软阈值：越绿越透明，用 g - max(r,b) 作为强度
    excess = np.clip((g - np.maximum(r, b)).astype(float), 0, None)
    alpha = np.clip(255.0 - excess * 3.0, 0, 255).astype(np.uint8)
    alpha = np.where(green_dom, np.minimum(alpha, 0), 255).astype(np.uint8)
    # 防止残留：纯绿区域强制全透明
    rgba = np.dstack([rgb_np, alpha])
    return rgba

def despill(rgba_np):
    """去除主体边缘绿色溢出：把 g 压到 <= max(r,b)+8。"""
    out = rgba_np.copy()
    r = out[:,:,0].astype(int); g = out[:,:,1].astype(int); b = out[:,:,2].astype(int); a = out[:,:,3]
    maxrb = np.maximum(r, b)
    over = g > maxrb + 8
    out[:,:,1] = np.where(over, np.clip(maxrb + 8, 0, 255).astype(np.uint8), out[:,:,1])
    return out

def crop_to_alpha(rgba_np, pad_frac=0.06):
    """裁剪到 alpha>0 的 bbox + 边距，返回正方形 RGBA。"""
    a = rgba_np[:,:,3]
    ys, xs = np.where(a > 8)
    if len(xs) == 0:
        # 全透明：返回原尺寸
        return rgba_np
    x0, x1 = xs.min(), xs.max(); y0, y1 = ys.min(), ys.max()
    w = x1 - x0; h = y1 - y0
    pad = int(max(w, h) * pad_frac)
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
    x1 = min(rgba_np.shape[1] - 1, x1 + pad); y1 = min(rgba_np.shape[0] - 1, y1 + pad)
    crop = rgba_np[y0:y1+1, x0:x1+1]
    # 正方形化（取较大边，居中放到透明画布）
    ch, cw = crop.shape[:2]
    side = max(ch, cw)
    canvas = np.zeros((side, side, 4), dtype=np.uint8)
    oy = (side - ch) // 2; ox = (side - cw) // 2
    canvas[oy:oy+ch, ox:ox+cw] = crop
    return canvas

def make_base(keyframe_path):
    """关键帧 → 512×512 居中 RGBA base（主体缩放到 BASE_FIT）。"""
    im = Image.open(keyframe_path).convert("RGB")
    rgb = np.array(im)
    rgba = chroma_key_green(rgb)
    rgba = despill(rgba)
    # 轻微模糊 alpha 边缘去锯齿
    a_img = Image.fromarray(rgba[:,:,3]).filter(ImageFilter.GaussianBlur(0.8))
    rgba[:,:,3] = np.array(a_img)
    crop = crop_to_alpha(rgba, pad_frac=0.08)
    # 缩放到 BASE_FIT 居中放到 OUT_SIZE 画布
    ch, cw = crop.shape[:2]
    scale = BASE_FIT / max(ch, cw)
    nw = max(1, int(round(cw * scale))); nh = max(1, int(round(ch * scale)))
    im_crop = Image.fromarray(crop, mode="RGBA").resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (OUT_SIZE, OUT_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(im_crop, ((OUT_SIZE - nw) // 2, (OUT_SIZE - nh) // 2))
    return np.array(canvas)

# ---------- color adjust ----------
def adjust_color(rgba_np, brightness=1.0, saturation=1.0, alpha_mul=1.0):
    out = rgba_np.astype(np.float32).copy()
    rgb = out[:,:,:3]; a = out[:,:,3]
    # brightness
    rgb = rgb * brightness
    # saturation：向灰度靠拢
    gray = rgb.mean(axis=2, keepdims=True)
    rgb = gray + (rgb - gray) * saturation
    out[:,:,:3] = np.clip(rgb, 0, 255)
    out[:,:,3] = np.clip(a * alpha_mul, 0, 255)
    return out.astype(np.uint8)

# ---------- geometry ----------
def transform(base_rgba_np, scale=1.0, rotate_deg=0.0, tx=0, ty=0):
    """对 base 做缩放/旋转/平移，返回 512×512 RGBA。"""
    im = Image.fromarray(base_rgba_np, mode="RGBA")
    s = max(0.05, scale)
    nw = max(1, int(round(OUT_SIZE * s))); nh = max(1, int(round(OUT_SIZE * s)))
    im_s = im.resize((nw, nh), Image.LANCZOS)
    if rotate_deg != 0.0:
        im_s = im_s.rotate(rotate_deg, resample=Image.BICUBIC, expand=False, fillcolor=(0,0,0,0))
    canvas = Image.new("RGBA", (OUT_SIZE, OUT_SIZE), (0,0,0,0))
    canvas.alpha_composite(im_s, ((OUT_SIZE - nw)//2 + tx, (OUT_SIZE - nh)//2 + ty))
    return np.array(canvas)

def to_png(rgba_np, path):
    Image.fromarray(rgba_np, mode="RGBA").save(path)

# ---------- per-state synthesis ----------
def synth_idle(base, i, n):
    t = i / n
    s = 1.0 + 0.02 * math.sin(2 * math.pi * t)
    return transform(base, scale=s)

def synth_selected(base, i, n):
    t = i / (n - 1)
    # 上跳：先向上再回落
    ty = int(round(-8 * math.sin(math.pi * t)))
    s = 1.0 + 0.03 * math.sin(math.pi * t)
    fr = adjust_color(base, brightness=1.12, saturation=1.25)
    return transform(fr, scale=s, ty=ty)

def synth_moving(base, i, n):
    t = i / n
    tx = int(round(6 * math.sin(2 * math.pi * t)))
    rot = 2.0 * math.sin(2 * math.pi * t)
    return transform(base, rotate_deg=rot, tx=tx)

def synth_killing(base, i, n):
    t = i / (n - 1)
    # 前冲：0→8→0
    tx = int(round(8 * math.sin(math.pi * t)))
    # 闪光：中段最亮
    flash = 1.0 + 0.30 * math.sin(math.pi * t)
    fr = adjust_color(base, brightness=flash, saturation=1.15)
    return transform(fr, tx=tx)

def synth_killed(base, i, n):
    t = i / (n - 1)
    rot = 75.0 * t
    alpha_mul = 1.0 - 0.75 * t
    sat = 1.0 - 0.6 * t
    fr = adjust_color(base, saturation=sat, alpha_mul=alpha_mul)
    return transform(fr, rotate_deg=rot)

SYNTH = {
    "idle": synth_idle,
    "selected": synth_selected,
    "moving": synth_moving,
    "killing": synth_killing,
    "killed": synth_killed,
}

def process_piece(piece_key, save=True):
    key_path = os.path.join(KEY_DIR, piece_key + ".png")
    if not os.path.exists(key_path):
        print("[skip] keyframe missing:", key_path)
        return False
    base = make_base(key_path)
    if save:
        out_dir = os.path.join(PIECES_DIR, piece_key)
        os.makedirs(out_dir, exist_ok=True)
    count = 0
    for state in STATES:
        fn = SYNTH[state]
        for i in range(FRAMES):
            frame = fn(base, i, FRAMES)
            if save:
                p = os.path.join(out_dir, "%s_%03d.png" % (state, i + 1))
                to_png(frame, p)
                count += 1
    print("[done] %s : %d frames" % (piece_key, count))
    return True

def main():
    args = sys.argv[1:]
    keys = args if args else PIECE_KEYS
    ok = 0
    for k in keys:
        if process_piece(k):
            ok += 1
    print("processed %d/%d pieces" % (ok, len(keys)))

if __name__ == "__main__":
    main()
