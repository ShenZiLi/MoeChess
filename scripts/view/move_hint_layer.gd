## 可走位置提示层（Node2D）
## 关联：scripts/core/move.gd、scripts/view/board_perspective.gd、
##       docs/plans/2026-07-28-moechess-design.md §7.2
##       docs/development/acceptance-standard.md F4
##
## 职责：
##   - 在选中棋子时显示该棋子的合法走法目标格（半透明圆形/星形）
##   - 这是"短暂反馈"（非常驻几何圈），不是调试辅助层；正常运行时正常显示
##     （AGENTS.md：合法的"短暂反馈"非调试辅助层）
##   - 提示层会随视角翻转重算位置（D6）
class_name MoveHintLayer
extends Node2D

## 提示圆形基础半径（会按 row 透视缩放）
const HINT_RADIUS: float = 36.0

## 提示颜色（柔和半透明）
const HINT_COLOR: Color = Color(0.4, 0.85, 1.0, 0.55)

## 提示边缘描边色
const HINT_EDGE_COLOR: Color = Color(0.8, 0.95, 1.0, 0.9)

## 脉动动画周期（秒）
const PULSE_PERIOD: float = 1.2

## 当前是否处于翻转视角（D6：翻转后位置重算）
var _flipped: bool = false

## 当前显示的走法列表（用于 set_flipped 重绘）
var _current_moves: Array = []

## 当前活跃的提示节点（Array[Sprite2D 风格的 Node2D]）
var _hint_nodes: Array = []

func _ready() -> void:
	# 默认隐藏（无 hints 时不渲染）
	visible = false

## 显示可走位置（F4）
## moves: Array[Move]，每个 Move 用 to_col / to_row 作为目标格
func show_hints(moves: Array) -> void:
	clear_hints()
	_current_moves = moves.duplicate(false)
	if moves.is_empty():
		visible = false
		return
	visible = true
	for m in moves:
		if m == null:
			continue
		var pos: Vector2i = Vector2i(m.to_col, m.to_row)
		var screen_pos: Vector2 = BoardPerspective.board_to_screen(pos, _flipped)
		var s: float = BoardPerspective.scale_at_row(m.to_row, _flipped)
		var hint: Node2D = _create_hint_node(screen_pos, s)
		add_child(hint)
		_hint_nodes.append(hint)

## 清除所有提示
func clear_hints() -> void:
	for n in _hint_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_hint_nodes.clear()
	_current_moves.clear()
	visible = false

## 设置当前视角（翻转后重算所有 hint 位置，D6）
func set_flipped(p_flipped: bool) -> void:
	_flipped = p_flipped
	if _current_moves.is_empty():
		return
	# 重新摆位已有 hints
	var idx: int = 0
	for m in _current_moves:
		if m == null or idx >= _hint_nodes.size():
			continue
		var node: Node2D = _hint_nodes[idx]
		idx += 1
		if not is_instance_valid(node):
			continue
		var pos: Vector2i = Vector2i(m.to_col, m.to_row)
		var sp: Vector2 = BoardPerspective.board_to_screen(pos, _flipped)
		var sc: float = BoardPerspective.scale_at_row(m.to_row, _flipped)
		node.position = sp
		node.scale = Vector2(sc, sc)

## 创建单个提示节点：半透明圆形 + 轻微脉动
func _create_hint_node(at_pos: Vector2, scale_factor: float) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = "MoveHint"
	node.position = at_pos
	node.scale = Vector2(scale_factor, scale_factor)
	# 自绘圆形
	var drawer: HintDrawer = HintDrawer.new()
	drawer.radius = HINT_RADIUS
	drawer.color = HINT_COLOR
	drawer.edge_color = HINT_EDGE_COLOR
	node.add_child(drawer)
	# 脉动 Tween
	var tween: Tween = create_tween()
	tween.set_loops()
	tween.tween_property(drawer, "scale", Vector2(1.15, 1.15), PULSE_PERIOD * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(drawer, "scale", Vector2(1.0, 1.0), PULSE_PERIOD * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return node


## 内部自绘提示圆形节点
class HintDrawer:
	extends Node2D
	var radius: float = 36.0
	var color: Color = Color(1.0, 1.0, 1.0, 0.5)
	var edge_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)
		# 描边
		var prev_w: float = 2.0
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, edge_color, prev_w)
