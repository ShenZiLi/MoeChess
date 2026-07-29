## 皮肤选择面板（验收 F1：MainMenu→SelectTheme→SelectMode）
## 关联：scripts/theme/theme_manager.gd、scripts/theme/theme_resource.gd、
##       docs/plans/2026-07-28-moechess-design.md §4.1、§7.1
##
## 用 OptionButton/左右按钮在 6 类皮肤间轮播；set_themes 注入可选项，get_selected 返回当前 theme_id。
## 上层（GameStateMachine）订阅 theme_confirmed 切到 SelectMode；订阅 back_pressed 返回 MainMenu。
## 预览图细节由视觉层后续打磨（这里只确保数据流与信号契约正确）。
class_name SelectThemePanel
extends Control

## 玩家确认当前皮肤——参数为 theme_id
signal theme_confirmed(theme_id: String)

## 选"返回"——回 MainMenu
signal back_pressed()

## 当前可皮肤列表（Array[ThemeResource]）
var _themes: Array = []

## 当前选中的索引
var _selected_idx: int = 0

@onready var _theme_label: Label = $VBox/ThemeLabel
@onready var _prev_button: Button = $VBox/ButtonRow/PrevButton
@onready var _next_button: Button = $VBox/ButtonRow/NextButton
@onready var _select_button: Button = $VBox/ButtonRow/SelectButton
@onready var _back_button: Button = $VBox/BackButton

func _ready() -> void:
	_prev_button.pressed.connect(_on_prev)
	_next_button.pressed.connect(_on_next)
	_select_button.pressed.connect(_on_confirm)
	_back_button.pressed.connect(func(): back_pressed.emit())
	_refresh_ui()

## 注入可选皮肤列表（通常来自 ThemeManager.list_themes()）
## 优先尝试保留上次选择；列表为空则禁用确认按钮
func set_themes(themes: Array) -> void:
	_themes = themes.duplicate()
	_selected_idx = 0
	_refresh_ui()

## 返回当前选中的 theme_id（列表为空返回空字符串）
func get_selected() -> String:
	if _themes.is_empty() or _selected_idx < 0 or _selected_idx >= _themes.size():
		return ""
	var t: ThemeResource = _themes[_selected_idx]
	return t.theme_id if t != null else ""

## 返回当前选中的 ThemeResource（可空）
func get_selected_theme() -> ThemeResource:
	if _themes.is_empty() or _selected_idx < 0 or _selected_idx >= _themes.size():
		return null
	return _themes[_selected_idx]

func _on_prev() -> void:
	if _themes.size() <= 1:
		return
	_selected_idx = (_selected_idx - 1 + _themes.size()) % _themes.size()
	_refresh_ui()

func _on_next() -> void:
	if _themes.size() <= 1:
		return
	_selected_idx = (_selected_idx + 1) % _themes.size()
	_refresh_ui()

func _on_confirm() -> void:
	var tid: String = get_selected()
	if tid.is_empty():
		return
	theme_confirmed.emit(tid)

## 刷新当前皮肤名展示与按钮可用性
func _refresh_ui() -> void:
	if _themes.is_empty():
		_theme_label.text = "（无皮肤）"
		_prev_button.disabled = true
		_next_button.disabled = true
		_select_button.disabled = true
		return
	_prev_button.disabled = _themes.size() <= 1
	_next_button.disabled = _themes.size() <= 1
	_select_button.disabled = false
	var t: ThemeResource = _themes[_selected_idx]
	if t == null:
		_theme_label.text = "（皮肤损坏）"
		return
	_theme_label.text = "%s\n(%d / %d)" % [t.theme_name, _selected_idx + 1, _themes.size()]
