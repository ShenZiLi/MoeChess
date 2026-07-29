## 棋盘视觉容器（Node2D）
## 关联：scripts/core/board_state.gd、scripts/view/piece_view.gd、scripts/view/board_perspective.gd、
##       scripts/view/fx_player.gd、scripts/theme/theme_manager.gd
##       docs/plans/2026-07-28-moechess-design.md §6.1 / §6.3 / §6.4
##       docs/development/acceptance-standard.md D1-D7 / E1-E3 / E8
##
## 职责：
##   - 加载 assets/board/ 两套透视背景图（PLACEHOLDER 模式可用纯色矩形兜底）
##   - 管理 90 格棋子视觉（Dictionary[Vector2i, PieceView]）
##   - setup(state) 初始化棋盘；flip_view() 翻转视角（D4/E8 列阵音效 + 背景切换 + 重算 + Tween 过渡）
##   - 接收点击事件并通过 BoardPerspective.screen_to_board 反查（D7 点击命中准确）
##   - 暴露 piece_clicked / cell_clicked 信号
##   - 皮肤切换时重载所有棋子贴图（C9）
class_name BoardView
extends Node2D

## 点击棋子（D7）
signal piece_clicked(piece: Piece)

## 点击空格子（D7）
signal cell_clicked(pos: Vector2i)

## 翻转序列开始（上层可借此触发额外 UI 反馈）
signal flip_started(flipped: bool)

## 翻转序列完成（棋子位置/缩放全部就位）
signal flip_finished(flipped: bool)

## 棋子 killed 动画完成（透传）
signal piece_killed_finished(piece: Piece)

## 棋子移动完成（透传）
signal piece_move_finished(piece: Piece)

## 玩家方透视背景图路径
const BOARD_PLAYER_PATH: String = "res://assets/board/board_player.png"

## 对手方透视背景图路径
const BOARD_OPPONENT_PATH: String = "res://assets/board/board_opponent.png"

## 翻转过渡 Tween 时长（秒，§6.3 约 0.4 秒）
const FLIP_DURATION: float = 0.4

## 当前棋盘状态
var board_state: BoardState = null

## 当前是否处于翻转视角
var flipped: bool = false

## 加速倍率
var _speed_mode: int = CoreConstants.SpeedMode.NORMAL

## 当前皮肤（用于切皮肤时重载贴图）
var _theme: ThemeResource = null

## 棋子视觉映射：Vector2i(col, row) -> PieceView
var _piece_views: Dictionary = {}

## 背景图节点（Sprite2D，本地坐标 (0,0) 对齐背景左上角）
var _bg_sprite: Sprite2D = null

## 可选 FxPlayer 引用（注入后 flip_view 会自动播放 formation_sfx，E8）
var fx_player: Node = null

## 当前在途的翻转 Tween
var _flip_tween: Tween = null

## 当前主题切换信号是否已连
var _theme_connected: bool = false

## 调试模式（不显示调试辅助层，但允许打印坐标到日志）
var _debug_verbose: bool = false

func _ready() -> void:
	_create_bg_sprite()
	# 默认加载玩家视角背景
	_set_bg_for_current_flip()
	# 监听皮肤切换（C9）：ThemeManager 是 autoload 节点，不是 Engine.singleton
	var tm: Node = _get_theme_manager()
	if tm != null:
		tm.theme_changed.connect(_on_theme_changed)
		_theme_connected = true
		_theme = tm.get_current()

## 创建背景 Sprite2D（占位图模式下贴图存在则加载，否则 fallback 纯色矩形）
func _create_bg_sprite() -> void:
	_bg_sprite = Sprite2D.new()
	_bg_sprite.name = "BoardBackground"
	_bg_sprite.centered = false  # 左上角对齐本地原点
	_bg_sprite.texture = _load_bg_texture(flipped)
	add_child(_bg_sprite)

## 根据 flipped 切换背景图
func _set_bg_for_current_flip() -> void:
	if _bg_sprite == null:
		return
	_bg_sprite.texture = _load_bg_texture(flipped)

## 加载背景纹理（PLACEHOLDER：用占位图；缺失则返回 null，由 _draw 兜底纯色）
func _load_bg_texture(p_flipped: bool) -> Texture2D:
	var path: String = BOARD_PLAYER_PATH if not p_flipped else BOARD_OPPONENT_PATH
	if ResourceLoader.exists(path, "Texture2D"):
		return load(path)
	return null

## 初始化棋盘：根据 BoardState 创建全部棋子视觉
func setup(state: BoardState) -> void:
	_clear_all_piece_views()
	board_state = state
	if state == null:
		return
	if _theme == null:
		var tm: Node = _get_theme_manager()
		if tm != null:
			_theme = tm.get_current()
	if _theme == null:
		push_warning("[BoardView] no theme available; PieceView will have empty SpriteFrames")
	for r in range(CoreConstants.ROWS):
		for c in range(CoreConstants.COLS):
			var p: Piece = state.grid[r][c]
			if p != null:
				_add_piece_view(p)

## 翻转视角（D4/E8：列阵音效 + 背景切换 + 重算 + Tween 过渡）
func flip_view() -> void:
	# 播放列阵音效（E8：双人对战换边触发 formation_sfx）
	if fx_player != null and fx_player.has_method("play_formation_sfx") and _theme != null:
		fx_player.call("play_formation_sfx", _theme)
	flip_started.emit(not flipped)
	# 切换背景
	flipped = not flipped
	_set_bg_for_current_flip()
	# 取消上一次未完成的翻转 Tween
	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	# 重算所有棋子位置/缩放，并用 Tween 过渡（贴图不旋转 D5）
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	for key in _piece_views.keys():
		var pv: PieceView = _piece_views[key]
		if pv == null or pv.piece == null:
			continue
		var target_pos: Vector2 = BoardPerspective.board_to_screen(Vector2i(pv.piece.col, pv.piece.row), flipped)
		var target_scale: float = BoardPerspective.scale_at_row(pv.piece.row, flipped)
		# 同时更新内部 flipped 标志，使后续动画用新视角
		pv.set_flipped(flipped)
		# Tween 覆盖位置 + 缩放（rotation 始终 0，D5）
		tween.tween_property(pv, "position", target_pos, FLIP_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_method(_set_piece_uniform_scale.bind(pv), pv.scale.x, target_scale, FLIP_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flip_tween = tween
	tween.chain().tween_callback(func(): flip_finished.emit(flipped))

## 设置加速倍率（影响所有动画 speed_scale；E3）
func set_speed_mode(mode: int) -> void:
	_speed_mode = mode
	for key in _piece_views.keys():
		var pv: PieceView = _piece_views[key]
		if pv != null:
			pv.set_speed_mode(mode)

## 设置当前主题（C9：皮肤切换后重载棋子贴图）
func set_theme(theme: ThemeResource) -> void:
	_on_theme_changed(theme)

## 播放走子动画（E1/E2：由 main_scene_controller._on_move_started 调用）
## 驱动 PieceView.move_to + 吃子 killed 动画，完成后发 piece_move_finished
func play_move(move: Move) -> void:
	if move == null:
		return
	var from_key: Vector2i = Vector2i(move.from_col, move.from_row)
	var to_key: Vector2i = Vector2i(move.to_col, move.to_row)
	var pv: PieceView = _piece_views.get(from_key, null)
	if pv == null:
		# 兜底：找不到棋子视图，直接通知完成
		piece_move_finished.emit(move.moved_piece)
		return
	# 处理吃子：被吃方播放 killed 动画
	if move.captured != null:
		var captured_pv: PieceView = _piece_views.get(to_key, null)
		if captured_pv != null:
			captured_pv.play_state(CoreConstants.AnimState.KILLED)
	# 同步字典键：从 from 移到 to
	_piece_views.erase(from_key)
	_piece_views[to_key] = pv
	# 驱动 PieceView 移动动画
	pv.move_to(move.to_col, move.to_row, true)

## 播放棋子状态动画（E1：选中动画，由 main_scene_controller._on_piece_selected 调用）
func play_piece_state(piece: Piece, anim_state: int) -> void:
	if piece == null:
		return
	var pv: PieceView = _piece_views.get(Vector2i(piece.col, piece.row), null)
	if pv != null:
		pv.play_state(anim_state)

## 获取当前棋子视觉
func get_piece_view(col: int, row: int) -> PieceView:
	return _piece_views.get(Vector2i(col, row), null)

## 获取所有棋子视觉（用于全队胜利/战败动画 E7）
func get_all_piece_views() -> Array:
	return _piece_views.values()

## 移除某个棋子视觉（被吃后调用）
func remove_piece_view(col: int, row: int) -> void:
	var key: Vector2i = Vector2i(col, row)
	var pv: PieceView = _piece_views.get(key, null)
	if pv == null:
		return
	_piece_views.erase(key)
	if is_instance_valid(pv):
		pv.queue_free()

## 添加一个棋子视图（如复盘或重置局面）
func add_piece_view(piece: Piece) -> PieceView:
	return _add_piece_view(piece)

## 处理点击事件（D7：点击命中准确）
## _unhandled_input 接收全屏未消费的点击，转成本地坐标后由 BoardPerspective 反查
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if board_state == null:
		return
	var local: Vector2 = _global_to_local(event.position)
	var board_pos: Vector2i = BoardPerspective.screen_to_board(local, flipped)
	if board_pos.x < 0 or board_pos.y < 0:
		# 点击在棋盘外
		return
	var p: Piece = board_state.get_piece(board_pos.x, board_pos.y)
	if p != null:
		piece_clicked.emit(p)
	else:
		cell_clicked.emit(board_pos)

## 设置调试 verbose（仅日志，不显示调试辅助层；I3 红线不受影响）
func set_debug_verbose(enabled: bool) -> void:
	_debug_verbose = enabled

# ---------- 内部辅助 ----------

## 全局屏幕坐标 → BoardView 本地坐标
func _global_to_local(global_pos: Vector2) -> Vector2:
	var gt: Transform2D = get_global_transform_with_canvas()
	return gt.affine_inverse() * global_pos

func _add_piece_view(piece: Piece) -> PieceView:
	if piece == null:
		return null
	var pv: PieceView = PieceView.new()
	pv.name = "Piece_%s_%d_%d" % [CoreConstants.TYPE_TO_KEY.get(piece.type, "p"), piece.col, piece.row]
	pv.set_speed_mode(_speed_mode)
	pv.set_flipped(flipped)
	add_child(pv)
	pv.set_piece(piece, _theme)
	pv.move_finished.connect(_on_piece_move_finished)
	pv.killed_finished.connect(_on_piece_killed_finished)
	_piece_views[Vector2i(piece.col, piece.row)] = pv
	return pv

func _clear_all_piece_views() -> void:
	for key in _piece_views.keys():
		var pv: PieceView = _piece_views[key]
		if is_instance_valid(pv):
			pv.queue_free()
	_piece_views.clear()

func _on_theme_changed(theme: ThemeResource) -> void:
	_theme = theme
	# 重载所有棋子贴图（C9）
	for key in _piece_views.keys():
		var pv: PieceView = _piece_views[key]
		if pv != null and pv.piece != null:
			pv.set_piece(pv.piece, _theme)

func _on_piece_move_finished(piece: Piece) -> void:
	# 同步 _piece_views 字典的键
	# 注意：调用方在 move_to 时已通过 BoardView.refresh_piece_position 同步
	piece_move_finished.emit(piece)

func _on_piece_killed_finished(piece: Piece) -> void:
	piece_killed_finished.emit(piece)

## 同步棋子视图字典的键（移动完成后调用）
func refresh_piece_position(from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	var from_key: Vector2i = Vector2i(from_col, from_row)
	var to_key: Vector2i = Vector2i(to_col, to_row)
	var pv: PieceView = _piece_views.get(from_key, null)
	if pv == null:
		return
	_piece_views.erase(from_key)
	# 若目标格已有视图（被吃方在 killed 动画完成前先占用），保留被吃方引用直到 killed_finished
	if _piece_views.has(to_key):
		# 通常这不应在此时发生（被吃方应已 queue_free），先覆盖
		_piece_views[to_key] = pv
	else:
		_piece_views[to_key] = pv

func _set_piece_uniform_scale(pv: PieceView, s: float) -> void:
	# 注意：bind(pv) 会把 pv 作为首参，tween_method 传入的 lerp 值作为后续参数
	# 故本函数签名是 (pv, s) 而非 (s, pv)
	if is_instance_valid(pv):
		pv.scale = Vector2(s, s)

func _get_theme_manager() -> Node:
	# 注意：get_node_or_null 是 Node 的方法，SceneTree 没有。
	# board_view 是 Node2D（在树中），直接用绝对路径查找 autoload。
	return get_node_or_null("/root/ThemeManager")

## 当背景纹理为 null 时（PLACEHOLDER 模式），用纯色矩形兜底显示
## 满足 D1：棋盘轻度倾斜 + 近大远小透视效果可见
func _draw() -> void:
	if _bg_sprite != null and _bg_sprite.texture != null:
		return  # 贴图已显示，不画兜底
	# 兜底：画一个梯形示意棋盘
	var near_color: Color = Color(0.86, 0.70, 0.47, 1.0)
	var far_color: Color = Color(0.66, 0.51, 0.31, 1.0)
	var cx: float = BoardPerspective.CENTER_X
	var near_y: float = BoardPerspective.NEAR_Y
	var far_y: float = BoardPerspective.FAR_Y
	var near_half: float = BoardPerspective.NEAR_HALF_WIDTH
	var far_half: float = BoardPerspective.FAR_HALF_WIDTH
	# 用 Polygon2D 风格的 draw_polygon 画底色梯形
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(cx - near_half, near_y),
		Vector2(cx + near_half, near_y),
		Vector2(cx + far_half, far_y),
		Vector2(cx - far_half, far_y),
	])
	var colors: PackedColorArray = PackedColorArray([near_color, near_color, far_color, far_color])
	draw_polygon(pts, colors)
	# 画网格线
	var line_color: Color = Color(0.23, 0.16, 0.08, 1.0)
	# 横线（11 条）
	for r in range(11):
		var t: float = float(r) / 10.0
		var y: float = lerpf(near_y, far_y, t)
		var half: float = lerpf(near_half, far_half, t)
		draw_line(Vector2(cx - half, y), Vector2(cx + half, y), line_color, 2.0)
	# 竖线（9 条）
	for c in range(9):
		var tt: float = float(c) / 8.0
		var xn: float = cx - near_half + 2.0 * near_half * tt
		var xf: float = cx - far_half + 2.0 * far_half * tt
		draw_line(Vector2(xn, near_y), Vector2(xf, far_y), line_color, 2.0)
