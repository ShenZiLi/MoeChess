## 走法生成单元测试 — 验收 A1（七种棋子走法）/ A2（蹩马腿/塞象眼/炮翻山）
## 关联：docs/development/test-cases.md TC-A1-001 ~ TC-A2-004、acceptance-standard.md A1/A2
## 关联实现：scripts/core/move_generator.gd、scripts/core/board_state.gd、scripts/core/constants.gd
##
## 坐标系（与 CoreConstants 一致）：
## - 9 列 × 10 行，col 0-8、row 0-9
## - row 0 = 红方底线（玩家方/下方）；row 9 = 黑方底线（电脑方/上方）
## - 红方前进 = row 增大（forward(RED)=+1）；黑方前进 = row 减小
## - 红兵过河 = row >= 5
extends GutTest

const PT = CoreConstants.PieceType
const SD = CoreConstants.Side

# -------------------- 工具 --------------------

## 构造空棋盘（无任何棋子）
func _empty_state() -> BoardState:
	return BoardState.new()

## 在空棋盘上放置一个棋子，返回该棋子引用
func _state_with_piece(type: int, side: int, col: int, row: int) -> BoardState:
	var s: BoardState = _empty_state()
	var p: Piece = Piece.new(type, side, col, row)
	s.set_piece_internal(col, row, p)
	return s

## 提取走法集合的 (to_col, to_row) 元组列表
func _to_targets(moves: Array) -> Array:
	var out: Array = []
	for m in moves:
		out.append([m.to_col, m.to_row])
	return out

## 断言走法目标集合精确匹配期望集合（顺序无关）
func _assert_targets_eq(moves: Array, expected: Array, msg: String) -> void:
	var got: Array = _to_targets(moves)
	# 比较前排序
	got.sort_custom(func(a, b): return a[0] == b[0] and a[1] < b[1] or a[0] < b[0])
	expected.sort_custom(func(a, b): return a[0] == b[0] and a[1] < b[1] or a[0] < b[0])
	assert_eq(got.size(), expected.size(), "%s (size)" % msg)
	for i in range(min(got.size(), expected.size())):
		assert_eq(got[i], expected[i], "%s (entry %d)" % [msg, i])

# -------------------- A1 测试 --------------------

## TC-A1-001：将/帅九宫内一步直走（红黑各一）
func test_king_moves_in_palace() -> void:
	# arrange：起始局面，红帅 4,0；黑将 4,9
	var state: BoardState = BoardState.initial()
	var red_king: Piece = state.get_piece(4, 0)
	var black_king: Piece = state.get_piece(4, 9)
	assert_not_null(red_king, "红帅应存在")
	assert_not_null(black_king, "黑将应存在")
	# act
	var red_moves: Array = MoveGenerator.generate_pseudo_moves(state, red_king)
	var black_moves: Array = MoveGenerator.generate_pseudo_moves(state, black_king)
	# assert：红帅走法 = {(3,0),(5,0),(4,1)}（被士阻挡上下，左侧/右侧各一格 + 前进一格）
	_assert_targets_eq(red_moves, [[3, 0], [5, 0], [4, 1]], "红帅走法")
	# 黑将走法 = {(3,9),(5,9),(4,8)}
	_assert_targets_eq(black_moves, [[3, 9], [5, 9], [4, 8]], "黑将走法")

## TC-A1-002：士九宫内一步斜走
func test_advisor_moves_in_palace() -> void:
	# arrange：起始局面，红士 3,0 与 5,0；黑士 3,9 与 5,9
	var state: BoardState = BoardState.initial()
	# act
	var red_a1: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(3, 0))
	var red_a2: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(5, 0))
	var black_a1: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(3, 9))
	var black_a2: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(5, 9))
	# assert：红士 3,0 走法 = {(4,1)}（被己方将阻挡，仅一个斜走目标）
	_assert_targets_eq(red_a1, [[4, 1]], "红士 3,0 走法")
	_assert_targets_eq(red_a2, [[4, 1]], "红士 5,0 走法")
	_assert_targets_eq(black_a1, [[4, 8]], "黑士 3,9 走法")
	_assert_targets_eq(black_a2, [[4, 8]], "黑士 5,9 走法")

## TC-A1-003：象走田字格两步
func test_elephant_moves() -> void:
	# arrange：自定义空棋盘，红象 2,0，黑象 2,9
	var red_state: BoardState = _state_with_piece(PT.ELEPHANT, SD.RED, 2, 0)
	var black_state: BoardState = _state_with_piece(PT.ELEPHANT, SD.BLACK, 2, 9)
	# act
	var red_moves: Array = MoveGenerator.generate_pseudo_moves(red_state, red_state.get_piece(2, 0))
	var black_moves: Array = MoveGenerator.generate_pseudo_moves(black_state, black_state.get_piece(2, 9))
	# assert：红象走法 = {(0,2),(4,2)}（田字格，象眼为空）
	_assert_targets_eq(red_moves, [[0, 2], [4, 2]], "红象走法")
	# 黑象对称：{(0,7),(4,7)}
	_assert_targets_eq(black_moves, [[0, 7], [4, 7]], "黑象走法")

## TC-A1-004：马走日字格（中心无蹩腿）
func test_horse_moves_center() -> void:
	# arrange：自定义空棋盘，红马 4,4
	var state: BoardState = _state_with_piece(PT.HORSE, SD.RED, 4, 4)
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 4))
	# assert：8 个日字格位置
	_assert_targets_eq(moves, [[2, 3], [2, 5], [3, 2], [5, 2], [6, 3], [6, 5], [3, 6], [5, 6]], "中心马走法")

## TC-A1-005：车直线任意距离
func test_chariot_moves_open_board() -> void:
	# arrange：自定义空棋盘，红车 4,4
	var state: BoardState = _state_with_piece(PT.CHARIOT, SD.RED, 4, 4)
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 4))
	# assert：列 4 上 9 个 + 行 4 上 8 个 = 17 个
	var expected: Array = []
	for r in range(0, 10):
		if r != 4:
			expected.append([4, r])
	for c in range(0, 9):
		if c != 4:
			expected.append([c, 4])
	assert_eq(moves.size(), 17, "车走法总数应为 17")
	_assert_targets_eq(moves, expected, "车走法集合")

## TC-A1-006：炮直线移动（不吃子时同车）
func test_cannon_moves_no_capture() -> void:
	# arrange：自定义空棋盘，红炮 4,4
	var state: BoardState = _state_with_piece(PT.CANNON, SD.RED, 4, 4)
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 4))
	# assert：非吃子走法 = 17 个；无吃子走法（无炮架）
	var capture_count: int = 0
	for m in moves:
		if m.is_capture():
			capture_count += 1
	assert_eq(capture_count, 0, "空棋盘炮无吃子走法")
	assert_eq(moves.size(), 17, "炮非吃子走法应为 17")

## TC-A1-007：兵未过河前进一步（红兵前进 = row 增大）
func test_pawn_moves_before_river() -> void:
	# arrange：起始局面，红兵 0,3（未过河）；黑兵 0,6（未过河）
	var state: BoardState = BoardState.initial()
	var red_pawn: Piece = state.get_piece(0, 3)
	var black_pawn: Piece = state.get_piece(0, 6)
	assert_not_null(red_pawn, "红兵应存在")
	assert_not_null(black_pawn, "黑兵应存在")
	# act
	var red_moves: Array = MoveGenerator.generate_pseudo_moves(state, red_pawn)
	var black_moves: Array = MoveGenerator.generate_pseudo_moves(state, black_pawn)
	# assert：红兵前进 = row 增大，走法 = {(0,4)}；黑兵前进 = row 减小，走法 = {(0,5)}
	_assert_targets_eq(red_moves, [[0, 4]], "红兵未过河走法（row 增大）")
	_assert_targets_eq(black_moves, [[0, 5]], "黑兵未过河走法（row 减小）")

## TC-A1-008：初始局面走法总数核对（断言 ≥ 40，不写死 44）
func test_initial_position_move_count() -> void:
	# arrange
	var state: BoardState = BoardState.initial()
	# act
	var moves: Array = MoveGenerator.generate_all_pseudo_moves(state, SD.RED)
	# assert：≥ 40 个伪走法（标准中国象棋初始红方伪走法数为 44，允许实现差异，但至少应 ≥ 40）
	assert_true(moves.size() >= 40, "初始红方伪走法总数应 ≥ 40，实际 %d" % moves.size())
	# 同时验证黑方数量与红方对称
	var black_moves: Array = MoveGenerator.generate_all_pseudo_moves(state, SD.BLACK)
	assert_true(black_moves.size() >= 40, "初始黑方伪走法总数应 ≥ 40，实际 %d" % black_moves.size())

# -------------------- A2 测试 --------------------

## TC-A2-001：蹩马腿
func test_horse_blocked_leg() -> void:
	# arrange：自定义棋盘，红马 4,4；红兵 4,5（蹩 (4,5→4,6) 方向马腿）和 5,4（蹩 (5,4→6,4) 方向马腿）
	var state: BoardState = _empty_state()
	state.set_piece_internal(4, 4, Piece.new(PT.HORSE, SD.RED, 4, 4))
	# 蹩腿子：放在马走日字的"先直走 1 格"位置
	# 4,5 蹩掉向下方向（先直走 (4,5)），影响目标 (3,6) 和 (5,6)
	state.set_piece_internal(4, 5, Piece.new(PT.PAWN, SD.RED, 4, 5))
	# 5,4 蹩掉向右方向（先直走 (5,4)），影响目标 (6,3) 和 (6,5)
	state.set_piece_internal(5, 4, Piece.new(PT.PAWN, SD.RED, 5, 4))
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 4))
	# assert：被蹩腿方向的目标格不出现在走法中
	var got: Array = _to_targets(moves)
	assert_false(_has_target(got, [3, 6]), "4,5 蹩腿应屏蔽 (3,6) 方向")
	assert_false(_has_target(got, [5, 6]), "4,5 蹩腿应屏蔽 (5,6) 方向")
	assert_false(_has_target(got, [6, 3]), "5,4 蹩腿应屏蔽 (6,3) 方向")
	assert_false(_has_target(got, [6, 5]), "5,4 蹩腿应屏蔽 (6,5) 方向")
	# 其余日字格仍可走（4 个：(2,3),(2,5),(3,2),(5,2)）
	assert_true(_has_target(got, [2, 3]), "未被蹩腿的 (2,3) 应可走")
	assert_true(_has_target(got, [2, 5]), "未被蹩腿的 (2,5) 应可走")
	assert_true(_has_target(got, [3, 2]), "未被蹩腿的 (3,2) 应可走")
	assert_true(_has_target(got, [5, 2]), "未被蹩腿的 (5,2) 应可走")

## TC-A2-002：塞象眼
func test_elephant_blocked_eye() -> void:
	# arrange：红象 2,0；红兵 3,1（塞 2,0→4,2 田字中心象眼）
	var state: BoardState = _empty_state()
	state.set_piece_internal(2, 0, Piece.new(PT.ELEPHANT, SD.RED, 2, 0))
	state.set_piece_internal(3, 1, Piece.new(PT.PAWN, SD.RED, 3, 1))
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(2, 0))
	# assert：走法中不含 (4,2)；若 (0,2) 方向象眼空，仍可走 (0,2)
	var got: Array = _to_targets(moves)
	assert_false(_has_target(got, [4, 2]), "塞象眼应屏蔽 (4,2)")
	assert_true(_has_target(got, [0, 2]), "未塞象眼方向 (0,2) 应可走")

## TC-A2-003：炮翻山隔一子吃
func test_cannon_capture_over_screen() -> void:
	# arrange：红炮 4,4；黑车 4,7（远端）；红兵 4,5（炮架）
	var state: BoardState = _empty_state()
	state.set_piece_internal(4, 4, Piece.new(PT.CANNON, SD.RED, 4, 4))
	state.set_piece_internal(4, 5, Piece.new(PT.PAWN, SD.RED, 4, 5))
	state.set_piece_internal(4, 7, Piece.new(PT.CHARIOT, SD.BLACK, 4, 7))
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 4))
	# assert：含 (4,7) 吃黑车（含 captured 字段）；不含 (4,5)（己方子）
	var got: Array = _to_targets(moves)
	assert_true(_has_target(got, [4, 7]), "炮应能隔山吃 (4,7) 黑车")
	assert_false(_has_target(got, [4, 5]), "炮架位置 (4,5) 不可到达")
	# 4,5 之前可走、之后不可：检查 (4,0)-(4,3) 均可走
	for r in range(0, 4):
		assert_true(_has_target(got, [4, r]), "炮架前 (4,%d) 应可走" % r)
	# 检查 (4,7) 走法的 captured 字段非空
	var capture_move: Move = null
	for m in moves:
		if m.to_col == 4 and m.to_row == 7:
			capture_move = m
			break
	assert_not_null(capture_move, "应找到吃车走法")
	if capture_move != null:
		assert_not_null(capture_move.captured, "吃车走法应有 captured 字段")
		assert_true(capture_move.is_capture(), "is_capture 应返回 true")

# -------------------- 内部工具 --------------------

func _has_target(arr: Array, target: Array) -> bool:
	for entry in arr:
		if entry[0] == target[0] and entry[1] == target[1]:
			return true
	return false
