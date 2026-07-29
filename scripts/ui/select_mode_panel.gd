## 模式选择面板（验收 F1：SelectTheme→SelectMode→Playing）
## 关联：scripts/core/constants.gd、scripts/states/game_state_machine.gd、docs/plans/2026-07-28-moechess-design.md §7.1
##
## 提供 4 个选项：人机-低 / 人机-中 / 人机-高 / 双人对战。
## 选定后发 mode_confirmed(mode, difficulty)，由 GameStateMachine 进入 Playing。
## - mode: 与 GameStateMachine.GameMode 对齐（PVE_LOW=0 / PVE_MEDIUM=1 / PVE_HIGH=2 / PVP=3），
##   调用方可直接传给 GameStateMachine.start_new_game(mode, difficulty)
## - difficulty: CoreConstants.Difficulty 整数（PVP 时为 LOW，由 GameStateMachine 二次覆盖）
class_name SelectModePanel
extends Control

## 玩家确认模式——切到 Playing
## mode: 与 GameStateMachine.GameMode 对齐（PVE_LOW=0 / PVE_MEDIUM=1 / PVE_HIGH=2 / PVP=3）
## difficulty: CoreConstants.Difficulty（PVP 时为 LOW，GameStateMachine 会再次覆盖）
signal mode_confirmed(mode: int, difficulty: int)

## 选"返回"——回 SelectTheme
signal back_pressed()

## 模式常量：与 GameStateMachine.GameMode 保持同值同序，调用方可直接传入 start_new_game
const MODE_PVE_LOW: int = 0

const MODE_PVE_MEDIUM: int = 1

const MODE_PVE_HIGH: int = 2

const MODE_PVP: int = 3

## 兼容别名（旧约定：mode 仅区分 PVE/PVP）
const MODE_PVE: int = 0

@onready var _pve_low_button: Button = $VBox/PveLowButton
@onready var _pve_medium_button: Button = $VBox/PveMediumButton
@onready var _pve_high_button: Button = $VBox/PveHighButton
@onready var _pvp_button: Button = $VBox/PvpButton
@onready var _back_button: Button = $VBox/BackButton

func _ready() -> void:
	_pve_low_button.pressed.connect(func(): mode_confirmed.emit(MODE_PVE_LOW, CoreConstants.Difficulty.LOW))
	_pve_medium_button.pressed.connect(func(): mode_confirmed.emit(MODE_PVE_MEDIUM, CoreConstants.Difficulty.MEDIUM))
	_pve_high_button.pressed.connect(func(): mode_confirmed.emit(MODE_PVE_HIGH, CoreConstants.Difficulty.HIGH))
	_pvp_button.pressed.connect(func(): mode_confirmed.emit(MODE_PVP, CoreConstants.Difficulty.LOW))
	_back_button.pressed.connect(func(): back_pressed.emit())

## 启用/禁用全部按钮
func set_buttons_interactive(enabled: bool) -> void:
	_pve_low_button.disabled = not enabled
	_pve_medium_button.disabled = not enabled
	_pve_high_button.disabled = not enabled
	_pvp_button.disabled = not enabled
	_back_button.disabled = not enabled
