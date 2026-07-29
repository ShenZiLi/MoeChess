## 对局中 HUD（验收 E3/E4/F2/F3）
## 关联：scripts/core/constants.gd、scripts/theme/theme_resource.gd、
##       docs/development/acceptance-standard.md E3/E4/F2/F3、docs/plans/2026-07-28-moechess-design.md §4.7、§7.2
##
## 顶部信息条：当前回合提示 + 加速按钮（1x⇄2x，头像跟随皮肤，E4）+ 暂停按钮（F2）。
## 加速按钮使用 TextureButton，正常速度显示 speed_button_idle，加速时显示 speed_button_fast。
## 点按加速按钮发 speed_toggled 信号，由 Playing 状态机切换 SpeedMode 后回灌 set_speed_mode。
## 点按暂停按钮发 pause_pressed 信号，由状态机切到 Paused。
class_name HUD
extends Control

## 加速按钮被点按——切 NORMAL ⇄ FAST
signal speed_toggled()

## 暂停按钮被点按——进入 Paused
signal pause_pressed()

## 当前主题资源（用于刷新加速按钮头像）
var _theme: ThemeResource = null

## 当前速度模式（默认 NORMAL）
var _speed_mode: int = CoreConstants.SpeedMode.NORMAL

@onready var _turn_label: Label = $Margin/TopBar/TurnLabel
@onready var _speed_button: TextureButton = $Margin/TopBar/SpeedButton
@onready var _pause_button: Button = $Margin/TopBar/PauseButton

func _ready() -> void:
	_speed_button.pressed.connect(func(): speed_toggled.emit())
	_pause_button.pressed.connect(func(): pause_pressed.emit())
	_apply_speed_button_texture()

## 设置当前行动方（CoreConstants.Side.RED / BLACK）
## 显示"红方走棋" / "黑方走棋"
func set_turn(side: int) -> void:
	match side:
		CoreConstants.Side.RED:
			_turn_label.text = "红方走棋"
		CoreConstants.Side.BLACK:
			_turn_label.text = "黑方走棋"
		_:
			_turn_label.text = ""

## 设置加速按钮状态（CoreConstants.SpeedMode.NORMAL / FAST）
## 切换头像为 idle 或 fast（E4）
func set_speed_mode(mode: int) -> void:
	_speed_mode = mode
	_apply_speed_button_texture()

## 设置当前主题（更新加速按钮头像，E4：跟随皮肤）
## 注意：函数名不能是 set_theme——会覆盖 Control.set_theme(Theme) 属性 setter
func set_theme_resource(theme: ThemeResource) -> void:
	_theme = theme
	_apply_speed_button_texture()

## 显示"思考中"提示（B6：AI 计算中显示思考中）
func show_thinking(thinking: bool) -> void:
	if thinking:
		_turn_label.text = "思考中…"
	# 不思考时由 set_turn 重新设置正确文本

## 启用/禁用加速按钮（动画播放中可短暂禁用）
func set_speed_button_interactive(enabled: bool) -> void:
	_speed_button.disabled = not enabled

## 根据当前 theme + speed_mode 选择正确的 TextureButton.texture_normal
func _apply_speed_button_texture() -> void:
	var tex: Texture2D = null
	if _theme != null:
		tex = _theme.speed_button_fast if _speed_mode == CoreConstants.SpeedMode.FAST else _theme.speed_button_idle
	_speed_button.texture_normal = tex
