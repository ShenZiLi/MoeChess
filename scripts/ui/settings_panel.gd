## 设置面板（用户偏好：皮肤/难度/音量/加速偏好）
## 关联：scripts/theme/theme_manager.gd、scripts/core/constants.gd、
##       docs/development/acceptance-standard.md G5（自动存档续局的"设置"字段）、docs/plans/2026-07-28-moechess-design.md §7.4
##
## 通过 load_settings/get_settings 与 SaveManager.load_settings/save_settings 配合持久化。
## 上层订阅 settings_changed 把新设置回写 SaveManager 并刷新当前主题；订阅 back_pressed 返回上一状态。
##
## 设置 Dictionary 字段约定：
##   {
##     "theme_id": "cats",
##     "difficulty": 2,             # CoreConstants.Difficulty 整数
##     "mode": 0,                   # SelectModePanel.MODE_PVE / MODE_PVP
##     "volume": 0.8,               # 0.0 ~ 1.0
##     "speed_mode": 0              # CoreConstants.SpeedMode.NORMAL / FAST
##   }
class_name SettingsPanel
extends Control

## 设置发生变化（用户调整任意选项时触发），参数为新的 settings Dictionary
signal settings_changed(settings: Dictionary)

## 选"返回"
signal back_pressed()

## 已知皮肤列表（theme_id → ThemeResource），由上层 set_themes 注入
var _themes: Dictionary = {}

## 当前设置缓存
var _settings: Dictionary = {}

@onready var _theme_option: OptionButton = $VBox/ThemeOption
@onready var _difficulty_option: OptionButton = $VBox/DifficultyOption
@onready var _volume_slider: HSlider = $VBox/VolumeSlider
@onready var _speed_option: OptionButton = $VBox/SpeedOption
@onready var _back_button: Button = $VBox/BackButton

func _ready() -> void:
	# 难度下拉：低 / 中 / 高
	_difficulty_option.add_item("低难度")
	_difficulty_option.set_item_metadata(0, CoreConstants.Difficulty.LOW)
	_difficulty_option.add_item("中难度")
	_difficulty_option.set_item_metadata(1, CoreConstants.Difficulty.MEDIUM)
	_difficulty_option.add_item("高难度")
	_difficulty_option.set_item_metadata(2, CoreConstants.Difficulty.HIGH)
	# 加速偏好下拉：正常 / 加速
	_speed_option.add_item("正常 (1x)")
	_speed_option.set_item_metadata(0, CoreConstants.SpeedMode.NORMAL)
	_speed_option.add_item("加速 (2x)")
	_speed_option.set_item_metadata(1, CoreConstants.SpeedMode.FAST)
	# 信号绑定：任意选项变化即发 settings_changed
	_theme_option.item_selected.connect(_on_any_changed)
	_difficulty_option.item_selected.connect(_on_any_changed)
	_volume_slider.value_changed.connect(_on_any_changed)
	_speed_option.item_selected.connect(_on_any_changed)
	_back_button.pressed.connect(func(): back_pressed.emit())

## 注入可选皮肤列表（通常来自 ThemeManager.list_themes()）
func set_themes(themes: Array) -> void:
	_theme_option.clear()
	_themes.clear()
	for t in themes:
		if t == null:
			continue
		var tr: ThemeResource = t as ThemeResource
		_theme_option.add_item("%s (%s)" % [tr.theme_name, tr.theme_id])
		_theme_option.set_item_metadata(_theme_option.item_count - 1, tr.theme_id)
		_themes[tr.theme_id] = tr

## 从 Dictionary 载入设置到 UI 控件
func load_settings(settings: Dictionary) -> void:
	_settings = settings.duplicate(true)
	# 皮肤
	var tid: String = String(_settings.get("theme_id", ""))
	for i in range(_theme_option.item_count):
		if String(_theme_option.get_item_metadata(i)) == tid:
			_theme_option.select(i)
			break
	# 难度
	var diff: int = int(_settings.get("difficulty", CoreConstants.Difficulty.MEDIUM))
	for i in range(_difficulty_option.item_count):
		if int(_difficulty_option.get_item_metadata(i)) == diff:
			_difficulty_option.select(i)
			break
	# 音量
	_volume_slider.value = float(_settings.get("volume", 0.8))
	# 加速偏好
	var sp: int = int(_settings.get("speed_mode", CoreConstants.SpeedMode.NORMAL))
	for i in range(_speed_option.item_count):
		if int(_speed_option.get_item_metadata(i)) == sp:
			_speed_option.select(i)
			break

## 收集当前 UI 控件值为 Dictionary
func get_settings() -> Dictionary:
	var out: Dictionary = {}
	var tidx: int = _theme_option.selected
	if tidx >= 0 and tidx < _theme_option.item_count:
		out["theme_id"] = String(_theme_option.get_item_metadata(tidx))
	else:
		out["theme_id"] = ""
	var didx: int = _difficulty_option.selected
	if didx >= 0 and didx < _difficulty_option.item_count:
		out["difficulty"] = int(_difficulty_option.get_item_metadata(didx))
	else:
		out["difficulty"] = CoreConstants.Difficulty.MEDIUM
	out["volume"] = float(_volume_slider.value)
	var sidx: int = _speed_option.selected
	if sidx >= 0 and sidx < _speed_option.item_count:
		out["speed_mode"] = int(_speed_option.get_item_metadata(sidx))
	else:
		out["speed_mode"] = CoreConstants.SpeedMode.NORMAL
	# 保留未在 UI 中暴露的字段（如 mode）
	if _settings.has("mode"):
		out["mode"] = _settings["mode"]
	return out

## 任意控件值变化时发 settings_changed
func _on_any_changed(_v: Variant = null) -> void:
	var new_settings: Dictionary = get_settings()
	_settings = new_settings
	settings_changed.emit(new_settings)
