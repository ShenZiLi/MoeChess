#!/usr/bin/env python3
"""
占位皮肤生成器（PLACEHOLDER）
为 birds/dogs/fish/hamsters/pandas 5 套皮肤生成与 cats 同结构的占位资源。
- 复制 cats 的全部 PNG，叠加主题色调以区分
- 改写 .tres 内的 res:// 路径指向新主题目录
- 复制 .tscn（kill_fx/killed_fx，无主题特定路径，直接复制）
- 生成 sfx.tres（7 音效全 null，is_placeholder=true 允许）
- 生成 theme.tres（引用本主题下的全部资源）

运行：python3 assets/themes/_gen_placeholder_themes.py
"""
import os
import shutil
from PIL import Image

CATS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cats")
THEMES_DIR = os.path.dirname(os.path.abspath(__file__))

THEMES = {
    "birds": {
        "name": "小鸟天空",
        "tint": (100, 150, 255, 70),
        "mapping": {
            "金丝雀": "king", "虎皮鹦鹉": "advisor", "玄凤": "elephant",
            "文鸟": "horse", "珍珠鸟": "chariot", "十姐妹": "cannon", "麻雀": "pawn",
        },
    },
    "dogs": {
        "name": "狗狗乐园",
        "tint": (180, 120, 60, 70),
        "mapping": {
            "金毛": "king", "拉布拉多": "advisor", "哈士奇": "elephant",
            "柯基": "horse", "柴犬": "chariot", "边牧": "cannon", "泰迪": "pawn",
        },
    },
    "fish": {
        "name": "鱼儿海洋",
        "tint": (80, 200, 220, 70),
        "mapping": {
            "锦鲤": "king", "金鱼": "advisor", "热带鱼": "elephant",
            "斗鱼": "horse", "龙鱼": "chariot", "斑马鱼": "cannon", "孔雀鱼": "pawn",
        },
    },
    "hamsters": {
        "name": "仓鼠庄园",
        "tint": (220, 180, 100, 70),
        "mapping": {
            "金丝熊": "king", "三线": "advisor", "紫仓": "elephant",
            "银狐": "horse", "布丁": "chariot", "奶茶": "cannon", "一线": "pawn",
        },
    },
    "pandas": {
        "name": "熊猫竹林",
        "tint": (200, 200, 200, 50),
        "mapping": {
            "大熊猫": "king", "小熊猫": "advisor", "赤狐": "elephant",
            "浣熊": "horse", "北极狐": "chariot", "雪貂": "cannon", "蜜袋鼯": "pawn",
        },
    },
}


def tint_image(src_path, dst_path, tint):
    img = Image.open(src_path).convert("RGBA")
    tint_layer = Image.new("RGBA", img.size, tint)
    result = Image.alpha_composite(img, tint_layer)
    result.save(dst_path)


def rewrite_tres(src_path, dst_path, old_theme, new_theme):
    with open(src_path, "r", encoding="utf-8") as f:
        content = f.read()
    content = content.replace(
        "res://assets/themes/%s/" % old_theme,
        "res://assets/themes/%s/" % new_theme,
    )
    with open(dst_path, "w", encoding="utf-8") as f:
        f.write(content)


def generate_theme(theme_id, config):
    theme_name = config["name"]
    tint = config["tint"]
    mapping = config["mapping"]
    dst_dir = os.path.join(THEMES_DIR, theme_id)
    print("Generating theme: %s (%s)" % (theme_id, theme_name))

    # 1. pieces/
    src_pieces = os.path.join(CATS_DIR, "pieces")
    dst_pieces = os.path.join(dst_dir, "pieces")
    for piece_name in os.listdir(src_pieces):
        src_piece_dir = os.path.join(src_pieces, piece_name)
        if not os.path.isdir(src_piece_dir):
            continue
        dst_piece_dir = os.path.join(dst_pieces, piece_name)
        os.makedirs(dst_piece_dir, exist_ok=True)
        for fname in os.listdir(src_piece_dir):
            src_f = os.path.join(src_piece_dir, fname)
            dst_f = os.path.join(dst_piece_dir, fname)
            if fname.endswith(".png"):
                tint_image(src_f, dst_f, tint)
            elif fname.endswith(".tres"):
                rewrite_tres(src_f, dst_f, "cats", theme_id)

    # 2. anim/
    src_anim = os.path.join(CATS_DIR, "anim")
    dst_anim = os.path.join(dst_dir, "anim")
    os.makedirs(dst_anim, exist_ok=True)
    for fname in os.listdir(src_anim):
        src_f = os.path.join(src_anim, fname)
        dst_f = os.path.join(dst_anim, fname)
        if fname.endswith(".png"):
            tint_image(src_f, dst_f, tint)
        elif fname.endswith(".tres"):
            rewrite_tres(src_f, dst_f, "cats", theme_id)

    # 3. ui/
    src_ui = os.path.join(CATS_DIR, "ui")
    dst_ui = os.path.join(dst_dir, "ui")
    os.makedirs(dst_ui, exist_ok=True)
    for fname in os.listdir(src_ui):
        if fname.endswith(".png"):
            tint_image(os.path.join(src_ui, fname), os.path.join(dst_ui, fname), tint)

    # 4. fx/
    src_fx = os.path.join(CATS_DIR, "fx")
    dst_fx = os.path.join(dst_dir, "fx")
    os.makedirs(dst_fx, exist_ok=True)
    for fname in os.listdir(src_fx):
        if fname.endswith(".tscn"):
            shutil.copy2(os.path.join(src_fx, fname), os.path.join(dst_fx, fname))

    # 5. sfx.tres
    sfx_content = (
        '[gd_resource type="ThemeSFXResource" script_class="ThemeSFXResource" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://scripts/theme/theme_sfx_resource.gd" id="1"]\n\n'
        "[resource]\n"
        "script = ExtResource(\"1\")\n"
        "formation_sfx = null\n"
        "select_sfx = null\n"
        "move_sfx = null\n"
        "kill_sfx = null\n"
        "killed_sfx = null\n"
        "victory_sfx = null\n"
        "defeat_sfx = null\n"
    )
    with open(os.path.join(dst_dir, "sfx.tres"), "w", encoding="utf-8") as f:
        f.write(sfx_content)

    # 6. theme.tres
    mapping_lines = []
    for breed, ptype in mapping.items():
        mapping_lines.append('"%s": "%s"' % (breed, ptype))
    mapping_str = ",\n".join(mapping_lines)

    piece_keys = [
        "red_king", "red_advisor", "red_elephant", "red_horse", "red_chariot", "red_cannon", "red_pawn",
        "black_king", "black_advisor", "black_elephant", "black_horse", "black_chariot", "black_cannon", "black_pawn",
    ]

    lines = []
    lines.append('[gd_resource type="ThemeResource" script_class="ThemeResource" load_steps=23 format=3]')
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://scripts/theme/theme_resource.gd" id="1"]')
    lines.append('[ext_resource type="Resource" path="res://assets/themes/%s/sfx.tres" id="2"]' % theme_id)
    lines.append('[ext_resource type="PackedScene" path="res://assets/themes/%s/fx/kill_fx.tscn" id="3"]' % theme_id)
    lines.append('[ext_resource type="PackedScene" path="res://assets/themes/%s/fx/killed_fx.tscn" id="4"]' % theme_id)
    lines.append('[ext_resource type="SpriteFrames" path="res://assets/themes/%s/anim/victory.tres" id="5"]' % theme_id)
    lines.append('[ext_resource type="SpriteFrames" path="res://assets/themes/%s/anim/defeat.tres" id="6"]' % theme_id)
    for i, key in enumerate(piece_keys):
        rid = str(7 + i)
        lines.append('[ext_resource type="SpriteFrames" path="res://assets/themes/%s/pieces/%s/%s.tres" id="%s"]' % (theme_id, key, key, rid))
    lines.append('[ext_resource type="Texture2D" path="res://assets/themes/%s/ui/speed_button_idle.png" id="21"]' % theme_id)
    lines.append('[ext_resource type="Texture2D" path="res://assets/themes/%s/ui/speed_button_fast.png" id="22"]' % theme_id)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1")')
    lines.append('theme_name = "%s"' % theme_name)
    lines.append('theme_id = "%s"' % theme_id)
    lines.append("is_placeholder = true")
    lines.append("pieces = {")
    for i, key in enumerate(piece_keys):
        rid = str(7 + i)
        comma = "," if i < len(piece_keys) - 1 else ""
        lines.append('"%s": ExtResource("%s")%s' % (key, rid, comma))
    lines.append("}")
    lines.append('kill_fx = ExtResource("3")')
    lines.append('killed_fx = ExtResource("4")')
    lines.append('victory_anim = ExtResource("5")')
    lines.append('defeat_anim = ExtResource("6")')
    lines.append('sfx = ExtResource("2")')
    lines.append("piece_mapping = {")
    lines.append(mapping_str)
    lines.append("}")
    lines.append('speed_button_idle = ExtResource("21")')
    lines.append('speed_button_fast = ExtResource("22")')
    lines.append("")

    with open(os.path.join(dst_dir, "theme.tres"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print("  Done: %s" % theme_id)


if __name__ == "__main__":
    for theme_id, config in THEMES.items():
        generate_theme(theme_id, config)
    print("All 5 placeholder themes generated.")
