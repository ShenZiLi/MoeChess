## 暂停面板（验收 F2：Paused 状态可暂停/继续/重开/返回菜单）
## 关联：docs/development/acceptance-standard.md F2、docs/plans/2026-07-28-moechess-design.md §7.1
##
## 模态遮罩 + 三个按钮：继续 / 重开 / 返回菜单。
## 由 Playing 状态机在 ESC（或移动端切后台）时弹出；按按钮发对应信号。
## 本面板不直接控制游戏逻辑，只发信号给 GameStateMachine。
class_name PausePanel
extends Control

## 继续——回 Playing，保留对局状态
signal resume_pressed()

## 重开——新对局，回 SelectMode 或重新初始化 Playing
signal restart_pressed()

## 返回菜单——回 MainMenu
signal menu_pressed()

@onready var _resume_button: Button = $Center/Panel/VBox/ResumeButton
@onready var _restart_button: Button = $Center/Panel/VBox/RestartButton
@onready var _menu_button: Button = $Center/Panel/VBox/MenuButton

func _ready() -> void:
	_resume_button.pressed.connect(func(): resume_pressed.emit())
	_restart_button.pressed.connect(func(): restart_pressed.emit())
	_menu_button.pressed.connect(func(): menu_pressed.emit())
	# 默认不拦截底层输入；show() 时再设 process_mode
	hide()

## 弹出面板（process_mode 设为 WHEN_PAUSED 以便暂停时仍可交互）
func show_panel() -> void:
	show()
	_resume_button.grab_focus()

## 隐藏面板
func hide_panel() -> void:
	hide()
