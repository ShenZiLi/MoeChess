## AI 强度/耗时基准脚本（验收 B7 / I5）
## 关联：docs/development/acceptance-standard.md B7/I5、docs/plans/2026-07-28-moechess-design.md §5、§10.2
##
## 在初始局面上让 AI 连续搜索 N 步，测量：
## - 每步耗时（毫秒）
## - 平均搜索节点数（若 SearchEngine 提供 nodes 计数）
## - 是否违规走法（与 GameController.generate_legal_moves 对比）
##
## 输出 JSON 报告：
##   {"difficulty": "high",
##    "moves": [{"step":1,"ms":320,"nodes":4500,"legal":true,"move":"(4,0)->(4,1)"}],
##    "avg_ms": ..., "max_ms": ..., "all_legal": true}
##
## 命令行运行：`godot --script scripts/debug/run_ai_benchmark.gd -- --difficulty high --steps 10`
##
## GUT 调用：
##   - 直接静态：`RunAiBenchmark.run(CoreConstants.Difficulty.HIGH, 10)`
##   - 注入方式（避免对未实现的 SearchEngine 硬依赖）：
##       var bench := RunAiBenchmark.new()
##       bench.set_search_engine(MockSearchEngine.new())
##       bench.set_game_controller(MockGameController)
##       var report := bench.run_impl(CoreConstants.Difficulty.HIGH, 10)
class_name RunAiBenchmark
extends RefCounted

# TODO: 实现完成后取消注释（依赖 scripts/ai/search_engine.gd，由其他 builder 并行实现）
# const SearchEngine = preload("res://scripts/ai/search_engine.gd")
# TODO: 实现完成后取消注释（依赖 scripts/core/game_controller.gd，由其他 builder 并行实现）
# const GameController = preload("res://scripts/core/game_controller.gd")

var _search_engine = null
var _game_controller = null

## 注入 SearchEngine 实现（避免硬依赖，供测试用）
## 期望接口：choose_move(state: BoardState, difficulty: int) -> Move
##         可选：get_last_nodes_count() -> int
func set_search_engine(engine) -> void:
	_search_engine = engine

## 注入 GameController 实现（类或实例均可）
## 期望接口：static apply_move(state: BoardState, move: Move) -> BoardState
##         static generate_legal_moves(state: BoardState, side: int) -> Array
func set_game_controller(controller) -> void:
	_game_controller = controller

## 静态入口：用默认（preload）的 SearchEngine/GameController 跑基准
## 注意：依赖未实现时，请改用实例 + set_search_engine + run_impl
static func run(difficulty: int, max_steps: int) -> Dictionary:
	var instance := RunAiBenchmark.new()
	# TODO: 实现完成后取消注释
	# if SearchEngine != null:
	# 	instance.set_search_engine(SearchEngine.new())
	# if GameController != null:
	# 	instance.set_game_controller(GameController)
	return instance.run_impl(difficulty, max_steps)

## 实例入口：用注入的 SearchEngine/GameController 跑基准
## difficulty: CoreConstants.Difficulty (LOW/MEDIUM/HIGH)
## max_steps: 让 AI 跑多少步
func run_impl(difficulty: int, max_steps: int) -> Dictionary:
	var moves: Array = []
	var total_ms: float = 0.0
	var max_ms: float = 0.0
	var all_legal: bool = true

	var state: BoardState = BoardState.initial()
	var difficulty_name: String = _difficulty_to_string(difficulty)

	for step_idx in range(1, max_steps + 1):
		if _search_engine == null:
			moves.append({
				"step": step_idx,
				"error": "SearchEngine not injected",
				"legal": false,
				"ms": 0,
				"nodes": 0,
			})
			all_legal = false
			break

		var start_time: float = Time.get_ticks_msec()
		var move = _search_engine.choose_move(state, difficulty)
		var elapsed_ms: float = Time.get_ticks_msec() - start_time

		var nodes: int = 0
		if _search_engine.has_method("get_last_search_nodes"):
			nodes = int(_search_engine.get_last_search_nodes())

		var legal: bool = _check_legal(state, move)

		moves.append({
			"step": step_idx,
			"ms": elapsed_ms,
			"nodes": nodes,
			"legal": legal,
			"move": _move_to_str(move),
		})
		total_ms += elapsed_ms
		max_ms = max(max_ms, elapsed_ms)
		if not legal:
			all_legal = false
			break

		# 应用走法，切换到下一步（让 AI 走双方）
		var next_state: BoardState = _apply_move(state, move)
		if next_state == null:
			moves.append({
				"step": step_idx,
				"error": "apply_move returned null",
				"legal": false,
			})
			all_legal = false
			break
		state = next_state

	var avg_ms: float = total_ms / max(1, moves.size())
	return {
		"difficulty": difficulty_name,
		"moves": moves,
		"avg_ms": avg_ms,
		"max_ms": max_ms,
		"all_legal": all_legal,
		"steps_run": moves.size(),
	}

## 走法合法性校验（依赖 GameController.generate_legal_moves）
func _check_legal(state: BoardState, move) -> bool:
	if move == null:
		return false
	if _game_controller != null and _game_controller.has_method("generate_legal_moves"):
		var legal_moves: Array = _game_controller.generate_legal_moves(state, state.side_to_move)
		for m in legal_moves:
			if m is Move and m.equals(move):
				return true
		return false
	# 没有 GameController 时，仅做基本非空校验（弱校验，待 GameController 实现后强化）
	return true

## 应用走法（依赖 GameController.apply_move）
func _apply_move(state: BoardState, move) -> BoardState:
	if _game_controller != null and _game_controller.has_method("apply_move"):
		return _game_controller.apply_move(state, move)
	# 没有 GameController 时无法继续
	return null

func _move_to_str(move) -> String:
	if move == null:
		return "null"
	return str(move)

func _difficulty_to_string(difficulty: int) -> String:
	match difficulty:
		CoreConstants.Difficulty.LOW:
			return "low"
		CoreConstants.Difficulty.MEDIUM:
			return "medium"
		CoreConstants.Difficulty.HIGH:
			return "high"
		_:
			return "unknown"

func _init() -> void:
	# 命令行运行检测
	var args: PackedStringArray = OS.get_cmdline_args()
	var is_main: bool = false
	for arg in args:
		if arg.ends_with("run_ai_benchmark.gd"):
			is_main = true
			break
	if is_main:
		var difficulty: int = _parse_difficulty_arg(args)
		var max_steps: int = _parse_int_arg(args, "--steps", 10)
		var report: Dictionary = run(difficulty, max_steps)
		print(JSON.stringify(report))
		var exit_code: int = 0 if bool(report.get("all_legal", false)) else 1
		if Engine.get_main_loop() != null:
			Engine.get_main_loop().quit(exit_code)

static func _parse_difficulty_arg(args: PackedStringArray) -> int:
	var idx: int = args.find("--difficulty")
	if idx >= 0 and idx + 1 < args.size():
		match args[idx + 1]:
			"low":
				return CoreConstants.Difficulty.LOW
			"medium":
				return CoreConstants.Difficulty.MEDIUM
			"high":
				return CoreConstants.Difficulty.HIGH
	return CoreConstants.Difficulty.HIGH

static func _parse_int_arg(args: PackedStringArray, key: String, default: int) -> int:
	var idx: int = args.find(key)
	if idx >= 0 and idx + 1 < args.size():
		return int(args[idx + 1])
	return default
