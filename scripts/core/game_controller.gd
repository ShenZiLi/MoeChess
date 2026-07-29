## 游戏控制器
## 关联：scripts/core/constants.gd、scripts/core/board_state.gd、scripts/core/move.gd、scripts/core/move_generator.gd、scripts/core/rule_validator.gd
## 覆盖验收：A5（apply_move 配合 RuleValidator 过滤送将）、G1（move_history 自动记录）
##
## apply_move 返回新 BoardState（不可变更新），便于 AI 搜索分支 / 悔棋 / 复盘。
class_name GameController
extends RefCounted

## 应用走法，返回新状态（不可变更新）
## 新状态会：写入 move_history、last_move、turn_number+1、side_to_move 反转、captured 列表、check_history 追加 is_check
static func apply_move(state: BoardState, move: Move) -> BoardState:
	var s: BoardState = state.deep_copy()
	var piece: Piece = s.get_piece(move.from_col, move.from_row)
	if piece == null:
		push_warning("GameController.apply_move: no piece at (%d,%d)" % [move.from_col, move.from_row])
		return s
	# 同步 moved_piece 与 captured 到 move 对象（便于复盘/动画）
	move.moved_piece = Piece.new(piece.type, piece.side, move.from_col, move.from_row)
	var target: Piece = s.get_piece(move.to_col, move.to_row)
	if target != null:
		move.captured = Piece.new(target.type, target.side, target.col, target.row)
		if piece.side == CoreConstants.Side.RED:
			s.captured_by_red.append(Piece.new(target.type, target.side, target.col, target.row))
		else:
			s.captured_by_black.append(Piece.new(target.type, target.side, target.col, target.row))
	else:
		move.captured = null
	# 移动棋子
	s.grid[move.from_row][move.from_col] = null
	s.grid[move.to_row][move.to_col] = piece
	piece.col = move.to_col
	piece.row = move.to_row
	# 反转走棋方
	s.side_to_move = CoreConstants.opponent(piece.side)
	s.turn_number = state.turn_number + 1
	# 判定走完后是否将军对方
	var check_after: bool = RuleValidator.is_in_check(s, s.side_to_move)
	move.is_check = check_after
	s.check_history.append(check_after)
	s.last_move = move
	s.move_history.append(move)
	return s

## 生成合法走法（伪走法 - 送将 - 照面）
static func generate_legal_moves(state: BoardState, side: int) -> Array:
	var out: Array = []
	for p in state.pieces_of(side):
		var pseudo: Array = MoveGenerator.generate_pseudo_moves(state, p)
		for m in pseudo:
			if RuleValidator.is_legal(state, m):
				out.append(m)
	return out

## 便利方法：从 from 到 to 构造走法并应用
## 返回新状态；若走法非法，返回原 state 的深拷贝并 push_warning
static func make_move(state: BoardState, from: Vector2i, to: Vector2i) -> BoardState:
	var piece: Piece = state.get_piece(from.x, from.y)
	if piece == null:
		push_warning("GameController.make_move: no piece at %s" % [from])
		return state.deep_copy()
	var move: Move = Move.new(from.x, from.y, to.x, to.y, piece, state.get_piece(to.x, to.y))
	if not RuleValidator.is_legal(state, move):
		push_warning("GameController.make_move: illegal move %s" % [move])
		return state.deep_copy()
	return apply_move(state, move)

## 判断当前局面是否终局（将死/困毙/长将和棋）
## 返回 Dictionary：{over: bool, result: "red_win"/"black_win"/"draw"/null}
static func check_game_over(state: BoardState) -> Dictionary:
	var side: int = state.side_to_move
	if RuleValidator.is_checkmate(state, side):
		# side 被将死，对方胜
		var winner: String = "red_win" if CoreConstants.opponent(side) == CoreConstants.Side.RED else "black_win"
		return {"over": true, "result": winner}
	if RuleValidator.is_stalemate(state, side):
		return {"over": true, "result": "draw"}
	if RuleValidator.is_perpetual_check_draw(state):
		return {"over": true, "result": "draw"}
	return {"over": false, "result": null}
