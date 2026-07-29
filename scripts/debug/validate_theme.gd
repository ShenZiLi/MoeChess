## 皮肤校验脚本（验收 C8 / I5）
## 关联：docs/development/acceptance-standard.md C8/I5、docs/plans/2026-07-28-moechess-design.md §8.4、assets/README.md
##
## 扫描 `res://assets/themes/*/theme.tres`，校验：
## - 14 棋子目录齐全（7 类型 × 2 阵营，键名 `{side}_{type}`）
## - 每棋子 5 状态齐全（idle/selected/moving/killing/killed）
## - 每状态帧数 ≥ 12
## - 帧序列命名规范（{state}_{frame:03}.png）
## - theme.tres 资源引用有效（pieces 14 项 / kill_fx / killed_fx / victory_anim / defeat_anim）
## - 音效 7 项齐全（formation/select/move/kill/killed/victory/defeat）
## - 加速按钮头像 2 项齐全（speed_button_idle / speed_button_fast）
##
## 命令行运行：`godot --script scripts/debug/validate_theme.gd`
## 输出 JSON：`{"themes": [{"id":"cats","valid":true,"errors":[]}], "all_valid": true}`
##
## GUT 调用：`ValidateTheme.validate_all()` 返回同结构 Dictionary
class_name ValidateTheme
extends RefCounted

const THEMES_DIR: String = "res://assets/themes"
const THEME_FILE_NAME: String = "theme.tres"

const REQUIRED_PIECES: Array = [
	"red_king", "red_advisor", "red_elephant", "red_horse", "red_chariot", "red_cannon", "red_pawn",
	"black_king", "black_advisor", "black_elephant", "black_horse", "black_chariot", "black_cannon", "black_pawn",
]
const REQUIRED_STATES: Array = ["idle", "selected", "moving", "killing", "killed"]
const MIN_FRAMES_PER_STATE: int = 12
const REQUIRED_SFX: Array = ["formation", "select", "move", "kill", "killed", "victory", "defeat"]
const REQUIRED_SPEED_BUTTONS: Array = ["speed_button_idle", "speed_button_fast"]
const REQUIRED_FX: Array = ["kill_fx", "killed_fx", "victory_anim", "defeat_anim"]

## 校验所有皮肤，返回 JSON 报告字典
static func validate_all() -> Dictionary:
	var themes: Array = []
	var all_valid: bool = true
	var dir: DirAccess = DirAccess.open(THEMES_DIR)
	if dir == null:
		return {
			"themes": [],
			"all_valid": false,
			"errors": ["themes directory not found: %s" % THEMES_DIR],
		}
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.dir_exists(name) and not name.begins_with("."):
			var theme_path: String = "%s/%s/%s" % [THEMES_DIR, name, THEME_FILE_NAME]
			var report: Dictionary = validate_theme(theme_path)
			themes.append(report)
			if not bool(report.get("valid", false)):
				all_valid = false
		name = dir.get_next()
	dir.list_dir_end()
	themes.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return {
		"themes": themes,
		"all_valid": all_valid,
	}

## 校验单个皮肤目录（传入 theme.tres 路径）
static func validate_theme(theme_tres_path: String) -> Dictionary:
	var errors: Array = []
	var theme_id: String = ""
	var theme_name: String = ""

	# 1. 加载 theme.tres
	if not ResourceLoader.exists(theme_tres_path):
		errors.append("theme.tres missing or invalid: %s" % theme_tres_path)
		return {
			"id": theme_id,
			"name": theme_name,
			"path": theme_tres_path,
			"valid": false,
			"errors": errors,
		}
	var res: Resource = load(theme_tres_path)
	if res == null:
		errors.append("theme.tres load failed: %s" % theme_tres_path)
		return {
			"id": theme_id,
			"name": theme_name,
			"path": theme_tres_path,
			"valid": false,
			"errors": errors,
		}

	theme_id = String(res.get("theme_id"))
	theme_name = String(res.get("theme_name"))
	if theme_id == "":
		errors.append("theme_id is empty")

	var theme_dir: String = theme_tres_path.get_base_dir()

	# 2. 校验 14 棋子目录 + 帧序列
	for piece_key in REQUIRED_PIECES:
		var piece_dir: String = "%s/pieces/%s" % [theme_dir, piece_key]
		if not DirAccess.dir_exists_absolute(piece_dir):
			errors.append("piece dir missing: pieces/%s" % piece_key)
			continue
		for state_key in REQUIRED_STATES:
			var frames: Array = _list_frames(piece_dir, state_key)
			if frames.is_empty():
				errors.append("state frames missing: pieces/%s/%s" % [piece_key, state_key])
			elif frames.size() < MIN_FRAMES_PER_STATE:
				errors.append("state frames insufficient: pieces/%s/%s (%d < %d)" % [piece_key, state_key, frames.size(), MIN_FRAMES_PER_STATE])
			# 命名规范校验（已由 _list_frames 过滤前缀+扩展；这里再校验 frame 序号连续性）
			var naming_ok: bool = _check_naming(frames, state_key)
			if not naming_ok:
				errors.append("frame naming invalid: pieces/%s/%s (expected %s_001.png..)" % [piece_key, state_key, state_key])

	# 3. 校验 theme.tres 中 pieces 字段引用有效（14 项 SpriteFrames，无 null）
	var pieces_dict: Variant = res.get("pieces")
	if pieces_dict == null or typeof(pieces_dict) != TYPE_DICTIONARY:
		errors.append("theme.tres pieces field missing or not Dictionary")
	else:
		var pd: Dictionary = pieces_dict
		for piece_key in REQUIRED_PIECES:
			if not pd.has(piece_key):
				errors.append("theme.tres pieces missing entry: %s" % piece_key)
			elif pd[piece_key] == null:
				errors.append("theme.tres pieces null ref: %s" % piece_key)

	# 4. 校验特效 / 全队动画引用
	for fx_key in REQUIRED_FX:
		if res.get(fx_key) == null:
			errors.append("%s missing" % fx_key)

	# 5. 校验音效 7 项
	#    placeholder 皮肤（is_placeholder=true）允许音效字段为 null，与 ThemeResource.validate_sfx 对齐
	var sfx_res: Variant = res.get("sfx")
	if sfx_res == null:
		errors.append("sfx resource missing")
	else:
		var is_placeholder: bool = bool(res.get("is_placeholder", false))
		if not is_placeholder:
			for sfx_key in REQUIRED_SFX:
				if sfx_res.get(sfx_key) == null:
					errors.append("sfx missing: %s" % sfx_key)

	# 6. 校验加速按钮头像 2 项
	for btn_key in REQUIRED_SPEED_BUTTONS:
		if res.get(btn_key) == null:
			errors.append("speed button missing: %s" % btn_key)

	return {
		"id": theme_id,
		"name": theme_name,
		"path": theme_tres_path,
		"valid": errors.is_empty(),
		"errors": errors,
	}

## 列出某棋子目录下指定状态的帧文件（命名 {state}_{frame:03}.png）
static func _list_frames(piece_dir: String, state_key: String) -> Array:
	var frames: Array = []
	var dir: DirAccess = DirAccess.open(piece_dir)
	if dir == null:
		return frames
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if dir.file_exists(fname) and fname.begins_with(state_key + "_") and fname.ends_with(".png"):
			frames.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	frames.sort()
	return frames

## 校验帧序列命名规范：{state}_{frame:03}.png，frame 从 001 起连续
static func _check_naming(frames: Array, state_key: String) -> bool:
	if frames.is_empty():
		return false
	for i in range(frames.size()):
		var expected: String = "%s_%03d.png" % [state_key, i + 1]
		if frames[i] != expected:
			return false
	return true

## 命令行入口
static func main() -> int:
	var report: Dictionary = validate_all()
	print(JSON.stringify(report))
	return 0 if bool(report.get("all_valid", false)) else 1

func _init() -> void:
	# 命令行运行检测：当本脚本被 `godot --script .../validate_theme.gd` 直接运行时执行入口
	var args: PackedStringArray = OS.get_cmdline_args()
	var is_main: bool = false
	for arg in args:
		if arg.ends_with("validate_theme.gd"):
			is_main = true
			break
	if is_main:
		var report: Dictionary = validate_all()
		print(JSON.stringify(report))
		var exit_code: int = 0 if bool(report.get("all_valid", false)) else 1
		if Engine.get_main_loop() != null:
			Engine.get_main_loop().quit(exit_code)
