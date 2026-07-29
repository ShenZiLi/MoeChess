## Playing 子状态机（RefCounted，由 GameStateMachine 持有）
## 关联：docs/plans/2026-07-28-moechess-design.md §7.2、docs/development/acceptance-standard.md F3/F4/F5
##
## 子状态流转（F3）：
##   WaitingInput → PieceSelected → AnimatingMove → CheckTurnEnd → TurnSwitching → WaitingInput
##
## 职责：
## - 处理棋子/格子点击，驱动走棋流程
## - 选中棋子时通过 request_show_hints 信号请求显示可走位置提示（F4）
## - 将死时通过 game_over 信号通知上层进入 Gameover 并播放胜负动画（F5）
## - 双人对战换边时通过 request_flip_view 信号触发视角翻转 + 列阵音效（D4/E8）
## - 人机模式：玩家走完后启动 AIWorker，AI 走完后播动画
##
## 子状态说明：
## - WaitingInput：等待当前行动方选棋子；人机模式 AI 回合时在此状态启动 AI 计算
## - PieceSelected：已选中棋子，显示可走位置提示，等待目标格
## - AnimatingMove：播放移动动画（受加速倍率影响）
## - CheckTurnEnd：判定将死/困毙/长将和棋，满足则发 game_over
## - TurnSwitching：双人对战执行视角翻转 + 列阵音效；人机模式无翻转
class_name PlayingState
extends RefCounted

# Playing 子状态枚举（F3）
enum SubState {
	WAITING_INPUT,
	PIECE_SELECTED,
	ANIMATING_MOVE,
	CHECK_TURN_END,
	TURN_SWITCHING,
}

# GameMode 枚举值（与 GameStateMachine.GameMode 对应，避免循环 class_name 引用）
# 保持与 game_state_machine.gd 中 GameMode 枚举顺序一致
const _MODE_PVE_LOW: int = 0
const _MODE_PVE_MEDIUM: int = 1
const _MODE_PVE_HIGH: int = 2
const _MODE_PVP: int = 3

## 请求显示可走位置提示（F4）；moves: Array[Move]
signal request_show_hints(moves: Array)

## 请求清除可走位置提示（取消选中 / 走子后）
signal request_clear_hints()

## 请求视角翻转（双人对战换边，D4/E8：列阵音效 + 棋盘背景切换 + 棋子重算布局）
signal request_flip_view()

## 请求播放走子动画（view 层订阅，动画完成后调用 on_move_anim_done）
## move 包含 from/to/captured/moved_piece，view 层据此播放移动 + 吃子动画 + 音效
signal move_started(move: Move)

## 请求播放选中音效（view 层订阅后播 select_sfx）
signal piece_selected(piece: Piece)

## 游戏结束（F5）；result: {over: bool, result: "red_win"/"black_win"/"draw"/null}
signal game_over(result: Dictionary)

## AI 开始思考（UI 显示"思考中"，B6）
signal ai_thinking_started()

## AI 思考结束（UI 隐藏"思考中"）
signal ai_thinking_finished()

## 当前 BoardState（每次走子后替换为新对象，不可变更新）
var _state: BoardState = null

## 当前子状态
var _sub_state: int = SubState.WAITING_INPUT

## 当前对局模式（GameStateMachine.GameMode）
var _game_mode: int = 0

## 当前难度（CoreConstants.Difficulty，人机模式有效）
var _difficulty: int = CoreConstants.Difficulty.LOW

## 玩家阵营（人机模式固定 RED，设计 D3：玩家固定在下方）
var _player_side: int = CoreConstants.Side.RED

## 当前选中的棋子
var _selected_piece: Piece = null

## 当前选中棋子的合法走法列表（Array[Move]）
var _legal_moves_for_selected: Array = []

## AI Worker 引用（由 GameStateMachine 注入）
var _ai_worker: AIWorker = null

## AI 是否正在计算（在 WAITING_INPUT 子状态内标记 AI 回合）
var _ai_computing: bool = false

## 是否暂停
var _paused: bool = false

## 游戏是否已结束（防止结束后继续响应输入）
var _game_over: bool = false

## 进入 Playing 状态
## state: 初始 BoardState（通常为 BoardState.initial()）
func enter(state: BoardState) -> void:
	_state = state
	_sub_state = SubState.WAITING_INPUT
	_selected_piece = null
	_legal_moves_for_selected = []
	_paused = false
	_game_over = false
	_ai_computing = false
	GameLogger.info("[PlayingState] enter, side_to_move=%d mode=%d" % [_state.side_to_move, _game_mode])
	# 若进入时已是 AI 回合（续局场景），启动 AI
	if _is_ai_turn() and not _game_over:
		_start_ai()

## 退出 Playing 状态（清理资源，断开信号）
func exit() -> void:
	if _ai_worker != null:
		if _ai_worker.is_computing():
			_ai_worker.cancel()
		_disconnect_ai()
	_state = null
	_selected_piece = null
	_legal_moves_for_selected = []
	_ai_computing = false

## 设置 AI Worker（由 GameStateMachine 注入）
func set_ai_worker(worker: AIWorker) -> void:
	_ai_worker = worker

## 设置对局模式（GameStateMachine.GameMode）
func set_game_mode(mode: int) -> void:
	_game_mode = mode

## 设置难度（CoreConstants.Difficulty）
func set_difficulty(difficulty: int) -> void:
	_difficulty = difficulty

## 设置玩家阵营（人机模式默认 RED）
func set_player_side(side: int) -> void:
	_player_side = side

## 获取当前子状态
func get_sub_state() -> int:
	return _sub_state

## 获取当前子状态名（调试/日志用）
func get_sub_state_name() -> String:
	match _sub_state:
		SubState.WAITING_INPUT:
			return "WaitingInput"
		SubState.PIECE_SELECTED:
			return "PieceSelected"
		SubState.ANIMATING_MOVE:
			return "AnimatingMove"
		SubState.CHECK_TURN_END:
			return "CheckTurnEnd"
		SubState.TURN_SWITCHING:
			return "TurnSwitching"
		_:
			return "Unknown"

## 获取当前 BoardState（view 层读取渲染）
func get_state() -> BoardState:
	return _state

## 是否暂停
func is_paused() -> bool:
	return _paused

## 是否游戏已结束
func is_game_over() -> bool:
	return _game_over

## 暂停回调（GameStateMachine.pause_game 时调用）
func on_paused() -> void:
	_paused = true
	# 软取消 AI 计算；恢复后由 on_resumed 重启
	if _ai_worker != null and _ai_worker.is_computing():
		_ai_worker.cancel()

## 恢复回调（GameStateMachine.resume_game 时调用）
func on_resumed() -> void:
	_paused = false
	# 若被取消的 AI 还需要走，重启计算
	if _ai_computing and _ai_worker != null and not _ai_worker.is_computing() and not _game_over:
		_start_ai()

## 处理棋子点击
## piece: 被点击的棋子（由 view 层根据 InputProvider.piece_clicked 查 BoardState 得到）
func on_piece_clicked(piece: Piece) -> void:
	if _paused or _state == null or _game_over:
		return
	# 动画/换边/检查期间忽略输入
	if _sub_state == SubState.ANIMATING_MOVE or _sub_state == SubState.TURN_SWITCHING or _sub_state == SubState.CHECK_TURN_END:
		return
	# AI 回合忽略玩家点击
	if _ai_computing:
		return
	if piece == null:
		return
	if _sub_state == SubState.WAITING_INPUT:
		# 必须是当前走棋方的棋子；人机模式还必须是玩家方
		if piece.side != _state.side_to_move:
			return
		if _is_ai_turn():
			return
		_select_piece(piece)
	elif _sub_state == SubState.PIECE_SELECTED:
		if piece.side == _state.side_to_move:
			# 点击己方棋子：切换选中或取消选中
			if piece.equals(_selected_piece):
				_deselect()
			else:
				_select_piece(piece)
		else:
			# 点击对方棋子：若在合法走法中（吃子），执行走子
			_try_move_to(piece.col, piece.row)

## 处理格子点击
## pos: 棋盘逻辑坐标 Vector2i(col, row)
func on_cell_clicked(pos: Vector2i) -> void:
	if _paused or _state == null or _game_over:
		return
	if _sub_state != SubState.PIECE_SELECTED:
		return
	if _ai_computing:
		return
	_try_move_to(pos.x, pos.y)

## 走子动画完成回调（view 层动画播完后调用）
func on_move_anim_done() -> void:
	if _state == null or _game_over:
		return
	if _sub_state != SubState.ANIMATING_MOVE:
		return
	_sub_state = SubState.CHECK_TURN_END
	_check_turn_end()

## 双人对战视角翻转完成回调（view 层翻转动画播完后调用）
## 人机模式不调用此方法
func on_flip_done() -> void:
	if _sub_state != SubState.TURN_SWITCHING:
		return
	_finish_turn_switching()

# -------------------- 内部实现 --------------------

## 是否轮到 AI（人机模式且当前走棋方非玩家方）
func _is_ai_turn() -> bool:
	if _game_mode == _MODE_PVP:
		return false
	# PVE 模式：AI 控制非玩家方
	return _state.side_to_move != _player_side

## 选中棋子，进入 PieceSelected 子状态，发请求显示可走位置提示（F4）
func _select_piece(piece: Piece) -> void:
	_selected_piece = piece
	_legal_moves_for_selected = _generate_legal_moves_for(piece)
	_sub_state = SubState.PIECE_SELECTED
	request_show_hints.emit(_legal_moves_for_selected)
	piece_selected.emit(piece)
	GameLogger.debug("[PlayingState] selected %s, %d legal moves" % [piece, _legal_moves_for_selected.size()])

## 取消选中，回到 WaitingInput
func _deselect() -> void:
	_selected_piece = null
	_legal_moves_for_selected = []
	_sub_state = SubState.WAITING_INPUT
	request_clear_hints.emit()

## 生成指定棋子的合法走法（从 GameController.generate_legal_moves 中筛选 from == piece.pos）
func _generate_legal_moves_for(piece: Piece) -> Array:
	if piece == null or _state == null:
		return []
	var all: Array = GameController.generate_legal_moves(_state, piece.side)
	var out: Array = []
	for m in all:
		if m.from_col == piece.col and m.from_row == piece.row:
			out.append(m)
	return out

## 尝试走到 (col, row)：若是合法走法则执行，否则取消选中
func _try_move_to(col: int, row: int) -> void:
	if _selected_piece == null:
		return
	var move: Move = null
	for m in _legal_moves_for_selected:
		if m.to_col == col and m.to_row == row:
			move = m
			break
	if move == null:
		# 非法目标——取消选中
		_deselect()
		return
	_apply_move_and_animate(move)

## 应用走子并启动动画
## 1. GameController.apply_move 返回新 BoardState（不可变更新）
## 2. 清除选中状态和提示
## 3. 进入 AnimatingMove 子状态
## 4. 发 move_started 信号请求 view 层播放动画
func _apply_move_and_animate(move: Move) -> void:
	_state = GameController.apply_move(_state, move)
	_selected_piece = null
	_legal_moves_for_selected = []
	request_clear_hints.emit()
	_sub_state = SubState.ANIMATING_MOVE
	move_started.emit(move)
	# 触发自动存档（G5）— 通过 GameStateMachine autoload 通知
	var gsm: Node = Engine.get_main_loop().root.get_node_or_null("GameStateMachine")
	if gsm != null and gsm.has_method("notify_move_applied"):
		gsm.notify_move_applied(_state)
	GameLogger.debug("[PlayingState] move applied: %s" % move)

## 检查回合结束（将死/困毙/长将和棋）
## 满足终局则发 game_over 信号（F5）；否则进入换边流程
func _check_turn_end() -> void:
	var result: Dictionary = GameController.check_game_over(_state)
	if result.get("over", false):
		_game_over = true
		GameLogger.info("[PlayingState] game over: %s" % result)
		game_over.emit(result)
		return
	_start_turn_switching()

## 开始换边流程（F3：TurnSwitching）
## 双人对战：发 request_flip_view 信号触发视角翻转 + 列阵音效（D4/E8）
## 人机模式：无翻转，直接收尾
func _start_turn_switching() -> void:
	_sub_state = SubState.TURN_SWITCHING
	if _game_mode == _MODE_PVP:
		# 双人对战：触发视角翻转 + 列阵音效
		# view 层收到信号后播 formation_sfx + 翻转动画，完成后调用 on_flip_done
		request_flip_view.emit()
		GameLogger.debug("[PlayingState] PVP flip requested")
	else:
		# 人机模式：无翻转，直接收尾
		_finish_turn_switching()

## 换边收尾：若轮到 AI 则启动 AI 计算，否则回到 WaitingInput
func _finish_turn_switching() -> void:
	if _game_over:
		return
	if _is_ai_turn():
		_start_ai()
	else:
		_sub_state = SubState.WAITING_INPUT

## 启动 AI 计算（B6：WorkerThread + 思考中提示）
func _start_ai() -> void:
	if _ai_worker == null:
		push_warning("[PlayingState] no AIWorker, skip AI move")
		_sub_state = SubState.WAITING_INPUT
		return
	_sub_state = SubState.WAITING_INPUT
	_ai_computing = true
	ai_thinking_started.emit()
	_connect_ai()
	_ai_worker.start_compute(_state, _difficulty)
	GameLogger.info("[PlayingState] AI start_compute, difficulty=%d" % _difficulty)

## 连接 AI Worker 的 compute_finished 信号
func _connect_ai() -> void:
	if _ai_worker == null:
		return
	if not _ai_worker.compute_finished.is_connected(_on_ai_compute_finished):
		_ai_worker.compute_finished.connect(_on_ai_compute_finished)

## 断开 AI Worker 的 compute_finished 信号
func _disconnect_ai() -> void:
	if _ai_worker == null:
		return
	if _ai_worker.compute_finished.is_connected(_on_ai_compute_finished):
		_ai_worker.compute_finished.disconnect(_on_ai_compute_finished)

## AI 计算完成回调（由 AIWorker 在主线程 emit）
func _on_ai_compute_finished(move: Move) -> void:
	ai_thinking_finished.emit()
	_ai_computing = false
	if move == null:
		# 无合法走法——理论上 check_game_over 已处理，兜底判定
		GameLogger.warn("[PlayingState] AI returned null move")
		var result: Dictionary = GameController.check_game_over(_state)
		if result.get("over", false):
			_game_over = true
			game_over.emit(result)
		else:
			_sub_state = SubState.WAITING_INPUT
		return
	# 应用 AI 走子并播放动画
	_apply_move_and_animate(move)
