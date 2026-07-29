## 规则校验器
## 关联：scripts/core/constants.gd、scripts/core/board_state.gd、scripts/core/move.gd、scripts/core/move_generator.gd、scripts/core/game_controller.gd
## 覆盖验收：A5（过滤送将）、A6（将军判定）、A7（将死判定）、A8（困毙）、A9（长将判和）、A10（将帅照面）
##
## 本类所有方法均为纯逻辑，不修改入参 state。
class_name RuleValidator
extends RefCounted

## 走法是否合法：1) 伪走法生成器包含该走法 2) 走完后己方不被将军 3) 走完后双方将帅不照面
## 为了避免与 GameController 循环依赖，这里直接用 BoardState.deep_copy + 手动 apply
static func is_legal(state: BoardState, move: Move) -> bool:
	if move == null:
		return false
	var piece: Piece = move.moved_piece
	if piece == null:
		# moved_piece 可空时从 from 取
		piece = state.get_piece(move.from_col, move.from_row)
		if piece == null:
			return false
	# 验证该走法在伪走法列表中（防止伪造走法）
	var pseudo: Array = MoveGenerator.generate_pseudo_moves(state, piece)
	var found: bool = false
	for m in pseudo:
		if m.to_col == move.to_col and m.to_row == move.to_row:
			found = true
			break
	if not found:
		return false
	# 模拟走完后的状态
	var new_state: BoardState = _apply_move_raw(state, move)
	# A5：走完后己方将被将军 → 非法（不得送将）
	if is_in_check(new_state, piece.side):
		return false
	# A10：双方将帅不得照面
	if kings_face(new_state):
		return false
	return true

## 是否被将军：side 的将被对方任何棋子攻击
static func is_in_check(state: BoardState, side: int) -> bool:
	var king: Piece = state.find_king(side)
	if king == null:
		return true  # 将不存在视为被将军（异常局面）
	var opp: int = CoreConstants.opponent(side)
	# 遍历对方所有棋子的伪走法，看是否有走法的 to 等于将的位置
	for p in state.pieces_of(opp):
		var moves: Array = MoveGenerator.generate_pseudo_moves(state, p)
		for m in moves:
			if m.to_col == king.col and m.to_row == king.row:
				return true
	# 额外检查：将帅照面也算"被将军"（将帅互相攻击）
	if kings_face(state):
		return true
	return false

## 将死：被将军且无任何合法走法解将
static func is_checkmate(state: BoardState, side: int) -> bool:
	if not is_in_check(state, side):
		return false
	return not _has_any_legal_move(state, side)

## 困毙：无合法走法且未被将军（和棋）
static func is_stalemate(state: BoardState, side: int) -> bool:
	if is_in_check(state, side):
		return false
	return not _has_any_legal_move(state, side)

## 双方将帅是否照面：同列且中间无棋子
static func kings_face(state: BoardState) -> bool:
	var red_king: Piece = state.find_king(CoreConstants.Side.RED)
	var black_king: Piece = state.find_king(CoreConstants.Side.BLACK)
	if red_king == null or black_king == null:
		return false
	if red_king.col != black_king.col:
		return false
	var col: int = red_king.col
	var r1: int = min(red_king.row, black_king.row)
	var r2: int = max(red_king.row, black_king.row)
	for r in range(r1 + 1, r2):
		if state.get_piece(col, r) != null:
			return false
	return true

## 长将判和：检查 state.move_history 中连续 ≥ PERPETUAL_CHECK_LIMIT 步同方走完后将军对方
## 实现：从 move_history 末尾向前扫描，若最近 N 步（N=PERPETUAL_CHECK_LIMIT）的 check_history 全为 true，
## 且这些步骤是同一方连续将军（即每两步间隔一个对方非将军步），则判和。
## 简化判定：最近 PERPETUAL_CHECK_LIMIT 步的 check_history 全为 true。
static func generates_perpetual_check(state: BoardState, move: Move) -> bool:
	# 本函数判定"如果走出 move，是否会构成长将"。
	# 先模拟走出 move 后的状态
	var new_state: BoardState = _apply_move_raw(state, move)
	# move 走完后，对方是否被将军？若未被将军，则不是长将
	if not is_in_check(new_state, CoreConstants.opponent(move.moved_piece.side if move.moved_piece else state.side_to_move)):
		return false
	# 检查走完 move 后的 check_history：最近 PERPETUAL_CHECK_LIMIT 步是否全为 true
	# new_state.check_history 已包含 move 这一步的 is_check
	var hist: Array = new_state.check_history
	if hist.size() < CoreConstants.PERPETUAL_CHECK_LIMIT:
		return false
	var n: int = CoreConstants.PERPETUAL_CHECK_LIMIT
	for i in range(hist.size() - n, hist.size()):
		if not bool(hist[i]):
			return false
	return true

## 长将判和的便利方法：基于当前 state 的 check_history 判断当前局面是否因长将判和
static func is_perpetual_check_draw(state: BoardState) -> bool:
	var hist: Array = state.check_history
	if hist.size() < CoreConstants.PERPETUAL_CHECK_LIMIT:
		return false
	var n: int = CoreConstants.PERPETUAL_CHECK_LIMIT
	for i in range(hist.size() - n, hist.size()):
		if not bool(hist[i]):
			return false
	return true

# -------------------- 内部工具 --------------------

## 是否存在任意合法走法
static func _has_any_legal_move(state: BoardState, side: int) -> bool:
	for p in state.pieces_of(side):
		var pseudo: Array = MoveGenerator.generate_pseudo_moves(state, p)
		for m in pseudo:
			if is_legal(state, m):
				return true
	return false

## 原始 apply（不写 move_history，仅供本类内部模拟用，避免与 GameController 循环依赖）
## 返回新 BoardState，棋子已移动，side_to_move 已反转
static func _apply_move_raw(state: BoardState, move: Move) -> BoardState:
	var s: BoardState = state.deep_copy()
	var piece: Piece = s.get_piece(move.from_col, move.from_row)
	if piece == null:
		return s
	# 处理吃子
	var target: Piece = s.get_piece(move.to_col, move.to_row)
	if target != null:
		if piece.side == CoreConstants.Side.RED:
			s.captured_by_red.append(target)
		else:
			s.captured_by_black.append(target)
	# 移动棋子
	s.grid[move.from_row][move.from_col] = null
	s.grid[move.to_row][move.to_col] = piece
	piece.col = move.to_col
	piece.row = move.to_row
	# 反转走棋方
	s.side_to_move = CoreConstants.opponent(piece.side)
	return s
