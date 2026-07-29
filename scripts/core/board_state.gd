## 棋盘状态（不可变更新模型，便于 AI 搜索分支 / 悔棋 / 复盘）
## 关联：scripts/core/piece.gd、scripts/core/move.gd、docs/plans/2026-07-28-moechess-design.md §3.3
##
## 约定：
## - grid[row][col] 存 Piece 或 null；row 0-9、col 0-8
## - row 0 = 红方底线（玩家方/下方）；row 9 = 黑方底线（电脑方/上方）
## - apply_move 返回新 BoardState（不原地修改）
class_name BoardState
extends RefCounted

var grid: Array            # Array[Array[Piece/null]]，外层 row 0..9，内层 col 0..8
var side_to_move: int      # CoreConstants.Side，当前轮到走棋的一方
var move_history: Array    # Array[Move]
var captured_by_red: Array  # Array[Piece] 红方吃掉的棋子（即被吃的黑方棋子）
var captured_by_black: Array # Array[Piece] 黑方吃掉的棋子（即被吃的红方棋子）
var last_move: Move         # 最近一步（便于视觉层高亮起点/终点）
var turn_number: int        # 半回合数（每方走一步 +1，从 1 起）
var check_history: Array    # Array[bool]，每步走完后是否将军对方（用于长将判和）

func _init() -> void:
	grid = []
	for r in range(CoreConstants.ROWS):
		var row_arr: Array = []
		row_arr.resize(CoreConstants.COLS)
		for c in range(CoreConstants.COLS):
			row_arr[c] = null
		grid.append(row_arr)
	side_to_move = CoreConstants.Side.RED
	move_history = []
	captured_by_red = []
	captured_by_black = []
	last_move = null
	turn_number = 0
	check_history = []

## 标准初始局面（红方在 row 0-2，黑方在 row 7-9）
static func initial() -> BoardState:
	var s: BoardState = BoardState.new()
	# 红方底线（row 0）
	s.set_piece_internal(0, 0, Piece.new(CoreConstants.PieceType.CHARIOT, CoreConstants.Side.RED, 0, 0))
	s.set_piece_internal(1, 0, Piece.new(CoreConstants.PieceType.HORSE, CoreConstants.Side.RED, 1, 0))
	s.set_piece_internal(2, 0, Piece.new(CoreConstants.PieceType.ELEPHANT, CoreConstants.Side.RED, 2, 0))
	s.set_piece_internal(3, 0, Piece.new(CoreConstants.PieceType.ADVISOR, CoreConstants.Side.RED, 3, 0))
	s.set_piece_internal(4, 0, Piece.new(CoreConstants.PieceType.KING, CoreConstants.Side.RED, 4, 0))
	s.set_piece_internal(5, 0, Piece.new(CoreConstants.PieceType.ADVISOR, CoreConstants.Side.RED, 5, 0))
	s.set_piece_internal(6, 0, Piece.new(CoreConstants.PieceType.ELEPHANT, CoreConstants.Side.RED, 6, 0))
	s.set_piece_internal(7, 0, Piece.new(CoreConstants.PieceType.HORSE, CoreConstants.Side.RED, 7, 0))
	s.set_piece_internal(8, 0, Piece.new(CoreConstants.PieceType.CHARIOT, CoreConstants.Side.RED, 8, 0))
	# 红方炮（row 2）
	s.set_piece_internal(1, 2, Piece.new(CoreConstants.PieceType.CANNON, CoreConstants.Side.RED, 1, 2))
	s.set_piece_internal(7, 2, Piece.new(CoreConstants.PieceType.CANNON, CoreConstants.Side.RED, 7, 2))
	# 红方兵（row 3）
	for c in [0, 2, 4, 6, 8]:
		s.set_piece_internal(c, 3, Piece.new(CoreConstants.PieceType.PAWN, CoreConstants.Side.RED, c, 3))
	# 黑方底线（row 9）
	s.set_piece_internal(0, 9, Piece.new(CoreConstants.PieceType.CHARIOT, CoreConstants.Side.BLACK, 0, 9))
	s.set_piece_internal(1, 9, Piece.new(CoreConstants.PieceType.HORSE, CoreConstants.Side.BLACK, 1, 9))
	s.set_piece_internal(2, 9, Piece.new(CoreConstants.PieceType.ELEPHANT, CoreConstants.Side.BLACK, 2, 9))
	s.set_piece_internal(3, 9, Piece.new(CoreConstants.PieceType.ADVISOR, CoreConstants.Side.BLACK, 3, 9))
	s.set_piece_internal(4, 9, Piece.new(CoreConstants.PieceType.KING, CoreConstants.Side.BLACK, 4, 9))
	s.set_piece_internal(5, 9, Piece.new(CoreConstants.PieceType.ADVISOR, CoreConstants.Side.BLACK, 5, 9))
	s.set_piece_internal(6, 9, Piece.new(CoreConstants.PieceType.ELEPHANT, CoreConstants.Side.BLACK, 6, 9))
	s.set_piece_internal(7, 9, Piece.new(CoreConstants.PieceType.HORSE, CoreConstants.Side.BLACK, 7, 9))
	s.set_piece_internal(8, 9, Piece.new(CoreConstants.PieceType.CHARIOT, CoreConstants.Side.BLACK, 8, 9))
	# 黑方炮（row 7）
	s.set_piece_internal(1, 7, Piece.new(CoreConstants.PieceType.CANNON, CoreConstants.Side.BLACK, 1, 7))
	s.set_piece_internal(7, 7, Piece.new(CoreConstants.PieceType.CANNON, CoreConstants.Side.BLACK, 7, 7))
	# 黑方卒（row 6）
	for c in [0, 2, 4, 6, 8]:
		s.set_piece_internal(c, 6, Piece.new(CoreConstants.PieceType.PAWN, CoreConstants.Side.BLACK, c, 6))
	s.side_to_move = CoreConstants.Side.RED
	s.turn_number = 1
	return s

## 深拷贝（用于 apply_move 生成新状态）
func deep_copy() -> BoardState:
	var s: BoardState = BoardState.new()
	for r in range(CoreConstants.ROWS):
		for c in range(CoreConstants.COLS):
			var p: Piece = grid[r][c]
			if p != null:
				s.grid[r][c] = Piece.new(p.type, p.side, p.col, p.row)
	s.side_to_move = side_to_move
	s.move_history = move_history.duplicate(true)
	s.captured_by_red = captured_by_red.duplicate(true)
	s.captured_by_black = captured_by_black.duplicate(true)
	s.last_move = last_move
	s.turn_number = turn_number
	s.check_history = check_history.duplicate()
	return s

## 内部：设置格子棋子（不校验越界，调用方需保证 col/row 合法）
## 注意：函数名不能是 _set——会覆盖 Object.set_piece_internal(StringName, Variant) -> bool 虚函数
func set_piece_internal(col: int, row: int, piece: Piece) -> void:
	grid[row][col] = piece

func get_piece(col: int, row: int) -> Piece:
	if not CoreConstants.in_bounds(col, row):
		return null
	return grid[row][col]

func get_piece_at(pos: Vector2i) -> Piece:
	return get_piece(pos.x, pos.y)

## 列出某阵营所有棋子（顺序：row 升序，col 升序）
func pieces_of(side: int) -> Array:
	var out: Array = []
	for r in range(CoreConstants.ROWS):
		for c in range(CoreConstants.COLS):
			var p: Piece = grid[r][c]
			if p != null and p.side == side:
				out.append(p)
	return out

## 找指定阵营的将/帅
func find_king(side: int) -> Piece:
	for r in range(CoreConstants.ROWS):
		for c in range(CoreConstants.COLS):
			var p: Piece = grid[r][c]
			if p != null and p.side == side and p.type == CoreConstants.PieceType.KING:
				return p
	return null

## 棋盘快照字典（用于存档/复盘）
func to_dict() -> Dictionary:
	var pieces_arr: Array = []
	for r in range(CoreConstants.ROWS):
		for c in range(CoreConstants.COLS):
			var p: Piece = grid[r][c]
			if p != null:
				pieces_arr.append(p.to_dict())
	var history_arr: Array = []
	for m in move_history:
		history_arr.append(m.to_dict())
	return {
		"side_to_move": side_to_move,
		"turn_number": turn_number,
		"pieces": pieces_arr,
		"move_history": history_arr,
		"check_history": check_history.duplicate(),
	}

static func from_dict(d: Dictionary) -> BoardState:
	var s: BoardState = BoardState.new()
	var pieces_arr: Array = d.get("pieces", [])
	for pd in pieces_arr:
		var p: Piece = Piece.from_dict(pd)
		s.grid[p.row][p.col] = p
	s.side_to_move = int(d.get("side_to_move", CoreConstants.Side.RED))
	s.turn_number = int(d.get("turn_number", 1))
	var history_arr: Array = d.get("move_history", [])
	for md in history_arr:
		s.move_history.append(Move.from_dict(md))
	s.check_history = Array(d.get("check_history", []), TYPE_INT, "null", null)
	return s

func _to_string() -> String:
	var lines: Array = []
	for r in range(CoreConstants.ROWS - 1, -1, -1):
		var chars: Array = []
		for c in range(CoreConstants.COLS):
			var p: Piece = grid[r][c]
			if p == null:
				chars.append(".")
			else:
				var ch: String = CoreConstants.TYPE_TO_KEY.get(p.type, "?")[0]
				if p.side == CoreConstants.Side.BLACK:
					ch = ch.to_upper()
				chars.append(ch)
		lines.append("".join(chars))
	return "\n".join(lines)
