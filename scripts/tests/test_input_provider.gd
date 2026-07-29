## InputProvider 契约层测试 — 验收 H7（鼠标/触屏统一输出语义事件）
## 关联：docs/development/test-cases.md TC-H7-001 ~ TC-H7-003、acceptance-standard.md H7
## 关联实现：scripts/input/input_provider.gd
##
## 注意：本测试不依赖真节点（不进入场景树）；仅断言 InputProvider 类的契约（信号存在 + API 存在）
extends GutTest

# -------------------- TC-H7-001：InputProvider 信号存在 --------------------

## InputProvider 类应定义 piece_clicked / cell_clicked / ui_action / pause_requested 4 个信号
func test_input_provider_signals_exist() -> void:
	# arrange
	var provider: InputProvider = InputProvider.new()
	# act & assert：4 个信号在 InputProvider 类上存在
	# 通过 Signal 对象存在性检查
	var has_piece_clicked: bool = InputProvider.has_signal("piece_clicked")
	var has_cell_clicked: bool = InputProvider.has_signal("cell_clicked")
	var has_ui_action: bool = InputProvider.has_signal("ui_action")
	var has_pause_requested: bool = InputProvider.has_signal("pause_requested")
	assert_true(has_piece_clicked, "InputProvider 应定义 piece_clicked 信号")
	assert_true(has_cell_clicked, "InputProvider 应定义 cell_clicked 信号")
	assert_true(has_ui_action, "InputProvider 应定义 ui_action 信号")
	assert_true(has_pause_requested, "InputProvider 应定义 pause_requested 信号")
	# 清理
	provider.queue_free()

# -------------------- TC-H7-002：API 方法存在 --------------------

## InputProvider 应提供 set_board_view / set_board_state / set_flipped / set_enabled / emit_ui_action 方法
func test_input_provider_api_exists() -> void:
	# arrange
	var provider: InputProvider = InputProvider.new()
	# act & assert：方法存在性（通过 Object.has_method）
	assert_true(provider.has_method("set_board_view"), "应有 set_board_view 方法")
	assert_true(provider.has_method("set_board_state"), "应有 set_board_state 方法")
	assert_true(provider.has_method("set_flipped"), "应有 set_flipped 方法")
	assert_true(provider.has_method("set_enabled"), "应有 set_enabled 方法")
	assert_true(provider.has_method("emit_ui_action"), "应有 emit_ui_action 方法")
	assert_true(provider.has_method("emit_pause_requested"), "应有 emit_pause_requested 方法")
	assert_true(provider.has_method("is_enabled"), "应有 is_enabled 方法")
	# set_enabled / is_enabled 互逆
	provider.set_enabled(false)
	assert_false(provider.is_enabled(), "set_enabled(false) 后 is_enabled 应为 false")
	provider.set_enabled(true)
	assert_true(provider.is_enabled(), "set_enabled(true) 后 is_enabled 应为 true")
	# 清理
	provider.queue_free()

# -------------------- TC-H7-003：emit_ui_action 触发 ui_action 信号 --------------------

## emit_ui_action 应触发 ui_action 信号
func test_input_provider_emit_ui_action() -> void:
	# arrange
	var provider: InputProvider = InputProvider.new()
	var signal_received: bool = false
	var received_name: String = ""
	var callable: Callable = Callable(func(action_name: String):
		signal_received = true
		received_name = action_name
	)
	provider.ui_action.connect(callable)
	# act
	provider.emit_ui_action("test_action")
	# assert
	assert_true(signal_received, "emit_ui_action 应触发 ui_action 信号")
	assert_eq(received_name, "test_action", "信号参数应为 'test_action'")
	# 清理
	provider.ui_action.disconnect(callable)
	provider.queue_free()
