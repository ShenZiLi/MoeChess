## 规则校验单元测试 — 验收 A3（九宫/不过河限制）/ A4（兵过河）/ A5（送将过滤）/ A6（将军判定）/ A7（将死）/ A8（困毙）/ A9（长将判和）/ A10（将帅照面）
## 关联：docs/development/test-cases.md TC-A3 ~ TC-A10、acceptance-standard.md A3-A10
## 关联实现：scripts/core/rule_validator.gd、scripts/core/move_generator.gd、scripts/core/game_controller.gd
extends GutTest

const PT = CoreConstants.PieceType
const SD = CoreConstants.Side

# -------------------- 工具 --------------------

func _empty_state_with_kings() -> BoardState:
	"""构造空棋盘，仅放红帅 4,0 与黑将 4,9（避免 find_king 返回 null）"""
	var s: BoardState = BoardState.new()
	s.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	s.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	return s

func _has_target(arr: Array, target: Array) -> bool:
	for entry in arr:
		if entry[0] == target[0] and entry[1] == target[1]:
			return true
	return false

func _to_targets(moves: Array) -> Array:
	var out: Array = []
	for m in moves:
		out.append([m.to_col, m.to_row])
	return out

# -------------------- A3：九宫/不过河限制 --------------------

## TC-A3-001：将/帅不得出九宫
func test_king_cannot_leave_palace() -> void:
	# arrange：自定义空棋盘，红帅 4,1（九宫内中心）；同时放黑将 4,9 避免异常
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 1, Piece.new(PT.KING, SD.RED, 4, 1))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 1))
	# assert：走法 = {(3,1),(5,1),(4,0),(4,2)} 全部在九宫 row 0-2 / col 3-5
	var got: Array = _to_targets(moves)
	for t in got:
		assert_true(CoreConstants.in_palace(t[0], t[1], SD.RED), "红帅走法目标 (%d,%d) 必须在九宫内" % [t[0], t[1]])
	assert_false(_has_target(got, [2, 1]), "红帅不可走出九宫到 (2,1)")
	assert_false(_has_target(got, [6, 1]), "红帅不可走出九宫到 (6,1)")
	# 不含斜走（红帅走法总数 = 4 个直走方向，假设无阻挡）
	assert_eq(got.size(), 4, "红帅 4,1 在九宫中心应有 4 个直走目标")

## TC-A3-002：士不得出九宫
func test_advisor_cannot_leave_palace() -> void:
	# arrange：自定义空棋盘，红士 4,1（九宫内中心）
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 1, Piece.new(PT.ADVISOR, SD.RED, 4, 1))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 1))
	# assert：走法 = {(3,0),(5,0),(3,2),(5,2)} 全部在九宫内
	var got: Array = _to_targets(moves)
	for t in got:
		assert_true(CoreConstants.in_palace(t[0], t[1], SD.RED), "红士走法目标 (%d,%d) 必须在九宫内" % [t[0], t[1]])
	assert_eq(got.size(), 4, "红士 4,1 在九宫中心应有 4 个斜走目标")

## TC-A3-003：象不得过河
func test_elephant_cannot_cross_river() -> void:
	# arrange：自定义空棋盘，红象 4,4（红方本区上沿，河边）
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 4, Piece.new(PT.ELEPHANT, SD.RED, 4, 4))
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 4))
	# assert：所有走法目标必须在红方半场（row <= 4）
	var got: Array = _to_targets(moves)
	for t in got:
		assert_true(t[1] <= 4, "红象走法目标 (%d,%d) 不得过河（row>4）" % [t[0], t[1]])
	# 红象 4,4 的合法田字目标：(2,2) 和 (6,2) 在本区；(2,6) 和 (6,6) 过河应禁止
	assert_true(_has_target(got, [2, 2]), "红象应可走 (2,2)")
	assert_true(_has_target(got, [6, 2]), "红象应可走 (6,2)")
	assert_false(_has_target(got, [2, 6]), "红象不得过河到 (2,6)")
	assert_false(_has_target(got, [6, 6]), "红象不得过河到 (6,6)")

# -------------------- A4：兵过河 --------------------

## TC-A4-001：兵未过河只能前进（红兵 0,3，未过河）
func test_pawn_before_river_no_horizontal() -> void:
	# arrange：自定义空棋盘，红兵 0,3
	var state: BoardState = _empty_state_with_kings()
	state.set_piece_internal(0, 3, Piece.new(PT.PAWN, SD.RED, 0, 3))
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(0, 3))
	# assert：走法 = {(0,4)}（仅前进一格 row+1）；不含左右、不含后退
	var got: Array = _to_targets(moves)
	assert_eq(got.size(), 1, "红兵未过河应仅有 1 个前进走法")
	assert_true(_has_target(got, [0, 4]), "红兵应前进到 (0,4)")
	assert_false(_has_target(got, [1, 3]), "红兵未过河不可横向到 (1,3)")
	assert_false(_has_target(got, [0, 2]), "红兵不可后退到 (0,2)")

## TC-A4-002：兵过河后可左右（红兵 4,5，已过河 = row >= 5）
func test_pawn_after_river_can_horizontal() -> void:
	# arrange：自定义空棋盘，红兵 4,5（已过河）
	var state: BoardState = _empty_state_with_kings()
	state.set_piece_internal(4, 5, Piece.new(PT.PAWN, SD.RED, 4, 5))
	# act
	var moves: Array = MoveGenerator.generate_pseudo_moves(state, state.get_piece(4, 5))
	# assert：走法 = {(4,6),(3,5),(5,5)}（前进 + 左 + 右）；不含后退 (4,4)
	var got: Array = _to_targets(moves)
	assert_true(_has_target(got, [4, 6]), "红兵过河后应可前进到 (4,6)")
	assert_true(_has_target(got, [3, 5]), "红兵过河后应可左移到 (3,5)")
	assert_true(_has_target(got, [5, 5]), "红兵过河后应可右移到 (5,5)")
	assert_false(_has_target(got, [4, 4]), "红兵不可后退到 (4,4)")

# -------------------- A5：is_legal 过滤送将 --------------------

## TC-A5-001：直接送将走法被过滤
## 局面：红帅 4,0，黑车 4,9（同列），红车 4,4 阻挡；红车拟走 4,4→3,4 离开 col 4
## 走完后双将照面 = 红方被将军 → is_legal 返回 false
func test_is_legal_filters_self_check() -> void:
	# arrange
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.set_piece_internal(4, 4, Piece.new(PT.CHARIOT, SD.RED, 4, 4))
	state.side_to_move = SD.RED
	# act：构造红车 4,4→3,4 走法
	var piece: Piece = state.get_piece(4, 4)
	var move: Move = Move.new(4, 4, 3, 4, piece, null)
	var is_legal: bool = RuleValidator.is_legal(state, move)
	# assert：走完后双将同列无遮挡照面 → 红方被将军 → 非法
	assert_false(is_legal, "红车离开 col 4 后双将照面，is_legal 应返回 false")

## TC-A5-002：移动后暴露将军被过滤
## 局面：红帅 4,0，黑车 4,5（同列将军），红士 4,2 挡车；红士走 4,2→3,1 后暴露黑车将军
func test_is_legal_filters_revealed_check() -> void:
	# arrange
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 5, Piece.new(PT.CHARIOT, SD.BLACK, 4, 5))
	state.set_piece_internal(4, 2, Piece.new(PT.ADVISOR, SD.RED, 4, 2))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.side_to_move = SD.RED
	# act：构造红士 4,2→3,1 走法
	var piece: Piece = state.get_piece(4, 2)
	var move: Move = Move.new(4, 2, 3, 1, piece, null)
	var is_legal: bool = RuleValidator.is_legal(state, move)
	# assert：红士移走后黑车在 col 4 直冲红帅 → 红方被将军 → 非法
	assert_false(is_legal, "红士移走后暴露黑车将军，is_legal 应返回 false")

# -------------------- A6：将军判定 --------------------

## TC-A6-001：车将军
func test_is_in_check() -> void:
	# arrange：红帅 4,0，黑车 4,5（同列无遮挡）
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 5, Piece.new(PT.CHARIOT, SD.BLACK, 4, 5))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	# act
	var in_check: bool = RuleValidator.is_in_check(state, SD.RED)
	# assert
	assert_true(in_check, "红方应被黑车将军")

## TC-A6-005：无将军返回 false（起始局面）
func test_is_in_check_initial_false() -> void:
	# arrange
	var state: BoardState = BoardState.initial()
	# act & assert
	assert_false(RuleValidator.is_in_check(state, SD.RED), "起始局面红方不应被将军")
	assert_false(RuleValidator.is_in_check(state, SD.BLACK), "起始局面黑方不应被将军")

# -------------------- A7：将死判定 --------------------

## TC-A7-001：标准将死局面
## 局面：红帅 4,0；黑车 4,1 直接将军；红士 3,0/5,0 阻挡横向逃走；红方无解将走法
func test_is_checkmate() -> void:
	# arrange
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 1, Piece.new(PT.CHARIOT, SD.BLACK, 4, 1))
	state.set_piece_internal(3, 0, Piece.new(PT.ADVISOR, SD.RED, 3, 0))
	state.set_piece_internal(5, 0, Piece.new(PT.ADVISOR, SD.RED, 5, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.side_to_move = SD.RED
	# act
	var in_check: bool = RuleValidator.is_in_check(state, SD.RED)
	var is_mate: bool = RuleValidator.is_checkmate(state, SD.RED)
	var legal_moves: Array = GameController.generate_legal_moves(state, SD.RED)
	# assert：被将军 + 无合法走法 = 将死
	assert_true(in_check, "红方应被将军")
	assert_true(is_mate, "红方应被将死")
	assert_eq(legal_moves.size(), 0, "红方将死时应无合法走法")

## TC-A7-002：可解将非将死
## 局面：红帅 4,0；黑车 4,5（同列将军）；红车 3,0（可走 3,0→4,3 解将）
func test_is_checkmate_false_when_resolvable() -> void:
	# arrange
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 5, Piece.new(PT.CHARIOT, SD.BLACK, 4, 5))
	state.set_piece_internal(3, 0, Piece.new(PT.CHARIOT, SD.RED, 3, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.side_to_move = SD.RED
	# act
	var is_mate: bool = RuleValidator.is_checkmate(state, SD.RED)
	var legal_moves: Array = GameController.generate_legal_moves(state, SD.RED)
	# assert
	assert_false(is_mate, "红方可解将，不应判将死")
	assert_true(legal_moves.size() > 0, "红方应有合法走法解将")

# -------------------- A8：困毙判定 --------------------

## TC-A8-001：困毙局面判定
## 局面：红帅 4,0；红士 3,0/5,0；红象 2,0/6,0（象眼被塞无法走田字）；
## 红士走 4,1 后会被黑车 4,5 将军（被 is_legal 过滤）；
## 红帅被两侧士堵、上方 4,1 走后被将军，导致无合法走法但当前未被将军
func test_is_stalemate() -> void:
	# arrange
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(3, 0, Piece.new(PT.ADVISOR, SD.RED, 3, 0))
	state.set_piece_internal(5, 0, Piece.new(PT.ADVISOR, SD.RED, 5, 0))
	state.set_piece_internal(2, 0, Piece.new(PT.ELEPHANT, SD.RED, 2, 0))
	state.set_piece_internal(6, 0, Piece.new(PT.ELEPHANT, SD.RED, 6, 0))
	# 塞红象眼：(3,1) 和 (5,1) 各放一子
	state.set_piece_internal(3, 1, Piece.new(PT.PAWN, SD.BLACK, 3, 1))
	state.set_piece_internal(5, 1, Piece.new(PT.PAWN, SD.BLACK, 5, 1))
	# 黑车 4,5：阻止红士走 4,1（移到 4,1 会被车将军）
	state.set_piece_internal(4, 5, Piece.new(PT.CHARIOT, SD.BLACK, 4, 5))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.side_to_move = SD.RED
	# act
	var in_check: bool = RuleValidator.is_in_check(state, SD.RED)
	var is_stalemate: bool = RuleValidator.is_stalemate(state, SD.RED)
	var legal_moves: Array = GameController.generate_legal_moves(state, SD.RED)
	# assert：未被将军 + 无合法走法 = 困毙
	assert_false(in_check, "红方不应被将军（困毙前提）")
	assert_true(is_stalemate, "红方应判困毙")
	assert_eq(legal_moves.size(), 0, "困毙时无合法走法")

## TC-A8-002：有合法走法不困毙（起始局面）
func test_is_stalemate_false_when_moves_exist() -> void:
	# arrange
	var state: BoardState = BoardState.initial()
	# act & assert
	assert_false(RuleValidator.is_stalemate(state, SD.RED), "起始红方有合法走法，不困毙")
	assert_false(RuleValidator.is_stalemate(state, SD.BLACK), "起始黑方有合法走法，不困毙")

# -------------------- A10：将帅照面 --------------------

## TC-A10-001：直接照面走法被 is_legal 过滤
## 局面：红帅 4,0，黑将 4,9，红车 4,4（同列 4 阻挡）；红方走子，红车拟走 4,4→3,4 离开 col 4
func test_kings_face_filter() -> void:
	# arrange
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.set_piece_internal(4, 4, Piece.new(PT.CHARIOT, SD.RED, 4, 4))
	state.side_to_move = SD.RED
	# act：构造红车 4,4→3,4 走法
	var piece: Piece = state.get_piece(4, 4)
	var move: Move = Move.new(4, 4, 3, 4, piece, null)
	var is_legal: bool = RuleValidator.is_legal(state, move)
	# assert：移走后双将同列无遮挡照面 → 非法
	assert_false(is_legal, "红车离开 col 4 后双将照面，is_legal 应返回 false")

## TC-A10-002：kings_face 准确判定
func test_kings_face_detection() -> void:
	# arrange (a)：双将同列无遮挡
	var state_a: BoardState = BoardState.new()
	state_a.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state_a.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	# (b)：双将同列中间有子
	var state_b: BoardState = BoardState.new()
	state_b.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state_b.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state_b.set_piece_internal(4, 4, Piece.new(PT.CHARIOT, SD.RED, 4, 4))
	# (c)：双将不同列
	var state_c: BoardState = BoardState.new()
	state_c.set_piece_internal(3, 0, Piece.new(PT.KING, SD.RED, 3, 0))
	state_c.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	# act & assert
	assert_true(RuleValidator.kings_face(state_a), "(a) 双将同列无遮挡应照面")
	assert_false(RuleValidator.kings_face(state_b), "(b) 双将同列中间有子不应照面")
	assert_false(RuleValidator.kings_face(state_c), "(c) 双将不同列不应照面")

# -------------------- A9：长将判和 --------------------

## TC-A9-001：连续将军达限定回合判和
## 简化测试：构造一个 check_history 已达 PERPETUAL_CHECK_LIMIT 全 true 的局面，调用 is_perpetual_check_draw
func test_perpetual_check_draw() -> void:
	# arrange：起始局面 + 注入连续 N 步将军历史（N = PERPETUAL_CHECK_LIMIT）
	var state: BoardState = BoardState.initial()
	var limit: int = CoreConstants.PERPETUAL_CHECK_LIMIT
	state.check_history.clear()
	for i in range(limit):
		state.check_history.append(true)
	# act
	var is_draw: bool = RuleValidator.is_perpetual_check_draw(state)
	# assert
	assert_true(is_draw, "连续 %d 步将军应判长将和棋" % limit)

## TC-A9-002：非连续将军不判和
func test_no_perpetual_check_when_varied() -> void:
	# arrange：check_history 含非将军步
	var state: BoardState = BoardState.initial()
	var limit: int = CoreConstants.PERPETUAL_CHECK_LIMIT
	state.check_history.clear()
	for i in range(limit - 1):
		state.check_history.append(true)
	state.check_history.append(false)  # 最后一步非将军
	# act
	var is_draw: bool = RuleValidator.is_perpetual_check_draw(state)
	# assert
	assert_false(is_draw, "最近一步非将军，不应判长将和棋")
