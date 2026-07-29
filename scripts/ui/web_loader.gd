## Web 端资源分批加载（H6）+ 浏览器暂停处理
## 关联：docs/development/acceptance-standard.md H6、docs/plans/2026-07-28-moechess-design.md §9.3
##
## 职责：
## - preload_critical()：优先加载关键资源（棋盘背景 + 当前皮肤 14 棋子 + theme.tres）
## - preload_background()：后台加载其余资源（其他皮肤 / 特效 / 全队动画）
## - 加载用 ResourceLoader.load_threaded_request；Web 平台禁用子线程（PlatformConfig.should_use_threads()=false），
##   按帧分批 poll（_poll_budget 限制每帧轮询数），避免首屏卡顿与 Web 无 Thread 限制冲突。
## - 浏览器 visibilitychange（标签隐藏）暂停轮询，可见后恢复：用 JavaScriptBridge 监听；
##   并以 MainLoop.NOTIFICATION_APPLICATION_PAUSED/RESUMED 作兜底（Godot Web 平台会把 visibilitychange 翻译为该通知）。
##
## PlatformConfig 契约（RefCounted，由 input 层实现）：is_web() / should_use_threads()。
## 本类通过 PlatformConfig.new() 实例化调用，未集成时回退 OS.has_feature，仅用于解耦集成顺序，不散落平台分支。
class_name WebLoader
extends Node

## 关键资源加载完成（可进入主菜单/对局）
signal critical_loaded()
## 后台资源全部加载完成
signal background_loaded()

const BOARD_ROOT: String = "res://assets/board"
const THEMES_ROOT: String = "res://assets/themes"
const VALID_EXTS: Array[String] = ["tres", "res", "tscn", "png", "tex", "wav", "ogg", "mp3"]

# 阶段：0=idle, 1=critical, 2=background, 3=done
var _phase: int = 0
# path -> 状态：0=loading, 1=done, 2=failed
var _pending: Dictionary = {}
var _critical_paths: Array[String] = []
var _background_paths: Array[String] = []
var _critical_done: bool = false
var _background_done: bool = false
var _browser_paused: bool = false

# JavaScriptBridge 句柄（仅 Web 非空）。用 Variant 持有，避免非 Web 平台静态引用类型导致解析失败。
var _jsb: Variant = null
var _js_callback: Variant = null

func _ready() -> void:
	_jsb = Engine.get_singleton("JavaScriptBridge")
	if _jsb != null:
		_setup_browser_visibility()

func _process(_delta: float) -> void:
	if _phase == 0 or _phase == 3:
		return
	if _browser_paused:
		return
	var budget: int = _poll_budget()
	var polled: int = 0
	var paths: Array = _pending.keys()
	for path in paths:
		if _pending[path] != 0:
			continue
		# Web 平台限制每帧轮询数（分帧加载，H6）；非 Web 由子线程加载，poll 仅查状态，可全量。
		if _is_web() and polled >= budget:
			continue
		var progress: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(String(path), progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var res: Resource = ResourceLoader.load_threaded_get(String(path))
				if res != null:
					_pending[path] = 1
				else:
					_pending[path] = 2
					if GameLogger != null:
						GameLogger.warn("[WebLoader] load returned null: %s" % path)
			ResourceLoader.THREAD_LOAD_FAILED:
				_pending[path] = 2
				if GameLogger != null:
					GameLogger.warn("[WebLoader] load failed (status): %s" % path)
			_:
				pass
		polled += 1
	_check_phase_complete()

func _check_phase_complete() -> void:
	if _phase == 1 and _all_settled(_critical_paths):
		_critical_done = true
		critical_loaded.emit()
		if GameLogger != null:
			GameLogger.info("[WebLoader] critical loaded")
		if not _background_paths.is_empty():
			_phase = 2
			_request_all(_background_paths)
		else:
			_phase = 3
			_background_done = true
			background_loaded.emit()
	elif _phase == 2 and _all_settled(_background_paths):
		_background_done = true
		_phase = 3
		background_loaded.emit()
		if GameLogger != null:
			GameLogger.info("[WebLoader] background loaded")

## 加载关键资源：棋盘背景 + 当前皮肤棋子 + theme.tres
func preload_critical() -> void:
	if _phase != 0:
		return
	_critical_paths = _collect_critical_paths()
	_phase = 1
	if _critical_paths.is_empty():
		_critical_done = true
		_phase = 3
		critical_loaded.emit()
		return
	_request_all(_critical_paths)

## 后台加载其余资源：其他皮肤 + 特效 + 全队动画
func preload_background() -> void:
	_background_paths = _collect_background_paths()
	if _phase == 0:
		# 未先调 preload_critical：视为关键阶段，关键路径为空，立即完成并进入后台阶段
		_phase = 1
	if _phase == 3:
		if not _background_paths.is_empty():
			_phase = 2
			_request_all(_background_paths)
		else:
			background_loaded.emit()
		return
	if _background_paths.is_empty() and _phase == 2:
		background_loaded.emit()
		_phase = 3
		_background_done = true

func _request_all(paths: Array[String]) -> void:
	for path in paths:
		if _pending.has(path):
			continue
		var err: int = ResourceLoader.load_threaded_request(path, "", _should_use_threads())
		if err == OK:
			_pending[path] = 0
		else:
			_pending[path] = 2
			if GameLogger != null:
				GameLogger.warn("[WebLoader] request error %d: %s" % [err, path])

func _all_settled(paths: Array[String]) -> bool:
	for path in paths:
		if _pending.get(path, 0) == 0:
			return false
	return true

func _collect_critical_paths() -> Array[String]:
	var out: Array[String] = []
	_collect_dir_resources(BOARD_ROOT, out, false)
	var theme_id: String = _current_theme_id()
	if theme_id != "":
		var theme_dir: String = "%s/%s" % [THEMES_ROOT, theme_id]
		out.append("%s/theme.tres" % theme_dir)
		_collect_dir_resources("%s/pieces" % theme_dir, out, false)
	return out

func _collect_background_paths() -> Array[String]:
	var out: Array[String] = []
	var current: String = _current_theme_id()
	var dir: DirAccess = DirAccess.open(THEMES_ROOT)
	if dir == null:
		return out
	dir.list_dir_begin()
	var subdir: String = dir.get_next()
	while subdir != "":
		if dir.dir_exists(subdir) and not subdir.begins_with("."):
			var full: String = "%s/%s" % [THEMES_ROOT, subdir]
			if subdir != current:
				_collect_dir_resources(full, out, true)
			else:
				_collect_dir_resources("%s/fx" % full, out, false)
				_collect_dir_resources("%s/anim" % full, out, false)
		subdir = dir.get_next()
	dir.list_dir_end()
	return out

func _collect_dir_resources(dir_path: String, out: Array[String], recursive: bool) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var item: String = dir.get_next()
	while item != "":
		if item.begins_with("."):
			item = dir.get_next()
			continue
		var full: String = "%s/%s" % [dir_path, item]
		if dir.dir_exists(item) and recursive:
			_collect_dir_resources(full, out, true)
		elif dir.file_exists(item):
			if item.get_extension().to_lower() in VALID_EXTS:
				out.append(full)
		item = dir.get_next()
	dir.list_dir_end()

func _current_theme_id() -> String:
	var tm: Object = get_node_or_null("/root/ThemeManager")
	if tm != null and tm.has_method("get_current"):
		var t: Object = tm.get_current()
		if t != null and "theme_id" in t:
			return String(t.theme_id)
	return ""

func _poll_budget() -> int:
	return 2 if _is_web() else 64

func _is_web() -> bool:
	var pc: Object = _platform_config()
	if pc != null and pc.has_method("is_web"):
		return pc.is_web()
	return OS.has_feature("web")

func _should_use_threads() -> bool:
	var pc: Object = _platform_config()
	if pc != null and pc.has_method("should_use_threads"):
		return pc.should_use_threads()
	return not OS.has_feature("web")

func _platform_config() -> Object:
	# PlatformConfig 是 RefCounted（非 autoload），通过 new() 实例化
	return PlatformConfig.new()

## 总体加载进度 0.0~1.0（关键 + 后台）
func get_progress() -> float:
	var total: int = _critical_paths.size() + _background_paths.size()
	if total == 0:
		return 1.0
	var done: int = 0
	for p in _critical_paths:
		if _pending.get(p, 0) != 0:
			done += 1
	for p in _background_paths:
		if _pending.get(p, 0) != 0:
			done += 1
	return float(done) / float(total)

## 关键资源是否就绪
func is_critical_ready() -> bool:
	return _critical_done

## 浏览器 visibilitychange 监听（仅 Web；_jsb 非空时安装）
func _setup_browser_visibility() -> void:
	_js_callback = _jsb.create_callback(Callable(self, "_on_visibility_change"))
	# 在 window 上挂一个对象，用其方法注册回调（get_interface 返回 window 属性对象，按属性名调用其方法）
	_jsb.eval(
		"(function(){window.__moechessBridge={registerVis:function(cb){window.__moechessVisCb=cb;if(!window.__moechessVisInstalled){window.__moechessVisInstalled=true;document.addEventListener('visibilitychange',function(){if(window.__moechessVisCb){try{window.__moechessVisCb(document.hidden);}catch(e){}}});}}};})();",
		true
	)
	var bridge: Variant = _jsb.get_interface("__moechessBridge")
	if bridge != null:
		bridge.registerVis(_js_callback)
	if GameLogger != null:
		GameLogger.info("[WebLoader] browser visibility listener installed")

## create_callback 的回调签名：单个 Array 参数（JS arguments 转数组）
func _on_visibility_change(args: Array) -> void:
	var hidden: bool = bool(args[0]) if args.size() > 0 else true
	_browser_paused = hidden
	if GameLogger != null:
		GameLogger.info("[WebLoader] browser visibility hidden=%s" % hidden)

func _notification(what: int) -> void:
	# 兜底：Godot Web 平台把 visibilitychange/blur 翻译为以下通知；非 Web 平台不触发
	match what:
		MainLoop.NOTIFICATION_APPLICATION_PAUSED:
			_browser_paused = true
		MainLoop.NOTIFICATION_APPLICATION_RESUMED:
			_browser_paused = false
