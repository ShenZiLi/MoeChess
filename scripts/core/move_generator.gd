## 走法生成器（策略模式，每种棋子一个生成函数）
## 关联：scripts/core/constants.gd、scripts/core/piece.gd、scripts/core/move.gd、scripts/core/board_state.gd
## 覆盖验收：A1（七种棋子走法）、A2（蹩马腿/塞象眼/炮翻山）、A3（九宫/不过河限制）、A4（兵过河左右）
##
## 坐标约定（与 CoreConstants 一致）：
## - 9 列 × 10 行，col 0-8、row 0-9
## - row 0 = 红方底线（玩家方/下方），row 9 = 黑方底线（电脑方/上方）
## - 红方前进 = row 增大（forward(RED)=+1）；黑方前进 = row 减小（forward(BLACK)=-1）
## - 红方九宫 row 0-2 / cols 3-5；黑方九宫 row 7-9 / cols 3-5
## - 红方半场 row 0-4；黑方半场 row 5-9
##
## 本类只生成"伪走法"（pseudo moves）：不考虑走完后己方是否被将军（送将过滤由 RuleValidator 负责）。
class_name MoveGenerator
extends RefCounted

## 单棋子伪走法（不含送将过滤）
static func generate_pseudo_moves(state: BoardState, piece: Piece) -> Array:
	if piece == null:
		return []
	match piece.type:
		CoreConstants.PieceType.KING:
			return _gen_king(state, piece)
		CoreConstants.PieceType.ADVISOR:
			return _gen_advisor(state, piece)
		CoreConstants.PieceType.ELEPHANT:
			return _gen_elephant(state, piece)
		CoreConstants.PieceType.HORSE:
			return _gen_horse(state, piece)
		CoreConstants.PieceType.CHARIOT:
			return _gen_chariot(state, piece)
		CoreConstants.PieceType.CANNON:
			return _gen_cannon(state, piece)
		CoreConstants.PieceType.PAWN:
			return _gen_pawn(state, piece)
		_:
			return []

## 全阵营伪走法
static func generate_all_pseudo_moves(state: BoardState, side: int) -> Array:
	var out: Array = []
	for p in state.pieces_of(side):
		out.append_array(generate_pseudo_moves(state, p))
	return out

# -------------------- 各棋子走法 --------------------

## 将/帅：九宫内一步直走（上下左右），不可斜走，不可出九宫
static func _gen_king(state: BoardState, piece: Piece) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	for d in dirs:
		var nc: int = piece.col + d.x
		var nr: int = piece.row + d.y
		if not CoreConstants.in_bounds(nc, nr):
			continue
		if not CoreConstants.in_palace(nc, nr, piece.side):
			continue
		var target: Piece = state.get_piece(nc, nr)
		if target != null and target.side == piece.side:
			continue
		out.append(_make_move(piece, nc, nr, target))
	return out

## 士：九宫内斜走一步
static func _gen_advisor(state: BoardState, piece: Piece) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for d in dirs:
		var nc: int = piece.col + d.x
		var nr: int = piece.row + d.y
		if not CoreConstants.in_bounds(nc, nr):
			continue
		if not CoreConstants.in_palace(nc, nr, piece.side):
			continue
		var target: Piece = state.get_piece(nc, nr)
		if target != null and target.side == piece.side:
			continue
		out.append(_make_move(piece, nc, nr, target))
	return out

## 象：田字步（斜走 2 格），不过河，塞象眼（中间格有子则不能走）
static func _gen_elephant(state: BoardState, piece: Piece) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for d in dirs:
		var nc: int = piece.col + d.x * 2
		var nr: int = piece.row + d.y * 2
		if not CoreConstants.in_bounds(nc, nr):
			continue
		# 不过河：目标格必须在己方半场
		if not CoreConstants.in_home_half(nc, nr, piece.side):
			continue
		# 塞象眼：中间格有子则不能走
		var eye_c: int = piece.col + d.x
		var eye_r: int = piece.row + d.y
		if state.get_piece(eye_c, eye_r) != null:
			continue
		var target: Piece = state.get_piece(nc, nr)
		if target != null and target.side == piece.side:
			continue
		out.append(_make_move(piece, nc, nr, target))
	return out

## 马：日字步（先直走 1 格再斜走 1 格），蹩马腿（直走的那格有子则不能走）
static func _gen_horse(state: BoardState, piece: Piece) -> Array:
	var out: Array = []
	# 8 个日字目标，每个对应一个马腿格
	# 格式：(目标 col 偏移, 目标 row 偏移, 马腿 col 偏移, 马腿 row 偏移)
	var targets: Array = [
		[1, 2, 0, 1],   # 右下（先向下走 1）
		[-1, 2, 0, 1],  # 左下
		[1, -2, 0, -1], # 右上
		[-1, -2, 0, -1],# 左上
		[2, 1, 1, 0],   # 右下（先向右走 1）
		[2, -1, 1, 0],  # 右上
		[-2, 1, -1, 0], # 左下
		[-2, -1, -1, 0],# 左上
	]
	for t in targets:
		var nc: int = piece.col + t[0]
		var nr: int = piece.row + t[1]
		if not CoreConstants.in_bounds(nc, nr):
			continue
		# 蹩马腿
		var leg_c: int = piece.col + t[2]
		var leg_r: int = piece.row + t[3]
		if state.get_piece(leg_c, leg_r) != null:
			continue
		var target: Piece = state.get_piece(nc, nr)
		if target != null and target.side == piece.side:
			continue
		out.append(_make_move(piece, nc, nr, target))
	return out

## 车：直线任意格，遇己方子停止，遇敌方子可吃后停止，遇空格可继续
static func _gen_chariot(state: BoardState, piece: Piece) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	for d in dirs:
		var nc: int = piece.col + d.x
		var nr: int = piece.row + d.y
		while CoreConstants.in_bounds(nc, nr):
			var target: Piece = state.get_piece(nc, nr)
			if target == null:
				out.append(_make_move(piece, nc, nr, null))
			else:
				if target.side != piece.side:
					out.append(_make_move(piece, nc, nr, target))
				break
			nc += d.x
			nr += d.y
	return out

## 炮：直线任意格移动（不吃子时同车，遇阻停止）；吃子时必须隔恰好 1 子（炮架）翻山
static func _gen_cannon(state: BoardState, piece: Piece) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	for d in dirs:
		var nc: int = piece.col + d.x
		var nr: int = piece.row + d.y
		var jumped: bool = false
		while CoreConstants.in_bounds(nc, nr):
			var target: Piece = state.get_piece(nc, nr)
			if not jumped:
				if target == null:
					out.append(_make_move(piece, nc, nr, null))
				else:
					# 遇到第一个子，作为炮架
					jumped = true
			else:
				# 已翻山，找落点
				if target != null:
					if target.side != piece.side:
						out.append(_make_move(piece, nc, nr, target))
					break
			nc += d.x
			nr += d.y
	return out

## 兵：未过河只前进 1 格；过河后可前进/左/右 1 格，禁后退
static func _gen_pawn(state: BoardState, piece: Piece) -> Array:
	var out: Array = []
	var fwd: int = CoreConstants.forward(piece.side)
	# 前进
	var nc: int = piece.col
	var nr: int = piece.row + fwd
	if CoreConstants.in_bounds(nc, nr):
		var target: Piece = state.get_piece(nc, nr)
		if target == null or target.side != piece.side:
			out.append(_make_move(piece, nc, nr, target))
	# 过河后可左右
	if CoreConstants.pawn_crossed_river(piece.row, piece.side):
		for dc in [-1, 1]:
			nc = piece.col + dc
			nr = piece.row
			if not CoreConstants.in_bounds(nc, nr):
				continue
			var target: Piece = state.get_piece(nc, nr)
			if target == null or target.side != piece.side:
				out.append(_make_move(piece, nc, nr, target))
	return out

# -------------------- 工具 --------------------

## 构造走法对象
static func _make_move(piece: Piece, to_col: int, to_row: int, captured: Piece) -> Move:
	return Move.new(piece.col, piece.row, to_col, to_row, piece, captured)
