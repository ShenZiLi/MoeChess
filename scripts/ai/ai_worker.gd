## AI 后台计算 Worker（B6：WorkerThread + 思考中提示）
## 关联：docs/plans/2026-07-28-moechess-design.md §5.3、docs/development/acceptance-standard.md B6/H6
##
## 职责：
## - 将 SearchEngine.choose_move 放到 WorkerThread 执行，避免阻塞主线程
## - 计算完成后通过 compute_finished 信号通知（在主线程 emit）
## - Web 平台禁用 Thread（H6），改为同步计算（可能卡顿，但符合 Web 限制）
##
## cancel 语义：
## - 软取消——设置 _cancelled 标志，计算继续但结果被丢弃
## - Godot 4.x 不支持强制中断线程，SearchEngine 内部已通过时间限制保证 ≤2s 结束
class_name AIWorker
extends Node

## 计算完成信号（在主线程 emit，参数为选定的 Move，可能为 null 表示无合法走法）
signal compute_finished(move: Move)

var _search_engine: SearchEngine = SearchEngine.new()
var _thread: Thread = null
var _computing: bool = false
var _cancelled: bool = false
var _pending_move: Move = null
var _is_web: bool = false

func _init() -> void:
	# H6：Web 平台禁用 Thread，用 OS.has_feature 检测
	_is_web = OS.has_feature("web")

## 启动后台计算
## state: 当前棋盘状态（RefCounted，可跨线程传递）
## difficulty: CoreConstants.Difficulty.{LOW, MEDIUM, HIGH}
func start_compute(state: BoardState, difficulty: int) -> void:
	if _computing:
		GameLogger.warn("[AIWorker] Already computing, ignore start_compute")
		return
	_computing = true
	_cancelled = false
	_pending_move = null

	if _is_web:
		# H6：Web 平台禁用 Thread，同步计算（可能卡顿，但符合 Web 限制）
		# 用 call_deferred 确保 signal 在下一帧 emit，避免同步阻塞调用方
		var move: Move = _search_engine.choose_move(state, difficulty)
		_pending_move = move
		call_deferred("_emit_result")
	else:
		# 非 Web 平台用 WorkerThread
		_thread = Thread.new()
		var callable: Callable = Callable(self, "_compute_threaded").bind(state, difficulty)
		var err: int = _thread.start(callable)
		if err != OK:
			# 线程启动失败，降级为同步计算
			GameLogger.warn("[AIWorker] Thread.start failed (err=%d), fallback to sync" % err)
			_thread = null
			_pending_move = _search_engine.choose_move(state, difficulty)
			call_deferred("_emit_result")

## 线程入口：执行 SearchEngine.choose_move
## 注意：在线程内不能直接 emit 信号（Godot 信号非线程安全），需通过 call_deferred 切回主线程
func _compute_threaded(state: BoardState, difficulty: int) -> void:
	_pending_move = _search_engine.choose_move(state, difficulty)
	# 切回主线程处理结果
	call_deferred("_emit_result")

## 主线程回调：处理计算结果
func _emit_result() -> void:
	var move: Move = _pending_move
	_pending_move = null
	# 等待线程结束并释放资源
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_computing = false
	if not _cancelled:
		compute_finished.emit(move)

## 是否正在计算
func is_computing() -> bool:
	return _computing

## 取消计算（软取消——计算继续但结果被丢弃）
## 注意：Godot 4.x 不支持强制中断线程；SearchEngine 内部时间限制保证 ≤2s 结束
func cancel() -> void:
	_cancelled = true

## 注入置换表（透传给 SearchEngine）
func set_transposition_table(tt: TranspositionTable) -> void:
	_search_engine.set_transposition_table(tt)

## 透传测试钩子
func get_last_search_nodes() -> int:
	return _search_engine.get_last_search_nodes()

func get_last_search_ms() -> int:
	return _search_engine.get_last_search_ms()

func get_last_search_depth() -> int:
	return _search_engine.get_last_search_depth()
