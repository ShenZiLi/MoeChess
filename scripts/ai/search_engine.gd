## AI 搜索引擎（minimax + alpha-beta + 走法排序 + 迭代加深 + 时间限制）
## 关联：docs/plans/2026-07-28-moechess-design.md §5.1/§5.3、docs/development/acceptance-standard.md B1-B8
##
## 难度梯度（严格按设计文档 §5.1）：
## - LOW：搜索深度 2，仅子力评估，同分走法随机选（模拟新手失误）
## - MEDIUM：搜索深度 4，子力 + 位置表评估，极小扰动（±10 分随机）
## - HIGH：搜索深度 6，子力 + 位置表 + 机动性 + 威胁评估，无扰动，严格最优
##
## 红线：
## - B4：choose_move 只从 GameController.generate_legal_moves 返回的合法走法中选
## - B5：高难度评估含威胁惩罚 + 深度 6 搜索，能预见送子后果
## - B7：单步 ≤ 2 秒，用迭代加深 + 1900ms 时间限制，超时返回当前最优
## - B8：注入 TranspositionTable 后，相同局面重复搜索命中缓存
class_name SearchEngine
extends RefCounted

const DF = CoreConstants.Difficulty

## 将死分（远大于任何子力分，KING=10000）
const MATE_SCORE: int = 100000
## 时间限制（毫秒），B7 要求 ≤ 2000ms，预留 100ms 余量
const TIME_LIMIT_MS: int = 1900
## MEDIUM 难度扰动幅度
const MEDIUM_PERTURBATION: int = 10
## 无穷大哨兵
const _INF: int = 1_000_000

## 各难度搜索深度
const DEPTH_LOW: int = 2
const DEPTH_MEDIUM: int = 4
const DEPTH_HIGH: int = 6

var _evaluator: Evaluator = Evaluator.new()
var _tt: TranspositionTable = null

## 搜索上下文
var _root_side: int = CoreConstants.Side.RED
var _target_depth: int = DEPTH_LOW
var _start_time: int = 0
var _time_up: bool = false
var _nodes_searched: int = 0

## 上次搜索统计（测试钩子）
var _last_search_nodes: int = 0
var _last_search_ms: int = 0
var _last_search_depth: int = 0
var _last_search_target_depth: int = 0

## 注入置换表（B8）
func set_transposition_table(tt: TranspositionTable) -> void:
	_tt = tt

## 上次搜索节点数
func get_last_search_nodes() -> int:
	return _last_search_nodes

## 上次搜索耗时（毫秒）
func get_last_search_ms() -> int:
	return _last_search_ms

## 上次实际完成的最大深度（B3-001 测试钩子，返回实际完成深度）
func get_last_search_depth() -> int:
	return _last_search_depth

## 上次目标深度（B3-001 测试钩子，返回目标深度）
func get_last_search_target_depth() -> int:
	return _last_search_target_depth

## 主入口：选择走法
## B4 红线：只从 GameController.generate_legal_moves 返回的合法走法中选
func choose_move(state: BoardState, difficulty: int) -> Move:
	_root_side = state.side_to_move
	_evaluator.set_difficulty(difficulty)
	_target_depth = _depth_for_difficulty(difficulty)
	_last_search_target_depth = _target_depth

	_start_time = Time.get_ticks_msec()
	_time_up = false
	_nodes_searched = 0

	# B4 红线：合法走法来源
	var legal_moves: Array = GameController.generate_legal_moves(state, _root_side)
	if legal_moves.is_empty():
		GameLogger.warn("[AI] No legal moves for side %d" % _root_side)
		_last_search_nodes = 0
		_last_search_ms = 0
		_last_search_depth = 0
		return null
	if legal_moves.size() == 1:
		_last_search_nodes = 1
		_last_search_ms = Time.get_ticks_msec() - _start_time
		_last_search_depth = 0
		return legal_moves[0]

	# 走法排序（吃子优先，MVV-LVA）
	var ordered_moves: Array = _order_moves(state, legal_moves)

	var best_move: Move = ordered_moves[0]
	var completed_depth: int = 0
	var last_complete_scores: Array = []
	var last_complete_moves: Array = ordered_moves.duplicate()

	# 迭代加深：从 depth=1 到目标 depth，每轮完成后检查时间
	for depth in range(1, _target_depth + 1):
		var iter_result: Array = _search_root(state, ordered_moves, depth)
		var iter_best_move: Move = iter_result[0]
		var iter_best_score: int = iter_result[1]
		var iter_scores: Array = iter_result[2]

		if _time_up:
			break  # 超时，保留上一轮完整结果

		best_move = iter_best_move
		last_complete_scores = iter_scores
		last_complete_moves = ordered_moves.duplicate()
		completed_depth = depth

		# 找到将死，提前结束
		if abs(iter_best_score) >= MATE_SCORE - 1000:
			break

	# 如果第一轮就超时（无完整结果），用深度 0 评估兜底
	if last_complete_scores.is_empty():
		last_complete_scores = []
		for m in ordered_moves:
			var new_state: BoardState = GameController.apply_move(state, m)
			last_complete_scores.append(_evaluator.evaluate(new_state, _root_side))
		last_complete_moves = ordered_moves.duplicate()
		best_move = _select_by_difficulty(difficulty, last_complete_moves, last_complete_scores, ordered_moves[0])
	else:
		best_move = _select_by_difficulty(difficulty, last_complete_moves, last_complete_scores, best_move)

	_last_search_nodes = _nodes_searched
	_last_search_ms = Time.get_ticks_msec() - _start_time
	_last_search_depth = completed_depth

	GameLogger.info("[AI] difficulty=%d depth=%d/%d nodes=%d ms=%d" % [difficulty, completed_depth, _target_depth, _last_search_nodes, _last_search_ms])
	return best_move

## 难度对应深度
func _depth_for_difficulty(difficulty: int) -> int:
	match difficulty:
		DF.LOW:
			return DEPTH_LOW
		DF.MEDIUM:
			return DEPTH_MEDIUM
		DF.HIGH:
			return DEPTH_HIGH
		_:
			return DEPTH_LOW

## 根节点搜索：返回 [best_move, best_score, all_scores]
## all_scores 与 ordered_moves 对齐，记录每个走法的评分（用于难度后处理）
## 根节点不做 beta 剪枝，确保所有走法都被评估（all_scores 完整）
func _search_root(state: BoardState, ordered_moves: Array, depth: int) -> Array:
	var alpha: int = -_INF
	var beta: int = _INF
	var best_move: Move = ordered_moves[0]
	var best_score: int = -_INF
	var all_scores: Array = []
	all_scores.resize(ordered_moves.size())
	for i in range(all_scores.size()):
		all_scores[i] = -_INF

	# 置换表提示：优先尝试上次最佳走法
	var tt_move: Move = null
	if _tt != null:
		var h: int = _tt.compute_hash(state)
		var lookup: Dictionary = _tt.lookup(h, depth)
		tt_move = lookup["best_move"]

	var moves_to_try: Array = ordered_moves.duplicate()
	if tt_move != null:
		var idx: int = _find_move_index(moves_to_try, tt_move)
		if idx > 0:
			moves_to_try.remove_at(idx)
			moves_to_try.insert(0, tt_move)

	for move in moves_to_try:
		if _time_up:
			break
		var new_state: BoardState = GameController.apply_move(state, move)
		var score: int = minimax(new_state, depth - 1, alpha, beta, false)
		var orig_idx: int = _find_move_index(ordered_moves, move)
		if orig_idx >= 0:
			all_scores[orig_idx] = score
		if score > best_score:
			best_score = score
			best_move = move
		if best_score > alpha:
			alpha = best_score
		# 根节点不 break，确保所有走法都被评估

	# 存置换表
	if _tt != null and not _time_up:
		var h: int = _tt.compute_hash(state)
		_tt.store(h, depth, best_score, TranspositionTable.Flag.EXACT, best_move)

	return [best_move, best_score, all_scores]

## minimax + alpha-beta 剪枝
## maximizing: 当前节点是否为 _root_side（最大化方）
## 评估函数返回 _root_side 视角的分，所以 maximizing 取 max，minimizing 取 min
func minimax(state: BoardState, depth: int, alpha: int, beta: int, maximizing: bool) -> int:
	_nodes_searched += 1

	# 时间限制检查（每 1024 个节点检查一次，避免频繁系统调用）
	if (_nodes_searched % 1024) == 0:
		if Time.get_ticks_msec() - _start_time > TIME_LIMIT_MS:
			_time_up = true
	if _time_up:
		return _evaluator.evaluate(state, _root_side)

	# 置换表查询
	var hash_val: int = 0
	var tt_move: Move = null
	if _tt != null:
		hash_val = _tt.compute_hash(state)
		var lookup: Dictionary = _tt.lookup(hash_val, depth)
		tt_move = lookup["best_move"]
		if lookup["found"]:
			var entry_score: int = int(lookup["score"])
			var entry_flag: int = int(lookup["flag"])
			# 根据 flag 调整 alpha/beta
			match entry_flag:
				TranspositionTable.Flag.EXACT:
					return entry_score
				TranspositionTable.Flag.LOWER_BOUND:
					if entry_score > alpha:
						alpha = entry_score
				TranspositionTable.Flag.UPPER_BOUND:
					if entry_score < beta:
						beta = entry_score
			if alpha >= beta:
				return entry_score

	# 叶子节点
	if depth <= 0:
		return _evaluator.evaluate(state, _root_side)

	# 生成合法走法
	var legal_moves: Array = GameController.generate_legal_moves(state, state.side_to_move)
	if legal_moves.is_empty():
		# 终局判定
		if RuleValidator.is_in_check(state, state.side_to_move):
			# 被将死：返回 _root_side 视角的分
			# mate_dist 越小（越接近根），惩罚越大，鼓励更快将死
			var mate_dist: int = _target_depth - depth
			if state.side_to_move == _root_side:
				return -MATE_SCORE + mate_dist  # _root_side 输
			else:
				return MATE_SCORE - mate_dist  # _root_side 赢
		else:
			return 0  # 困毙，和棋

	# 走法排序（MVV-LVA + tt_move 优先）
	var ordered: Array = _order_moves(state, legal_moves)
	if tt_move != null:
		var idx: int = _find_move_index(ordered, tt_move)
		if idx > 0:
			ordered.remove_at(idx)
			ordered.insert(0, tt_move)

	var orig_alpha: int = alpha
	var orig_beta: int = beta
	var local_best_move: Move = null

	if maximizing:
		var best: int = -_INF
		for move in ordered:
			if _time_up:
				break
			var new_state: BoardState = GameController.apply_move(state, move)
			var score: int = minimax(new_state, depth - 1, alpha, beta, false)
			if score > best:
				best = score
				local_best_move = move
			if best > alpha:
				alpha = best
			if alpha >= beta:
				break  # beta 剪枝
		if _tt != null and local_best_move != null and not _time_up:
			var flag: int = _flag_for_maximizing(best, orig_alpha, beta)
			_tt.store(hash_val, depth, best, flag, local_best_move)
		return best
	else:
		var best: int = _INF
		for move in ordered:
			if _time_up:
				break
			var new_state: BoardState = GameController.apply_move(state, move)
			var score: int = minimax(new_state, depth - 1, alpha, beta, true)
			if score < best:
				best = score
				local_best_move = move
			if best < beta:
				beta = best
			if alpha >= beta:
				break  # alpha 剪枝
		if _tt != null and local_best_move != null and not _time_up:
			var flag: int = _flag_for_minimizing(best, alpha, orig_beta)
			_tt.store(hash_val, depth, best, flag, local_best_move)
		return best

## maximizing 节点的 flag 判定
## best >= beta（被剪枝）→ LOWER_BOUND；best <= orig_alpha（未提升）→ UPPER_BOUND；否则 EXACT
func _flag_for_maximizing(best: int, orig_alpha: int, beta: int) -> int:
	if best >= beta:
		return TranspositionTable.Flag.LOWER_BOUND
	if best <= orig_alpha:
		return TranspositionTable.Flag.UPPER_BOUND
	return TranspositionTable.Flag.EXACT

## minimizing 节点的 flag 判定
## best <= alpha（被剪枝）→ UPPER_BOUND；best >= orig_beta（未提升）→ LOWER_BOUND；否则 EXACT
func _flag_for_minimizing(best: int, alpha: int, orig_beta: int) -> int:
	if best <= alpha:
		return TranspositionTable.Flag.UPPER_BOUND
	if best >= orig_beta:
		return TranspositionTable.Flag.LOWER_BOUND
	return TranspositionTable.Flag.EXACT

## alpha_beta 入口：根据 side_to_move 判断 maximizing，调用 minimax
func alpha_beta(state: BoardState, depth: int, alpha: int, beta: int) -> int:
	var maximizing: bool = (state.side_to_move == _root_side)
	return minimax(state, depth, alpha, beta, maximizing)

## 走法排序：MVV-LVA（吃子优先，被吃子价值 - 走子价值，降序）
## 无吃子的走法排后（score=0）
func _order_moves(state: BoardState, moves: Array) -> Array:
	var scored: Array = []
	for m in moves:
		var score: int = 0
		if m.captured != null:
			var cap_v: int = int(CoreConstants.PIECE_VALUE.get(m.captured.type, 0))
			var mov_v: int = 0
			if m.moved_piece != null:
				mov_v = int(CoreConstants.PIECE_VALUE.get(m.moved_piece.type, 0))
			score = cap_v - mov_v
		scored.append([score, m])
	# 降序排序（吃高价值子优先）
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var result: Array = []
	for entry in scored:
		result.append(entry[1])
	return result

## 在走法列表中查找指定走法的索引（用 equals 比较 from/to）
func _find_move_index(moves: Array, target: Move) -> int:
	if target == null:
		return -1
	for i in range(moves.size()):
		if moves[i] != null and moves[i].equals(target):
			return i
	return -1

## 难度后处理：根据评分选择最终走法
## - LOW：同分走法随机选（模拟新手失误）
## - MEDIUM：在 ±MEDIUM_PERTURBATION 分内的走法，80% 选最优，20% 随机选（极小扰动）
## - HIGH：严格最优
func _select_by_difficulty(difficulty: int, moves: Array, scores: Array, default_best: Move) -> Move:
	if moves.is_empty():
		return default_best

	# 找最高分
	var max_score: int = -_INF
	for s in scores:
		if s > max_score:
			max_score = s

	match difficulty:
		DF.HIGH:
			# 严格最优
			return default_best
		DF.LOW:
			# 同分走法随机选
			var candidates: Array = []
			for i in range(moves.size()):
				if scores[i] == max_score:
					candidates.append(moves[i])
			if candidates.is_empty():
				return default_best
			return candidates[randi() % candidates.size()]
		DF.MEDIUM:
			# 极小扰动：在 ±MEDIUM_PERTURBATION 内的走法，80% 最优，20% 随机
			var candidates: Array = []
			for i in range(moves.size()):
				if max_score - scores[i] <= MEDIUM_PERTURBATION:
					candidates.append(moves[i])
			if candidates.is_empty():
				return default_best
			# 80% 返回最优，20% 返回候选中的随机一个
			if randf() < 0.8 or candidates.size() == 1:
				return default_best
			return candidates[randi() % candidates.size()]
		_:
			return default_best
