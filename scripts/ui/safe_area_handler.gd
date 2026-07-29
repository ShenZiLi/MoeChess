## 移动端安全区适配 + 切后台自动暂停（H5）
## 关联：docs/development/acceptance-standard.md H5、docs/plans/2026-07-28-moechess-design.md §9.3
##
## 用法：把 SafeAreaHandler 加入场景，对需要避让安全区的全屏 Control 调用 apply_safe_area(node)。
## node 应为锚点铺满父级（0,0,1,1）的 Control；本类将其内缩到 DisplayServer.get_window_safe_area() 内。
## 桌面端安全区 = 整个窗口，内缩为 0，等同无操作；移动端规避刘海/圆角/手势条。
## 切后台/失焦：监听 MainLoop.NOTIFICATION_APPLICATION_PAUSED 自动 get_tree().paused = true，
##   NOTIFICATION_APPLICATION_RESUMED 还原（仅还原由本类触发的暂停，避免覆盖用户主动暂停）。
## Android 系统返回键：NOTIFICATION_WM_GO_BACK_REQUEST 通过 back_requested 信号通知，
##   由状态机决定行为（如打开暂停面板），本类不直接退出应用。
class_name SafeAreaHandler
extends Control

## Android 系统返回键信号（状态机订阅以打开暂停面板/返回上级菜单）
signal back_requested()

## 自动暂停态变化信号（true=因切后台而暂停，false=已恢复）
signal auto_pause_changed(paused: bool)

var _tracked: Array[Control] = []
var _auto_paused: bool = false
# NOTIFICATION_WM_GO_BACK_REQUEST 在 Godot 4 各版本中归属 MainLoop/Node 存在差异，
# 运行时通过 ClassDB 解析，避免静态引用错误类前缀导致解析失败；APPLICATION_PAUSED/RESUMED 在 MainLoop 稳定。
var _back_request_const: int = -1

func _ready() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.size_changed.connect(_reapply_all)
	_back_request_const = _resolve_const(&"NOTIFICATION_WM_GO_BACK_REQUEST")

func _resolve_const(const_name: StringName) -> int:
	for cls in ["MainLoop", "Node"]:
		if ClassDB.class_has_integer_constant(StringName(cls), const_name):
			return ClassDB.class_get_integer_constant(StringName(cls), const_name)
	return -1

## 对 node 应用安全区内缩；node 会被持续跟踪，窗口/安全区变化时自动重算
func apply_safe_area(node: Control) -> void:
	if node == null:
		return
	if not _tracked.has(node):
		_tracked.append(node)
	_apply_to(node)

func _apply_to(node: Control) -> void:
	var safe: Rect2i = DisplayServer.get_window_safe_area()
	var win: Vector2i = DisplayServer.window_get_size()
	# 锚点铺满父级
	node.anchor_left = 0.0
	node.anchor_top = 0.0
	node.anchor_right = 1.0
	node.anchor_bottom = 1.0
	# 内缩 = 安全区相对窗口的边距（offset 在父级坐标系下）
	node.offset_left = float(safe.position.x)
	node.offset_top = float(safe.position.y)
	node.offset_right = -float(maxi(0, win.x - safe.end.x))
	node.offset_bottom = -float(maxi(0, win.y - safe.end.y))

func _reapply_all() -> void:
	for n in _tracked:
		if is_instance_valid(n):
			_apply_to(n)

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_PAUSED:
		_auto_pause()
	elif what == MainLoop.NOTIFICATION_APPLICATION_RESUMED:
		_auto_resume()
	elif _back_request_const != -1 and what == _back_request_const:
		back_requested.emit()

func _auto_pause() -> void:
	if _auto_paused:
		return
	_auto_paused = true
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = true
	if GameLogger != null:
		GameLogger.info("[SafeAreaHandler] application paused (background) -> tree.paused=true")
	auto_pause_changed.emit(true)

func _auto_resume() -> void:
	if not _auto_paused:
		return
	_auto_paused = false
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	if GameLogger != null:
		GameLogger.info("[SafeAreaHandler] application resumed -> tree.paused=false")
	auto_pause_changed.emit(false)

## 查询当前是否因切后台而处于自动暂停态（供状态机区分用户暂停与后台暂停）
func is_auto_paused() -> bool:
	return _auto_paused
