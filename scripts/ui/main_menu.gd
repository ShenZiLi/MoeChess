## 主菜单（验收 F1：Boot→MainMenu 流转入口）
## 关联：scripts/theme/theme_manager.gd、docs/plans/2026-07-28-moechess-design.md §7.1
##
## 提供开始/图鉴/设置/退出四个入口；点按按钮发对应信号，由 GameStateMachine 切换状态。
## 视觉布局：标题在上，按钮 VBox 居中。具体美术风格由 visual-reviewer 后续打磨。
class_name MainMenu
extends Control

## 选"开始"——切到 SelectTheme
signal start_pressed()

## 选"图鉴"——切到 Codex
signal codex_pressed()

## 选"设置"——切到 Settings
signal settings_pressed()

## 选"退出"——退出游戏
signal quit_pressed()

@onready var _start_button: Button = $VBox/StartButton
@onready var _codex_button: Button = $VBox/CodexButton
@onready var _settings_button: Button = $VBox/SettingsButton
@onready var _quit_button: Button = $VBox/QuitButton

func _ready() -> void:
	_start_button.pressed.connect(func(): start_pressed.emit())
	_codex_button.pressed.connect(func(): codex_pressed.emit())
	_settings_button.pressed.connect(func(): settings_pressed.emit())
	_quit_button.pressed.connect(func(): quit_pressed.emit())

## 启用/禁用全部按钮（状态切换时短暂锁定输入用）
func set_buttons_interactive(enabled: bool) -> void:
	_start_button.disabled = not enabled
	_codex_button.disabled = not enabled
	_settings_button.disabled = not enabled
	_quit_button.disabled = not enabled
