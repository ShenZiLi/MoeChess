## 棋谱回放脚本（验收 G3 / I5）
## 关联：docs/development/acceptance-standard.md G3/I5、docs/plans/2026-07-28-moechess-design.md §7.3、§10.2
##
## 加载 `user://records/{timestamp}.json` 棋谱存档，支持前进/后退一步。
## 棋谱格式（来自 BoardState.to_dict + 元信息）：
##   {
##     "meta": {"theme": "cats", "difficulty": "high", "result": "red_win", "timestamp": "..."},
##     "moves": [{"from_col":..,"from_row":..,"to_col":..,"to_row":..,"piece":{..},"captured":{..}|null}, ...],
##     "initial_state": {"pieces":[...],"side_to_move":0,"turn_number":1}
##   }
##
## 命令行运行：`godot --script scripts/debug/play_replay.gd -- --replay user://records/xxx.json`
##
## GUT 调用：
##   var state := PlayReplay.load_replay("user://records/xxx.json")
##   state = PlayReplay.step(state, true)   # 前进一步
##   state = PlayReplay.step(state, false)  # 后退一步
class_name PlayReplay
extends RefCounted

## 加载棋谱
## 返回 {ok, moves: Array[Move], meta: Dictionary, initial_state: Dictionary, current_step: int, total: int}
static func load_replay(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {
			"ok": false,
			"error": "cannot open file: %s (err=%d)" % [path, FileAccess.get_open_error()],
			"moves": [],
			"meta": {},
			"initial_state": {},
			"current_step": 0,
			"total": 0,
			"path": path,
		}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "invalid JSON: %s" % path,
			"moves": [],
			"meta": {},
			"initial_state": {},
			"current_step": 0,
			"total": 0,
			"path": path,
		}
	var d: Dictionary = parsed
	var moves_raw: Array = d.get("moves", [])
	var moves: Array = []
	for md in moves_raw:
		if typeof(md) == TYPE_DICTIONARY:
			moves.append(Move.from_dict(md))
	return {
		"ok": true,
		"moves": moves,
		"meta": d.get("meta", {}),
		"initial_state": d.get("initial_state", {}),
		"current_step": 0,
		"total": moves.size(),
		"path": path,
	}

## 前进/后退一步
## replay_state: load_replay 返回的字典（会被原地修改 current_step）
## forward: true=前进一步，false=后退一步
## 返回更新后的 replay_state（同引用）
static func step(replay_state: Dictionary, forward: bool) -> Dictionary:
	if not bool(replay_state.get("ok", false)):
		return replay_state
	var total: int = int(replay_state.get("total", 0))
	var cur: int = int(replay_state.get("current_step", 0))
	if forward:
		cur = min(cur + 1, total)
	else:
		cur = max(cur - 1, 0)
	replay_state["current_step"] = cur
	_log_current_move(replay_state)
	return replay_state

## 跳到指定步（0..total）
static func seek_to(replay_state: Dictionary, step_idx: int) -> Dictionary:
	if not bool(replay_state.get("ok", false)):
		return replay_state
	var total: int = int(replay_state.get("total", 0))
	var cur: int = clamp(step_idx, 0, total)
	replay_state["current_step"] = cur
	_log_current_move(replay_state)
	return replay_state

## 获取当前步的 Move（或 null）
static func get_current_move(replay_state: Dictionary) -> Move:
	var cur: int = int(replay_state.get("current_step", 0))
	var moves: Array = replay_state.get("moves", [])
	if cur <= 0 or cur > moves.size():
		return null
	return moves[cur - 1]

## 输出当前步走法日志（stdout，便于命令行观测）
static func _log_current_move(replay_state: Dictionary) -> void:
	var cur: int = int(replay_state.get("current_step", 0))
	var total: int = int(replay_state.get("total", 0))
	var mv: Move = get_current_move(replay_state)
	if mv == null:
		print("[Replay] step %d/%d (no move)" % [cur, total])
		return
	var meta: Dictionary = replay_state.get("meta", {})
	var theme_id: String = String(meta.get("theme", "?"))
	var difficulty: String = String(meta.get("difficulty", "?"))
	print("[Replay] step %d/%d theme=%s difficulty=%s move=%s" % [cur, total, theme_id, difficulty, str(mv)])

func _init() -> void:
	# 命令行运行检测
	var args: PackedStringArray = OS.get_cmdline_args()
	var is_main: bool = false
	for arg in args:
		if arg.ends_with("play_replay.gd"):
			is_main = true
			break
	if is_main:
		_run_cli(args)

## 命令行入口：加载棋谱并前进一步，输出当前步信息
func _run_cli(args: PackedStringArray) -> void:
	var replay_path: String = _parse_str_arg(args, "--replay", "")
	if replay_path == "":
		print(JSON.stringify({"ok": false, "error": "missing --replay <path>"}))
		_quit(1)
		return
	var state: Dictionary = load_replay(replay_path)
	if not bool(state.get("ok", false)):
		print(JSON.stringify(state))
		_quit(1)
		return
	# 默认前进一步，打印首步
	state = step(state, true)
	var mv: Move = get_current_move(state)
	print(JSON.stringify({
		"ok": true,
		"meta": state.get("meta", {}),
		"current_step": state.get("current_step", 0),
		"total": state.get("total", 0),
		"current_move": _move_to_dict(mv),
	}))
	_quit(0)

static func _quit(code: int) -> void:
	if Engine.get_main_loop() != null:
		Engine.get_main_loop().quit(code)

static func _parse_str_arg(args: PackedStringArray, key: String, default: String) -> String:
	var idx: int = args.find(key)
	if idx >= 0 and idx + 1 < args.size():
		return args[idx + 1]
	return default

static func _move_to_dict(mv: Move) -> Dictionary:
	if mv == null:
		return {}
	return mv.to_dict()
