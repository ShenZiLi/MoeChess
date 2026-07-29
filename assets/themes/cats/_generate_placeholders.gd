@tool
## 占位皮肤资源生成器（PLACEHOLDER）
## 关联：scripts/theme/theme_resource.gd、assets/README.md、docs/plans/2026-07-28-moechess-design.md §4
##
## 用途：当真实美术未就绪时，生成结构完整但视觉为占位的皮肤资源，让 validate_theme.gd 能跑通校验。
##
## 运行方式（二选一）：
##   1. Godot 编辑器 → File → Run → 选本脚本（EditorScript 模式）
##   2. 编辑器脚本编辑器中执行 _run()
##
## 生成内容（全部标注 PLACEHOLDER）：
##   - 14 棋子 × 5 状态 × 12 帧 = 840 张 PNG（512×512 透明背景 + 阵营色环 + 类型首字母）
##   - 14 SpriteFrames .tres（每片 5 动画，帧率 24fps，每状态 12 帧）
##   - ui/speed_button_idle.png + speed_button_fast.png（256×256）
##   - anim/victory.tres + anim/defeat.tres（SpriteFrames，1 动画 × 12 帧）
##
## 重要约束：
##   - 占位图必须可识别为占位，不能伪装成正式美术（颜色用占位色 + 字母 P 标识）
##   - 文件命名严格遵循 assets/README.md：{state}_{frame:03}.png
##   - 14 棋子键名严格遵循 ThemeResource.PIECE_KEYS
extends EditorScript

const SIZE_PIECE: int = 512
const SIZE_UI: int = 256
const FRAMES_PER_STATE: int = 12
const ANIM_FPS: float = 24.0

const PIECE_KEYS: Array[String] = [
	"red_king", "red_advisor", "red_elephant", "red_horse", "red_chariot", "red_cannon", "red_pawn",
	"black_king", "black_advisor", "black_elephant", "black_horse", "black_chariot", "black_cannon", "black_pawn",
]
const ANIM_STATES: Array[String] = ["idle", "selected", "moving", "killing", "killed"]

const COLOR_RED: Color = Color(0.90, 0.22, 0.22, 1.0)
const COLOR_BLACK: Color = Color(0.13, 0.13, 0.13, 1.0)
const COLOR_PLACEHOLDER_BG: Color = Color(0.85, 0.85, 0.85, 1.0)

# 类型→主体填充色（占位用，便于肉眼区分棋子种类）
const TYPE_COLORS: Dictionary = {
	"king": Color(0.95, 0.78, 0.20, 1.0),     # 金黄
	"advisor": Color(0.45, 0.75, 0.95, 1.0),  # 浅蓝
	"elephant": Color(0.55, 0.85, 0.55, 1.0), # 浅绿
	"horse": Color(0.80, 0.55, 0.85, 1.0),    # 浅紫
	"chariot": Color(0.95, 0.55, 0.40, 1.0),  # 橙红
	"cannon": Color(0.65, 0.45, 0.30, 1.0),   # 棕色
	"pawn": Color(0.75, 0.75, 0.78, 1.0),     # 浅灰
}

# 类型→首字母（占位标识，chariot 用 R 避开 cannon 的 C）
const TYPE_LETTER: Dictionary = {
	"king": "K", "advisor": "A", "elephant": "E", "horse": "H",
	"chariot": "R", "cannon": "C", "pawn": "P",
}

# 5×7 点阵字母（X=绘制像素，.=透明）
const LETTER_BITMAP: Dictionary = {
	"K": [".X..X", ".X.X.", ".XX..", ".X.X.", ".X..X", ".X..X", ".X..X"],
	"A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
	"E": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
	"H": ["X...X", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
	"R": ["XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"],
	"C": [".XXX.", "X...X", "X....", "X....", "X....", "X...X", ".XXX."],
	"P": ["XXXX.", "X...X", "X...X", "XXXX.", "X....", "X....", "X...."],
	# 加速按钮用
	"I": ["..X..", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."],
	"F": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...."],
}

## EditorScript 入口（File > Run 调用）
func _run() -> void:
	var theme_dir: String = "res://assets/themes/cats"
	print("[_generate_placeholders] generating into %s" % theme_dir)
	_generate_all_pieces(theme_dir)
	_generate_ui_buttons(theme_dir)
	_generate_victory_defeat(theme_dir)
	print("[_generate_placeholders] done. PLACEHOLDER resources ready for validate_theme.gd")

## 生成 14 棋子 PNG + SpriteFrames
func _generate_all_pieces(theme_dir: String) -> void:
	for piece_key in PIECE_KEYS:
		var side: String = piece_key.get_slice("_", 0)
		var type_key: String = piece_key.substr(side.length() + 1)
		var piece_dir: String = "%s/pieces/%s" % [theme_dir, piece_key]
		_ensure_dir(piece_dir)
		for state in ANIM_STATES:
			for frame_idx in range(1, FRAMES_PER_STATE + 1):
				var png_path: String = "%s/%s_%03d.png" % [piece_dir, state, frame_idx]
				var img: Image = _make_piece_image(side, type_key, state, frame_idx)
				img.save_png(png_path)
		# 生成 SpriteFrames .tres
		var sf: SpriteFrames = _build_sprite_frames(piece_dir, piece_key)
		var tres_path: String = "%s/%s.tres" % [piece_dir, piece_key]
		ResourceSaver.save(sf, tres_path)
		print("[_generate_placeholders] piece done: %s" % piece_key)

## 构造单棋子 SpriteFrames（5 动画 × 12 帧）
func _build_sprite_frames(piece_dir: String, piece_key: String) -> SpriteFrames:
	var sf: SpriteFrames = SpriteFrames.new()
	# SpriteFrames 默认带 "default" 动画，先删掉
	for anim in sf.get_animation_names():
		sf.remove_animation(anim)
	for state in ANIM_STATES:
		sf.add_animation(state)
		sf.set_animation_speed(state, ANIM_FPS)
		sf.set_animation_loop(state, state in ["idle", "moving"])
		for frame_idx in range(1, FRAMES_PER_STATE + 1):
			var png_path: String = "%s/%s_%03d.png" % [piece_dir, state, frame_idx]
			var tex: Texture2D = load(png_path)
			sf.add_frame(state, tex, 1.0)
	return sf

## 生成加速按钮头像（1x 悠闲 / 2x 着急）
func _generate_ui_buttons(theme_dir: String) -> void:
	var ui_dir: String = "%s/ui" % theme_dir
	_ensure_dir(ui_dir)
	var idle_img: Image = _make_ui_button_image(COLOR_RED, "I", false)
	idle_img.save_png("%s/speed_button_idle.png" % ui_dir)
	var fast_img: Image = _make_ui_button_image(COLOR_RED, "F", true)
	fast_img.save_png("%s/speed_button_fast.png" % ui_dir)

## 生成胜利/战败全队动画（每片 1 动画 × 12 帧）
func _generate_victory_defeat(theme_dir: String) -> void:
	var anim_dir: String = "%s/anim" % theme_dir
	_ensure_dir(anim_dir)
	# victory：金色帧序
	var victory_keys: Array[String] = ["V1", "V2"]
	_build_simple_anim(anim_dir, "victory", Color(0.95, 0.78, 0.20, 1.0))
	_build_simple_anim(anim_dir, "defeat", Color(0.40, 0.40, 0.45, 1.0))

func _build_simple_anim(anim_dir: String, anim_name: String, base_color: Color) -> void:
	for frame_idx in range(1, FRAMES_PER_STATE + 1):
		var img: Image = _make_solid_image(SIZE_PIECE, base_color, frame_idx)
		img.save_png("%s/%s_%03d.png" % [anim_dir, anim_name, frame_idx])
	var sf: SpriteFrames = SpriteFrames.new()
	for anim in sf.get_animation_names():
		sf.remove_animation(anim)
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, ANIM_FPS)
	sf.set_animation_loop(anim_name, false)
	for frame_idx in range(1, FRAMES_PER_STATE + 1):
		var png_path: String = "%s/%s_%03d.png" % [anim_dir, anim_name, frame_idx]
		sf.add_frame(anim_name, load(png_path), 1.0)
	ResourceSaver.save(sf, "%s/%s.tres" % [anim_dir, anim_name])

## 工具：确保目录存在
func _ensure_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path.get_base_dir())
	if dir == null:
		# 递归创建
		var abs_path: String = path
		var parts: PackedStringArray = abs_path.split("/", false)
		var cur: String = ""
		for p in parts:
			cur += "/" + p
			if not DirAccess.dir_exists_absolute(cur):
				DirAccess.make_dir_recursive_absolute(cur)
		return
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)

## 构造单张棋子占位图（512×512 透明 + 阵营色环 + 类型色填充 + 类型首字母）
func _make_piece_image(side: String, type_key: String, state: String, frame_idx: int) -> Image:
	var img: Image = Image.create(SIZE_PIECE, SIZE_PIECE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center: Vector2i = Vector2i(SIZE_PIECE / 2, SIZE_PIECE / 2)
	var fill_color: Color = TYPE_COLORS.get(type_key, Color.GRAY)
	# 状态影响填充亮度（让序列帧肉眼可见变化）
	fill_color = _tint_for_state(fill_color, state, frame_idx)
	var side_color: Color = COLOR_RED if side == "red" else COLOR_BLACK
	# 外环（阵营色，半径 220，厚 24）
	_draw_ring(img, center, 220, 24, side_color)
	# 主体圆（类型色，半径 196）
	_draw_disc(img, center, 196, fill_color)
	# 类型首字母（5×7 点阵，居中绘制）
	var letter: String = TYPE_LETTER.get(type_key, "?")
	_draw_letter(img, center, letter, side_color)
	# 帧序号（右下角小数字，便于占位识别）
	_draw_frame_marker(img, frame_idx, state)
	return img

## 构造加速按钮头像（256×256）
func _make_ui_button_image(side_color: Color, letter: String, fast: bool) -> Image:
	var img: Image = Image.create(SIZE_UI, SIZE_UI, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center: Vector2i = Vector2i(SIZE_UI / 2, SIZE_UI / 2)
	var fill_color: Color = Color(0.95, 0.85, 0.55, 1.0) if fast else Color(0.55, 0.75, 0.85, 1.0)
	_draw_disc(img, center, 110, fill_color)
	_draw_ring(img, center, 110, 8, side_color)
	_draw_letter(img, center, letter, Color(0.13, 0.13, 0.13, 1.0))
	return img

## 构造纯色全队动画帧
func _make_solid_image(size: int, base_color: Color, frame_idx: int) -> Image:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c: Color = base_color
	# 帧间轻微亮度变化，模拟动画
	c.v = clampf(c.v + (frame_idx - 6) * 0.03, 0.2, 1.0)
	img.fill(c)
	return img

## 状态色调（让占位序列帧肉眼可见）
func _tint_for_state(base: Color, state: String, frame_idx: int) -> Color:
	var c: Color = base
	match state:
		"idle":
			c.v = clampf(c.v + sin(frame_idx * 0.5) * 0.05, 0.2, 1.0)
		"selected":
			c.s = clampf(c.s + 0.15, 0.0, 1.0)
		"moving":
			c.h = fposmod(c.h + frame_idx * 0.01, 1.0)
		"killing":
			c.v = clampf(c.v + 0.15, 0.0, 1.0)
			c.s = clampf(c.s + 0.20, 0.0, 1.0)
		"killed":
			c.v = clampf(c.v - 0.25 - frame_idx * 0.02, 0.05, 1.0)
	return c

## 绘制实心圆
func _draw_disc(img: Image, center: Vector2i, radius: int, color: Color) -> void:
	var r2: int = radius * radius
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + y * y <= r2:
				img.set_pixel(center.x + x, center.y + y, color)

## 绘制圆环（外半径 r，厚度 thickness）
func _draw_ring(img: Image, center: Vector2i, r_outer: int, thickness: int, color: Color) -> void:
	var r_inner: int = r_outer - thickness
	var r2_out: int = r_outer * r_outer
	var r2_in: int = r_inner * r_inner
	for y in range(-r_outer, r_outer + 1):
		for x in range(-r_outer, r_outer + 1):
			var d2: int = x * x + y * y
			if d2 <= r2_out and d2 >= r2_in:
				img.set_pixel(center.x + x, center.y + y, color)

## 绘制 5×7 点阵字母（居中，每像素 16×16）
func _draw_letter(img: Image, center: Vector2i, letter: String, color: Color) -> void:
	var pattern: Array = LETTER_BITMAP.get(letter, [])
	if pattern.is_empty():
		return
	var px_size: int = 16
	var cols: int = 5
	var rows: int = 7
	var start_x: int = center.x - (cols * px_size) / 2
	var start_y: int = center.y - (rows * px_size) / 2
	for ry in range(rows):
		var row_str: String = pattern[ry]
		for rx in range(cols):
			if rx < row_str.length() and row_str[rx] == 'X':
				for dy in range(px_size):
					for dx in range(px_size):
						var px: int = start_x + rx * px_size + dx
						var py: int = start_y + ry * px_size + dy
						if px >= 0 and px < SIZE_PIECE and py >= 0 and py < SIZE_PIECE:
							img.set_pixel(px, py, color)

## 帧序号标识（右下角 3 位数字 + 状态首字母，占位识别用）
func _draw_frame_marker(img: Image, frame_idx: int, state: String) -> void:
	# 简化版：右下角画一个小方块 + 文字省略，靠 PNG 文件名识别帧
	var marker_color: Color = Color(1, 1, 1, 0.6)
	var x0: int = SIZE_PIECE - 60
	var y0: int = SIZE_PIECE - 30
	for y in range(0, 16):
		for x in range(0, 40):
			img.set_pixel(x0 + x, y0 + y, marker_color)
