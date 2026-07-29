## 皮肤资源（数据驱动皮肤系统的入口资源）
## 关联：scripts/theme/theme_sfx_resource.gd、scripts/theme/theme_manager.gd、
##       docs/plans/2026-07-28-moechess-design.md §4.3、assets/README.md
##
## 一个 ThemeResource 实例 = 一套完整皮肤，存放于 assets/themes/{theme_id}/theme.tres。
## 新增皮肤只加目录 + theme.tres，零代码改动（ThemeManager 自动扫描登记）。
##
## 14 棋子键名（与 CoreConstants.TYPE_TO_KEY / SIDE_TO_KEY 对齐，固定）：
##   red_king / red_advisor / red_elephant / red_horse / red_chariot / red_cannon / red_pawn
##   black_king / black_advisor / black_elephant / black_horse / black_chariot / black_cannon / black_pawn
##
## 每个 SpriteFrames 含 5 动画状态（与 CoreConstants.AnimState 对齐）：
##   idle / selected / moving / killing / killed
class_name ThemeResource
extends Resource

## 显示名（如 "猫咪乐园"）
@export var theme_name: String

## 标识（如 "cats"，与目录名一致）
@export var theme_id: String

## 是否占位皮肤（PLACEHOLDER）
## true = 资源结构齐全但美术为程序化生成的占位图，validate_theme.gd 应允许跳过音效检查
## 等项目交付正式美术前不得设为 false
@export var is_placeholder: bool = false

## 14 项 SpriteFrames，键名 "{side}_{type}"（如 "red_king"）
@export var pieces: Dictionary

## 主动击杀特效场景
@export var kill_fx: PackedScene

## 被击杀特效场景
@export var killed_fx: PackedScene

## 胜利全队动画（SpriteFrames，动画名 "victory"）
@export var victory_anim: SpriteFrames

## 战败全队动画（SpriteFrames，动画名 "defeat"）
@export var defeat_anim: SpriteFrames

## 七音效集
@export var sfx: ThemeSFXResource

## 品种→棋子类型映射说明（设计文档 §4.1，皮肤特色来源）
## 例：{"布偶": "king", "英短": "chariot", "橘猫": "cannon", ...}
@export var piece_mapping: Dictionary

## 加速按钮悠闲表情头像（1x 速度）
@export var speed_button_idle: Texture2D

## 加速按钮着急表情头像（2x 速度）
@export var speed_button_fast: Texture2D

## 14 棋子键名清单（校验脚本与 ThemeManager 共用）
const PIECE_KEYS: Array[String] = [
	"red_king", "red_advisor", "red_elephant", "red_horse", "red_chariot", "red_cannon", "red_pawn",
	"black_king", "black_advisor", "black_elephant", "black_horse", "black_chariot", "black_cannon", "black_pawn",
]

## 5 动画状态名（与 SpriteFrames 内动画名一致）
const ANIM_STATES: Array[String] = ["idle", "selected", "moving", "killing", "killed"]

## 每状态最少帧数（assets/README.md 规格下限）
const MIN_FRAMES_PER_STATE: int = 12

## 校验：14 棋子键齐全
func has_all_piece_keys() -> bool:
	for key in PIECE_KEYS:
		if not pieces.has(key) or pieces[key] == null:
			return false
	return true

## 校验：每个 SpriteFrames 含 5 状态且帧数达标
## 返回 Array，空数组表示全部通过；非空时为诊断信息
func validate_piece_animations() -> Array:
	var issues: Array = []
	for key in PIECE_KEYS:
		if not pieces.has(key) or pieces[key] == null:
			issues.append("%s: missing SpriteFrames" % key)
			continue
		var sf: SpriteFrames = pieces[key]
		for state in ANIM_STATES:
			if not sf.has_animation(state):
				issues.append("%s/%s: missing animation" % [key, state])
				continue
			var frame_count: int = sf.get_frame_count(state)
			if frame_count < MIN_FRAMES_PER_STATE:
				issues.append("%s/%s: only %d frames (need >= %d)" % [key, state, frame_count, MIN_FRAMES_PER_STATE])
	return issues

## 校验：皮肤级资源（特效/全队动画/UI 头像）齐全
func validate_theme_level_resources() -> Array:
	var issues: Array = []
	if kill_fx == null:
		issues.append("kill_fx: null")
	if killed_fx == null:
		issues.append("killed_fx: null")
	if victory_anim == null:
		issues.append("victory_anim: null")
	elif not victory_anim.has_animation("victory"):
		issues.append("victory_anim: missing 'victory' animation")
	if defeat_anim == null:
		issues.append("defeat_anim: null")
	elif not defeat_anim.has_animation("defeat"):
		issues.append("defeat_anim: missing 'defeat' animation")
	if speed_button_idle == null:
		issues.append("speed_button_idle: null")
	if speed_button_fast == null:
		issues.append("speed_button_fast: null")
	return issues

## 校验：音效字段（placeholder 模式下允许缺失）
func validate_sfx(allow_placeholder: bool = false) -> Array:
	if sfx == null:
		return ["sfx: null ThemeSFXResource"]
	if allow_placeholder and is_placeholder:
		return []
	return sfx.missing_fields().map(func(field): return "sfx/%s: null" % field)

## 综合校验：返回所有问题（供 validate_theme.gd 调用）
## allow_placeholder_sfx = true 时，placeholder 皮肤跳过音效检查
func validate_all(allow_placeholder_sfx: bool = true) -> Array:
	var issues: Array = []
	issues.append_array(validate_theme_level_resources())
	issues.append_array(validate_piece_animations())
	issues.append_array(validate_sfx(allow_placeholder_sfx))
	return issues

func _to_string() -> String:
	var tag: String = " [PLACEHOLDER]" if is_placeholder else ""
	return "ThemeResource(id=%s, name=%s, pieces=%d)%s" % [theme_id, theme_name, pieces.size(), tag]
