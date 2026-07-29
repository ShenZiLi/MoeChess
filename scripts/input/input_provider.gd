## 输入抽象层（Node，挂在场景树中接收 _input）
## 关联：docs/plans/2026-07-28-moechess-design.md §9.2、docs/development/acceptance-standard.md H7
##
## 职责（H7）：
## - 统一输出语义事件：piece_clicked / cell_clicked / ui_action / pause_requested
## - 桌面/Web：处理 InputEventMouseButton（左键点击）
## - 移动：处理 InputEventScreenTouch（单指触屏）
## - 桌面 ESC 键触发 pause_requested
## - 通过 BoardPerspective.screen_to_board 转换坐标（按契约调用 view 层的静态方法）
##
## 坐标转换：
## - 输入事件的 position 是视口坐标
## - 通过注入的 board_view（CanvasItem）将视口坐标转为棋盘本地坐标
## - 再调用 BoardPerspective.screen_to_board(local_pos, flipped) 得到棋盘逻辑坐标
## - 若未注入 board_view，假定事件 position 已是棋盘本地坐标（测试场景）
##
## 棋子/空格区分：
## - 通过注入的 BoardState 判断点击位置是否有棋子
## - 有棋子 → piece_clicked；无棋子 → cell_clicked
class_name InputProvider
extends Node

## 点击棋子（坐标为棋盘逻辑坐标 Vector2i(col, row)）
signal piece_clicked(pos: Vector2i)

## 点击格子（坐标为棋盘逻辑坐标 Vector2i(col, row)）
signal cell_clicked(pos: Vector2i)

## UI 动作（按钮等通过 emit_ui_action 触发）
signal ui_action(name: String)

## 暂停请求（ESC 键或移动端暂停按钮）
signal pause_requested()

## 棋盘视图节点（CanvasItem），用于视口坐标 → 棋盘本地坐标转换
## 由 view 层注入；为 null 时假定事件 position 已是本地坐标
var _board_view: CanvasItem = null

## 当前 BoardState（用于区分点击位置是棋子还是空格）
## 由控制器层注入；为 null 时所有点击均发 cell_clicked
var _board_state: BoardState = null

## 当前视角是否翻转（双人对战换边后）
## BoardPerspective.screen_to_board 需要此参数
var _flipped: bool = false

## 是否启用输入（Playing 状态外可禁用）
var _enabled: bool = true

## 触屏去重标记（避免一次触摸发多次）
var _touch_pressed: bool = false

## 注入棋盘视图节点（view 层调用）
## board_view 需是 CanvasItem 或其子类（如 Control/Sprite2D）
func set_board_view(board_view: CanvasItem) -> void:
	_board_view = board_view

## 注入当前 BoardState（控制器层调用，每次走子后更新）
func set_board_state(state: BoardState) -> void:
	_board_state = state

## 设置当前视角翻转状态（双人对战换边时由 view 层调用）
func set_flipped(flipped: bool) -> void:
	_flipped = flipped

## 启用/禁用输入
func set_enabled(enabled: bool) -> void:
	_enabled = enabled

## 是否启用
func is_enabled() -> bool:
	return _enabled

## UI 层主动触发 UI 动作（按钮点击等调用）
func emit_ui_action(action_name: String) -> void:
	ui_action.emit(action_name)  # 信号参数名为 name（按 H7 契约），此处发射值

## UI 层主动触发暂停请求（移动端暂停按钮等调用）
func emit_pause_requested() -> void:
	pause_requested.emit()

func _input(event: InputEvent) -> void:
	if not _enabled:
		return
	# ESC 键暂停（桌面）
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			pause_requested.emit()
		return
	# 鼠标点击（桌面/Web）
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_screen_press(mb.position)
		return
	# 触屏点击（移动）
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed and not _touch_pressed:
			_touch_pressed = true
			_handle_screen_press(st.position)
		elif not st.pressed:
			_touch_pressed = false
		return

## 处理屏幕坐标按下事件：视口坐标 → 棋盘逻辑坐标 → 区分棋子/空格 → 发信号
func _handle_screen_press(screen_pos: Vector2) -> void:
	var local_pos: Vector2 = _viewport_to_local(screen_pos)
	var board_pos: Vector2i = BoardPerspective.screen_to_board(local_pos, _flipped)
	# 越界（点击棋盘外）—— 哨兵 (-1, -1)，忽略
	if board_pos.x < 0 or board_pos.y < 0:
		return
	if not CoreConstants.in_bounds(board_pos.x, board_pos.y):
		return
	# 区分棋子/空格
	if _board_state != null:
		var piece: Piece = _board_state.get_piece_at(board_pos)
		if piece != null:
			piece_clicked.emit(board_pos)
			return
	cell_clicked.emit(board_pos)

## 视口坐标 → 棋盘视图本地坐标
## 若注入了 board_view 且在场景树中，用其 canvas 变换反推本地坐标；否则假定已是本地坐标
func _viewport_to_local(screen_pos: Vector2) -> Vector2:
	if _board_view == null or not _board_view.is_inside_tree():
		return screen_pos
	# get_global_transform_with_canvas() 返回 local→viewport 的变换
	# 其逆变换将 viewport 坐标转为 local 坐标
	var t: Transform2D = _board_view.get_global_transform_with_canvas()
	return t.affine_inverse() * screen_pos
