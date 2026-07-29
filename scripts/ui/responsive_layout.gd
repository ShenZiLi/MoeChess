## 响应式布局管理（H3 手机竖屏上下分布 / H4 桌面横屏左右侧栏）
## 关联：docs/development/acceptance-standard.md H3/H4、docs/plans/2026-07-28-moechess-design.md §9.1
##
## 用法：把 ResponsiveLayout 作为子节点加入场景，调用 apply_layout(container)。
## container 应为普通 Control（非 Container 节点），其下包含命名子节点：
##   竖屏模式：TopHUD / Board / BottomHUD（棋盘主体 + HUD 上下分布）
##   横屏模式：LeftSidebar / Board / RightSidebar（棋盘居中 + 左右侧栏）
## 缺失的子节点会被跳过，布局仍可应用。
## 监听 viewport.size_changed 与 container.resized 自动重新布局。
## 基准 1080×1920 + canvas_items + expand（H2，已在 project.godot 配置），
## 本类据此在任意窗口尺寸下重排。
class_name ResponsiveLayout
extends Control

## 布局模式切换信号（视觉层可订阅以重算棋盘透视/坐标转换）
signal layout_changed(is_portrait_mode: bool)

## 竖屏顶部 HUD 高度（设计像素，基准 1080×1920）
const TOP_HUD_HEIGHT: float = 180.0
## 竖屏底部操作条高度（设计像素）
const BOTTOM_HUD_HEIGHT: float = 220.0
## 横屏侧栏宽度（设计像素）
const SIDEBAR_WIDTH: float = 360.0
## 判定为宽屏的最小宽高比（width/height），低于此值横屏也回退上下布局（平板/Web 窄屏回退）
const WIDE_RATIO: float = 1.3

var _container: Control = null

func _ready() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.size_changed.connect(_on_resized)

## 当前是否为竖屏（高度 >= 宽度）
func is_portrait() -> bool:
	var s: Vector2 = _reference_size()
	return s.y >= s.x

## 当前是否为宽屏（横屏且宽度 >= 高度 * WIDE_RATIO）
func is_wide_screen() -> bool:
	var s: Vector2 = _reference_size()
	if s.x <= s.y:
		return false
	return s.x >= s.y * WIDE_RATIO

## 根据当前屏幕方向/尺寸应用布局到 container
func apply_layout(container: Control) -> void:
	_container = container
	if _container != null:
		if not _container.resized.is_connected(_on_resized):
			_container.resized.connect(_on_resized)
	_do_layout()

func _do_layout() -> void:
	if _container == null:
		return
	var size: Vector2 = _container.size
	if size.x <= 0.0 or size.y <= 0.0:
		size = _reference_size()
	# portrait = 非宽屏（竖屏 或 横屏但不够宽 → 回退上下布局）
	var portrait: bool = not (size.x > size.y and size.x >= size.y * WIDE_RATIO)
	if portrait:
		_apply_vertical_layout(size)
	else:
		_apply_horizontal_layout(size)
	layout_changed.emit(portrait)

func _apply_vertical_layout(size: Vector2) -> void:
	var top: Control = _child("TopHUD")
	var board: Control = _child("Board")
	var bottom: Control = _child("BottomHUD")
	var top_h: float = TOP_HUD_HEIGHT if top != null else 0.0
	var bot_h: float = BOTTOM_HUD_HEIGHT if bottom != null else 0.0
	if top != null:
		_place(top, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, top_h)
	if bottom != null:
		_place(bottom, 0.0, 1.0, 1.0, 1.0, 0.0, -bot_h, 0.0, 0.0)
	if board != null:
		var avail_w: float = size.x
		var avail_h: float = maxf(0.0, size.y - top_h - bot_h)
		var b: float = minf(avail_w, avail_h)
		var bx: float = (avail_w - b) * 0.5
		var by: float = top_h + (avail_h - b) * 0.5
		_place(board, 0.0, 0.0, 1.0, 1.0, bx, by, bx + b - size.x, by + b - size.y)

func _apply_horizontal_layout(size: Vector2) -> void:
	var left: Control = _child("LeftSidebar")
	var right: Control = _child("RightSidebar")
	var board: Control = _child("Board")
	var lw: float = SIDEBAR_WIDTH if left != null else 0.0
	var rw: float = SIDEBAR_WIDTH if right != null else 0.0
	if left != null:
		_place(left, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, lw, 0.0)
	if right != null:
		_place(right, 1.0, 0.0, 1.0, 1.0, -rw, 0.0, 0.0, 0.0)
	if board != null:
		var avail_w: float = maxf(0.0, size.x - lw - rw)
		var avail_h: float = size.y
		var b: float = minf(avail_w, avail_h)
		var bx: float = lw + (avail_w - b) * 0.5
		var by: float = (avail_h - b) * 0.5
		_place(board, 0.0, 0.0, 1.0, 1.0, bx, by, bx + b - size.x, by + b - size.y)

func _place(node: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	node.anchor_left = al
	node.anchor_top = at
	node.anchor_right = ar
	node.anchor_bottom = ab
	node.offset_left = ol
	node.offset_top = ot
	node.offset_right = orr
	node.offset_bottom = ob

func _child(node_name: String) -> Control:
	if _container == null:
		return null
	var n: Node = _container.get_node_or_null(node_name)
	if n is Control:
		return n
	return null

func _reference_size() -> Vector2:
	if _container != null and _container.size.x > 0.0 and _container.size.y > 0.0:
		return _container.size
	var vp: Viewport = get_viewport()
	if vp != null:
		var r: Vector2 = vp.get_visible_rect().size
		if r.x > 0.0 and r.y > 0.0:
			return r
	return DisplayServer.window_get_size()

func _on_resized() -> void:
	if _container != null:
		_do_layout()
