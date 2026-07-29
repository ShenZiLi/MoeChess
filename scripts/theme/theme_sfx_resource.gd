## 皮肤音效资源（7 项 AudioStream，皮肤级统一，动作级差异化）
## 关联：scripts/theme/theme_resource.gd、docs/plans/2026-07-28-moechess-design.md §4.6、assets/README.md
##
## 字段对应 assets/themes/{id}/audio/ 下的固定 7 个文件名：
## formation.wav / select.wav / move.wav / kill.wav / killed.wav / victory.wav / defeat.wav
class_name ThemeSFXResource
extends Resource

## 列阵/视角切换音效（双人对战换边时触发）
@export var formation_sfx: AudioStream

## 选中棋子音效
@export var select_sfx: AudioStream

## 移动/落子音效
@export var move_sfx: AudioStream

## 主动击杀音效
@export var kill_sfx: AudioStream

## 被击杀音效
@export var killed_sfx: AudioStream

## 胜利音效
@export var victory_sfx: AudioStream

## 战败音效
@export var defeat_sfx: AudioStream

## 校验：7 项音效字段是否全部非空
## 校验脚本在 placeholder 模式下可跳过此检查（由 ThemeResource.is_placeholder 控制）
func is_complete() -> bool:
	return formation_sfx != null \
		and select_sfx != null \
		and move_sfx != null \
		and kill_sfx != null \
		and killed_sfx != null \
		and victory_sfx != null \
		and defeat_sfx != null

## 缺失项列表（供 validate_theme.gd 输出诊断）
func missing_fields() -> Array:
	var missing: Array = []
	if formation_sfx == null:
		missing.append("formation_sfx")
	if select_sfx == null:
		missing.append("select_sfx")
	if move_sfx == null:
		missing.append("move_sfx")
	if kill_sfx == null:
		missing.append("kill_sfx")
	if killed_sfx == null:
		missing.append("killed_sfx")
	if victory_sfx == null:
		missing.append("victory_sfx")
	if defeat_sfx == null:
		missing.append("defeat_sfx")
	return missing
