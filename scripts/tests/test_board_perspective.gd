## 棋盘透视单元测试 — 验收 D2（row 缩放 + Y 偏移）/ D6（board_to_screen / screen_to_board 互逆）
## 关联：docs/development/test-cases.md TC-D2-001 / TC-D6-002、acceptance-standard.md D2/D6
## 关联实现：scripts/view/board_perspective.gd
##
## 注意：D1/D3/D4/D5/D7（视觉验收）属于视觉范围，不在此 GUT 测试
extends GutTest

# -------------------- TC-D2-001：scale_at_row 缩放公式 --------------------

## scale_at_row：row 0 → 1.0；row 9 → 0.75；翻转后反之
func test_scale_at_row() -> void:
	# arrange & act
	var s_r0: float = BoardPerspective.scale_at_row(0, false)
	var s_r9: float = BoardPerspective.scale_at_row(9, false)
	var s_r0_flipped: float = BoardPerspective.scale_at_row(0, true)
	var s_r9_flipped: float = BoardPerspective.scale_at_row(9, true)
	# assert：未翻转时 row 0=1.0，row 9=0.75
	assert_almost_eq(s_r0, 1.0, 0.001, "未翻转 row 0 缩放应为 1.0")
	assert_almost_eq(s_r9, 0.75, 0.001, "未翻转 row 9 缩放应为 0.75")
	# 翻转后 row 0→0.75，row 9→1.0
	assert_almost_eq(s_r0_flipped, 0.75, 0.001, "翻转后 row 0 缩放应为 0.75")
	assert_almost_eq(s_r9_flipped, 1.0, 0.001, "翻转后 row 9 缩放应为 1.0")

# -------------------- TC-D6-001：board_to_screen / screen_to_board 互逆 --------------------

## board_to_screen → screen_to_board 应返回原坐标（90 格全部通过）
func test_board_to_screen_screen_to_board_inverse() -> void:
	# arrange & act & assert：90 格互逆
	for r in range(CoreConstants.ROWS):
		for c in range(CoreConstants.COLS):
			var pos: Vector2i = Vector2i(c, r)
			var screen: Vector2 = BoardPerspective.board_to_screen(pos, false)
			var restored: Vector2i = BoardPerspective.screen_to_board(screen, false)
			assert_eq(restored, pos, "未翻转：(c=%d,r=%d) 互逆应还原" % [c, r])
	# 翻转后同样应互逆
	for r in range(CoreConstants.ROWS):
		for c in range(CoreConstants.COLS):
			var pos: Vector2i = Vector2i(c, r)
			var screen: Vector2 = BoardPerspective.board_to_screen(pos, true)
			var restored: Vector2i = BoardPerspective.screen_to_board(screen, true)
			assert_eq(restored, pos, "翻转：(c=%d,r=%d) 互逆应还原" % [c, r])

# -------------------- TC-D6-002：翻转后 scale 反转 --------------------

## 翻转后 row 0 的 scale 应等于未翻转时 row 9 的 scale
func test_flipped_scale_reverse() -> void:
	# arrange & act
	var s_r0_normal: float = BoardPerspective.scale_at_row(0, false)
	var s_r0_flipped: float = BoardPerspective.scale_at_row(0, true)
	var s_r9_normal: float = BoardPerspective.scale_at_row(9, false)
	# assert：翻转后 row 0 = 未翻转 row 9
	assert_almost_eq(s_r0_flipped, s_r9_normal, 0.001, "翻转后 row 0 缩放应等于未翻转 row 9")
	# 翻转后 row 9 = 未翻转 row 0
	var s_r9_flipped: float = BoardPerspective.scale_at_row(9, true)
	assert_almost_eq(s_r9_flipped, s_r0_normal, 0.001, "翻转后 row 9 缩放应等于未翻转 row 0")
