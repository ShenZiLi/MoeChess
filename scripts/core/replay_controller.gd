## 复盘模式控制器（RefCounted，零节点依赖）
## 关联：scripts/core/save_manager.gd、scripts/core/board_state.gd、scripts/core/move.gd、scripts/core/game_controller.gd、
##       docs/development/acceptance-standard.md G3/G4、docs/plans/2026-07-28-moechess-design.md §7.3
##
## 职责：
## - 加载 SaveManager.save_record 写出的棋谱 JSON
## - 提供 step_forward / step_backward / auto_play / stop_auto_play API（G3）
## - 维护当前复盘局面（get_current_state），每步推进触发 step_played 信号（G4：视觉层订阅后重放动画+音效）
## - 自动播放通过 SceneTreeTimer 周期性推进，到达末步发 auto_play_finished
##
## 设计原则：本类只负责状态推进与信号分发；动画/音效的重放由视觉层订阅 step_played 实现。
## 后退时从 initial_state 重新 apply_move 到目标步，O(N) 但象棋一局 ≤ 200 步可接受。
class_name ReplayController
extends RefCounted

## 一步走完信号（前进或后退均触发；move 可能为 null 表示回到第 0 步初始局面）
signal step_played(move: Move, state: BoardState)

## 自动播放到达末步信号
signal auto_play_finished()

## 棋谱全部走法（Move 数组）
var _moves: Array = []

## 棋谱初始局面（默认 BoardState.initial()，可被 load() 覆盖）
var _initial_state: BoardState = null

## 棋谱元信息
var _meta: Dictionary = {}

## 当前步索引（0 = 初始局面，N = 走完第 N 步）
var _current_step: int = 0

## 当前复盘局面
var _current_state: BoardState = null

## 是否处于自动播放
var _auto_playing: bool = false

## 自动播放速度倍率（1.0 = 1 步/秒）
var _auto_play_speed: float = 1.0

## 当前棋谱文件路径（load 成功后填充）
var _path: String = ""

## 加载棋谱；成功返回 true
## path: SaveManager.save_record 返回的路径，或 list_records() 中的 path
func load(path: String) -> bool:
	var data: Dictionary = SaveManager.load_record(path)
	if data.is_empty():
		GameLogger.warn("[ReplayController] load failed: %s" % path)
		return false
	_path = path
	_meta = data.get("meta", {})
	var initial_dict: Dictionary = data.get("initial_state", {})
	if initial_dict.is_empty():
		_initial_state = BoardState.initial()
	else:
		_initial_state = BoardState.from_dict(initial_dict)
	_moves.clear()
	for md in data.get("moves", []):
		if typeof(md) == TYPE_DICTIONARY:
			_moves.append(Move.from_dict(md))
	_current_step = 0
	_current_state = _initial_state.deep_copy()
	_auto_playing = false
	GameLogger.info("[ReplayController] loaded %s (%d moves)" % [path, _moves.size()])
	return true

## 前进一步；返回该步 Move，已到末步返回 null
func step_forward() -> Move:
	if _current_step >= _moves.size():
		return null
	var mv: Move = _moves[_current_step]
	_current_state = GameController.apply_move(_current_state, mv)
	_current_step += 1
	step_played.emit(mv, _current_state)
	return mv

## 后退一步；返回该步 Move（被回退的那一步），已在初始局面返回 null
func step_backward() -> Move:
	if _current_step <= 0:
		return null
	_current_step -= 1
	# 从初始局面重新 apply_move 到 _current_step
	_current_state = _initial_state.deep_copy()
	for i in range(_current_step):
		_current_state = GameController.apply_move(_current_state, _moves[i])
	var mv: Move = null
	if _current_step < _moves.size():
		mv = _moves[_current_step]
	step_played.emit(mv, _current_state)
	return mv

## 跳到指定步（0..total）；越界自动 clamp
func seek_to(step_idx: int) -> void:
	var target: int = clamp(step_idx, 0, _moves.size())
	if target == _current_step:
		return
	_current_step = target
	_current_state = _initial_state.deep_copy()
	for i in range(_current_step):
		_current_state = GameController.apply_move(_current_state, _moves[i])
	var mv: Move = null
	if _current_step > 0 and _current_step <= _moves.size():
		mv = _moves[_current_step - 1]
	step_played.emit(mv, _current_state)

## 启动自动播放；speed = 每秒走多少步（如 1.0 = 1 步/秒，2.0 = 2 步/秒）
## 已到末步会立刻发 auto_play_finished
func auto_play(speed: float) -> void:
	stop_auto_play()
	if _moves.is_empty() or _current_step >= _moves.size():
		auto_play_finished.emit()
		return
	_auto_play_speed = max(speed, 0.001)
	_auto_playing = true
	_schedule_next_auto_step()

## 停止自动播放
func stop_auto_play() -> void:
	_auto_playing = false

## 是否处于自动播放
func is_auto_playing() -> bool:
	return _auto_playing

## 当前步索引（0..total）
func get_current_step() -> int:
	return _current_step

## 总步数
func get_total_steps() -> int:
	return _moves.size()

## 当前复盘局面（不要修改，仅供读取/渲染）
func get_current_state() -> BoardState:
	return _current_state

## 棋谱元信息
## 注意：函数名不能是 get_meta——会覆盖 Object.get_meta(StringName, Variant) -> Variant
func get_record_meta() -> Dictionary:
	return _meta

## 棋谱文件路径
## 注意：函数名不能是 get_path——会覆盖 Object.get_path() -> String
func get_record_path() -> String:
	return _path

## 调度下一步自动播放
func _schedule_next_auto_step() -> void:
	if not _auto_playing:
		return
	if _current_step >= _moves.size():
		_auto_playing = false
		auto_play_finished.emit()
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		_auto_playing = false
		auto_play_finished.emit()
		return
	var interval: float = 1.0 / _auto_play_speed
	var timer: SceneTreeTimer = tree.create_timer(interval)
	timer.timeout.connect(_on_auto_play_tick)

## 自动播放 tick 回调
func _on_auto_play_tick() -> void:
	if not _auto_playing:
		return
	if _current_step >= _moves.size():
		_auto_playing = false
		auto_play_finished.emit()
		return
	step_forward()
	if _current_step >= _moves.size():
		_auto_playing = false
		auto_play_finished.emit()
		return
	_schedule_next_auto_step()
