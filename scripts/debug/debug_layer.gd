## 调试辅助层（Control 节点，默认关闭）
## 关联：docs/development/acceptance-standard.md I2-I4、docs/plans/2026-07-28-moechess-design.md §10.2、AGENTS.md（调试辅助层默认关闭红线）
##
## 显示：FPS、当前回合、AI 评估分、AI 思考耗时、棋盘坐标提示。
## 默认隐藏（visible = false）；正常视觉验收截图不出现。
##
## 开启方式（任一）：
##   1. 命令行参数 `--debug-overlay`
##   2. `DebugLayer.set_enabled(true)` 运行时调用
##
## 带调试辅助层的截图必须在文件名或报告里明确标注（I4）。
class_name DebugLayer
extends Control

const CMDLINE_FLAG: String = "--debug-overlay"

var _enabled: bool = false
var _label: Label = null
var _info: Dictionary = {}

func _ready() -> void:
	# 默认隐藏：正常视觉验收截图不出现调试辅助层（I3 红线）
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_label()
	_check_command_line()

## 开启/关闭调试辅助层
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	if _label != null:
		_label.visible = enabled
	_refresh_label()

## 当前是否开启
func is_enabled() -> bool:
	return _enabled

## 更新调试层显示信息
## data 可包含字段：fps / turn / ai_score / ai_think_ms / board_coord_hint
func update_info(data: Dictionary) -> void:
	for key in data.keys():
		_info[key] = data[key]
	_refresh_label()

## 设置棋盘坐标提示（如 "hover: (4,0)"）
func set_board_coord_hint(hint: String) -> void:
	_info["board_coord_hint"] = hint
	_refresh_label()

## 清空信息
func clear_info() -> void:
	_info.clear()
	_refresh_label()

func _process(_delta: float) -> void:
	if not _enabled:
		return
	# FPS 由 _process 每帧自动刷新
	_info["fps"] = Engine.get_frames_per_second()
	_refresh_label()

func _ensure_label() -> void:
	if _label != null:
		return
	_label = Label.new()
	_label.name = "DebugLabel"
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_label.offset_left = 8.0
	_label.offset_top = 8.0
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)

func _refresh_label() -> void:
	if _label == null or not _enabled:
		return
	var lines: Array = []
	lines.append("FPS: %s" % [str(_info.get("fps", "--"))])
	lines.append("Turn: %s" % [str(_info.get("turn", "--"))])
	lines.append("AI Score: %s" % [str(_info.get("ai_score", "--"))])
	lines.append("AI Think(ms): %s" % [str(_info.get("ai_think_ms", "--"))])
	if _info.has("board_coord_hint") and String(_info["board_coord_hint"]) != "":
		lines.append("Coord: %s" % [str(_info["board_coord_hint"])])
	_label.text = "\n".join(lines)

func _check_command_line() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	for a in args:
		if a == CMDLINE_FLAG:
			set_enabled(true)
			return
