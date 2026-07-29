## 游戏控制器集成测试 — apply_move / generate_legal_moves / check_game_over
## 关联：docs/development/test-cases.md TC-G1 / TC-A5 / TC-A7 / TC-A8、acceptance-standard.md A5/A7/A8/G1
## 关联实现：scripts/core/game_controller.gd、scripts/core/rule_validator.gd、scripts/core/board_state.gd
extends GutTest

const PT = CoreConstants.PieceType
const SD = CoreConstants.Side

# -------------------- apply_move --------------------

## TC-apply-001：apply_move 返回新状态（不可变更新）
func test_apply_move_returns_new_state() -> void:
	# arrange：起始局面，红兵 4,3→4,4
	var state: BoardState = BoardState.initial()
	var piece: Piece = state.get_piece(4, 3)
	var move: Move = Move.new(4, 3, 4, 4, piece, null)
	# act
	var new_state: BoardState = GameController.apply_move(state, move)
	# assert：返回新对象，原 state 未被修改
	assert_not_null(new_state, "apply_move 应返回新 BoardState")
	assert_true(new_state != state, "apply_move 应返回新对象，不原地修改")
	# 原 state 的 (4,3) 仍有红兵
	assert_not_null(state.get_piece(4, 3), "原 state 的 (4,3) 应仍有红兵")
	# 新 state 的 (4,3) 为空、(4,4) 有红兵
	assert_null(new_state.get_piece(4, 3), "新 state 的 (4,3) 应为空")
	assert_not_null(new_state.get_piece(4, 4), "新 state 的 (4,4) 应有红兵")

## TC-apply-002：apply_move 记录 move_history
func test_apply_move_records_history() -> void:
	# arrange
	var state: BoardState = BoardState.initial()
	var piece: Piece = state.get_piece(4, 3)
	var move: Move = Move.new(4, 3, 4, 4, piece, null)
	var history_before: int = state.move_history.size()
	# act
	var new_state: BoardState = GameController.apply_move(state, move)
	# assert
	assert_eq(new_state.move_history.size(), history_before + 1, "move_history 应追加 1 条")
	var last_move: Move = new_state.move_history.back()
	assert_eq(last_move.from_col, 4, "最后一步 from_col=4")
	assert_eq(last_move.from_row, 3, "最后一步 from_row=3")
	assert_eq(last_move.to_col, 4, "最后一步 to_col=4")
	assert_eq(last_move.to_row, 4, "最后一步 to_row=4")

## TC-apply-003：apply_move 更新 side_to_move
func test_apply_move_updates_side_to_move() -> void:
	# arrange：起始局面 side_to_move = RED
	var state: BoardState = BoardState.initial()
	assert_eq(state.side_to_move, SD.RED, "起始局面应红方走")
	var piece: Piece = state.get_piece(4, 3)
	var move: Move = Move.new(4, 3, 4, 4, piece, null)
	# act
	var new_state: BoardState = GameController.apply_move(state, move)
	# assert
	assert_eq(new_state.side_to_move, SD.BLACK, "红方走完后应轮到黑方")

## TC-apply-004：apply_move 记录 capture
func test_apply_move_records_capture() -> void:
	# arrange：红车 4,4 吃黑兵 4,5
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.set_piece_internal(4, 4, Piece.new(PT.CHARIOT, SD.RED, 4, 4))
	state.set_piece_internal(4, 5, Piece.new(PT.PAWN, SD.BLACK, 4, 5))
	state.side_to_move = SD.RED
	var piece: Piece = state.get_piece(4, 4)
	var target: Piece = state.get_piece(4, 5)
	var move: Move = Move.new(4, 4, 4, 5, piece, target)
	# act
	var new_state: BoardState = GameController.apply_move(state, move)
	# assert：被吃子进入 captured_by_red 列表
	assert_eq(new_state.captured_by_red.size(), 1, "红方吃子列表应 +1")
	var captured: Piece = new_state.captured_by_red.back()
	assert_eq(captured.type, PT.PAWN, "被吃子应为兵")
	assert_eq(captured.side, SD.BLACK, "被吃子应为黑方")
	# move.captured 字段同步
	assert_not_null(move.captured, "move.captured 应被填充")
	if move.captured != null:
		assert_eq(move.captured.type, PT.PAWN, "move.captured.type 应为兵")

## TC-apply-005：apply_move 设置 is_check 标记
func test_apply_move_sets_is_check() -> void:
	# arrange：红车 4,4 走到 4,5将军黑将 4,9（同列无遮挡）
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.set_piece_internal(4, 4, Piece.new(PT.CHARIOT, SD.RED, 4, 4))
	state.side_to_move = SD.RED
	var piece: Piece = state.get_piece(4, 4)
	# 红车 4,4→4,5：移动后黑将 4,9 同列无遮挡 → 将军
	var move: Move = Move.new(4, 4, 4, 5, piece, null)
	# act
	var new_state: BoardState = GameController.apply_move(state, move)
	# assert
	assert_true(move.is_check, "走完后将军对方，move.is_check 应为 true")
	assert_eq(new_state.check_history.back(), true, "check_history 应记录 true")

# -------------------- generate_legal_moves --------------------

## TC-genlegal-001：generate_legal_moves 过滤非法走法（送将/照面）
func test_generate_legal_moves_excludes_illegal() -> void:
	# arrange：红帅 4,0；黑车 4,9（同列）；红车 4,4 阻挡；红方走子
	# 红车 4,4→3,4 离开 col 4 会暴露照面 → 应被过滤
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.set_piece_internal(4, 4, Piece.new(PT.CHARIOT, SD.RED, 4, 4))
	state.side_to_move = SD.RED
	# act
	var legal_moves: Array = GameController.generate_legal_moves(state, SD.RED)
	# assert：所有合法走法均不包含 4,4→3,4
	for m in legal_moves:
		var is_blocked_move: bool = (m.from_col == 4 and m.from_row == 4 and m.to_col == 3 and m.to_row == 4)
		assert_false(is_blocked_move, "红车 4,4→3,4 暴露照面，不应出现在合法走法中")
	# 至少有合法走法（红车 4,4→4,5 等挡车走法应保留）
	assert_true(legal_moves.size() > 0, "红方应有合法走法（保留挡车走法）")

# -------------------- check_game_over --------------------

## TC-gameover-001：将死局面 check_game_over 返回 over=true
func test_check_game_over_checkmate() -> void:
	# arrange：TC-A7-001 将死局面
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(4, 1, Piece.new(PT.CHARIOT, SD.BLACK, 4, 1))
	state.set_piece_internal(3, 0, Piece.new(PT.ADVISOR, SD.RED, 3, 0))
	state.set_piece_internal(5, 0, Piece.new(PT.ADVISOR, SD.RED, 5, 0))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.side_to_move = SD.RED
	# act
	var result: Dictionary = GameController.check_game_over(state)
	# assert
	assert_true(bool(result.get("over", false)), "将死局面 over 应为 true")
	# 红方被将死 → 黑方胜
	assert_eq(result.get("result", null), "black_win", "红方被将死应判 black_win")

## TC-gameover-002：困毙局面 check_game_over 返回 over=true, result=draw
func test_check_game_over_stalemate() -> void:
	# arrange：TC-A8-001 困毙局面
	var state: BoardState = BoardState.new()
	state.set_piece_internal(4, 0, Piece.new(PT.KING, SD.RED, 4, 0))
	state.set_piece_internal(3, 0, Piece.new(PT.ADVISOR, SD.RED, 3, 0))
	state.set_piece_internal(5, 0, Piece.new(PT.ADVISOR, SD.RED, 5, 0))
	state.set_piece_internal(2, 0, Piece.new(PT.ELEPHANT, SD.RED, 2, 0))
	state.set_piece_internal(6, 0, Piece.new(PT.ELEPHANT, SD.RED, 6, 0))
	state.set_piece_internal(3, 1, Piece.new(PT.PAWN, SD.BLACK, 3, 1))
	state.set_piece_internal(5, 1, Piece.new(PT.PAWN, SD.BLACK, 5, 1))
	state.set_piece_internal(4, 5, Piece.new(PT.CHARIOT, SD.BLACK, 4, 5))
	state.set_piece_internal(4, 9, Piece.new(PT.KING, SD.BLACK, 4, 9))
	state.side_to_move = SD.RED
	# act
	var result: Dictionary = GameController.check_game_over(state)
	# assert
	assert_true(bool(result.get("over", false)), "困毙局面 over 应为 true")
	assert_eq(result.get("result", null), "draw", "困毙应判 draw")

## TC-gameover-003：起始局面 check_game_over 返回 over=false
func test_check_game_over_not_over() -> void:
	# arrange
	var state: BoardState = BoardState.initial()
	# act
	var result: Dictionary = GameController.check_game_over(state)
	# assert
	assert_false(bool(result.get("over", false)), "起始局面 over 应为 false")
