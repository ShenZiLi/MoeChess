## 复盘控制面板（验收 G3/G4：前进/后退/自动播放 + 进度条）
## 关联：scripts/core/replay_controller.gd、
##       docs/development/acceptance-standard.md G3/G4、docs/plans/2026-07-28-moechess-design.md §7.3
##
## 提供 4 个按钮（后退/前进/自动播放/退出）+ 进度条（HSlider）。
## 由 ReplayController.step_played 信号驱动 UI 刷新（进度条 + 步数标签）。
## 按钮按下时只发对应信号；上层（Replay 状态机）调用 ReplayController 的对应方法，
## 由 ReplayController.step_played 回灌本面板刷新。
class_name ReplayPanel
extends Control

## 前进按钮按下
signal step_forward_pressed()

## 后退按钮按下
signal step_backward_pressed()

## 自动播放按钮按下（再次按下应切回停止——由上层根据 is_auto_playing 决定）
signal auto_play_pressed()

## 退出复盘
signal exit_pressed()

## 当前复盘控制器
var _replay: ReplayController = null

@onready var _progress_slider: HSlider = $VBox/ProgressSlider
@onready var _step_label: Label = $VBox/StepLabel
@onready var _backward_button: Button = $VBox/ButtonRow/BackwardButton
@onready var _forward_button: Button = $VBox/ButtonRow/ForwardButton
@onready var _auto_play_button: Button = $VBox/ButtonRow/AutoPlayButton
@onready var _exit_button: Button = $VBox/ButtonRow/ExitButton

func _ready() -> void:
	_backward_button.pressed.connect(func(): step_backward_pressed.emit())
	_forward_button.pressed.connect(func(): step_forward_pressed.emit())
	_auto_play_button.pressed.connect(_on_auto_play_button)
	_exit_button.pressed.connect(func(): exit_pressed.emit())
	_progress_slider.min_value = 0
	_progress_slider.max_value = 0
	_progress_slider.value = 0
	_progress_slider.editable = false  # 仅显示；如需 seek 可由上层开启

## 绑定 ReplayController；订阅 step_played/auto_play_finished 刷新 UI
func set_replay(replay: ReplayController) -> void:
	if _replay != null:
		_replay.step_played.disconnect(_on_step_played)
		_replay.auto_play_finished.disconnect(_on_auto_play_finished)
	_replay = replay
	if _replay == null:
		return
	_replay.step_played.connect(_on_step_played)
	_replay.auto_play_finished.connect(_on_auto_play_finished)
	_refresh_ui()

## 强制刷新当前进度（如加载新棋谱后立即调用）
func refresh() -> void:
	_refresh_ui()

func _on_step_played(_move: Move, _state: BoardState) -> void:
	_refresh_ui()

func _on_auto_play_finished() -> void:
	_auto_play_button.text = "▶▶ 自动播放"
	_refresh_ui()

func _on_auto_play_button() -> void:
	auto_play_pressed.emit()
	# 按钮文案随状态切换
	if _replay != null and _replay.is_auto_playing():
		_auto_play_button.text = "⏸ 停止"
	else:
		_auto_play_button.text = "▶▶ 自动播放"

## 刷新进度条 + 步数标签 + 按钮可用性
func _refresh_ui() -> void:
	if _replay == null:
		_progress_slider.max_value = 0
		_progress_slider.value = 0
		_step_label.text = "— / —"
		_backward_button.disabled = true
		_forward_button.disabled = true
		_auto_play_button.disabled = true
		return
	var total: int = _replay.get_total_steps()
	var cur: int = _replay.get_current_step()
	_progress_slider.max_value = total
	_progress_slider.value = cur
	_step_label.text = "%d / %d" % [cur, total]
	_backward_button.disabled = cur <= 0
	_forward_button.disabled = cur >= total
	_auto_play_button.disabled = total <= 0
	if _replay.is_auto_playing():
		_auto_play_button.text = "⏸ 停止"
	else:
		_auto_play_button.text = "▶▶ 自动播放"
