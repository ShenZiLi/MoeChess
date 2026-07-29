## 存档与棋谱记录管理（autoload 单例，已在 project.godot 注册为 `SaveManager`）
## 关联：scripts/core/board_state.gd、scripts/core/move.gd、scripts/debug/play_replay.gd、
##       docs/development/acceptance-standard.md G2/G5、docs/plans/2026-07-28-moechess-design.md §7.3-7.4
##
## 职责：
## - 棋局结束时把完整走法 + 元信息写入 `user://records/{timestamp}.json`（G2）
## - 对局进行中自动存档到 `user://save.json`，含棋谱 + 当前设置（G5）
## - 用户偏好（皮肤/难度/音量/加速偏好）写入 `user://settings.json`
## - list_records() 列出所有历史棋谱（按时间倒序），供复盘入口选择
##
## 棋谱 JSON 格式（验收 G2）：
##   {
##     "meta": {
##       "timestamp": "2026-07-29T12:00:00",
##       "theme_id": "cats",
##       "mode": "PVE_HIGH",          # PVE_LOW / PVE_MEDIUM / PVE_HIGH / PVP
##       "difficulty": 2,              # CoreConstants.Difficulty 整数（PVP 时为 -1）
##       "result": "red_win",          # red_win / black_win / draw / null
##       "turns": 87                   # 半回合数（state.move_history.size()）
##     },
##     "initial_state": {...},         # BoardState.initial().to_dict()
##     "moves": [{from_col, from_row, to_col, to_row, piece, captured, is_check}, ...]
##   }
##
## 自动存档 JSON 格式（验收 G5）：
##   {
##     "state": {...},                 # 当前 BoardState.to_dict()（含 move_history）
##     "settings": {"theme_id":..., "difficulty":..., "volume":..., "speed_mode":..., "mode":...},
##     "timestamp": "..."
##   }
##
## 注意：不声明 class_name SaveManager——本脚本通过 project.godot 注册为
## autoload 单例 `SaveManager`，所有 SaveManager.xxx 调用走 autoload 名。
## 保留 class_name 会触发 "Class SaveManager hides an autoload singleton" 报错。
extends Node

## 棋谱存档目录（user:// 在 Godot 各平台映射到用户数据目录）
const RECORDS_DIR: String = "user://records"

## 棋谱文件扩展名
const RECORD_EXT: String = ".json"

## 自动存档路径（续局用）
const AUTO_SAVE_PATH: String = "user://save.json"

## 用户偏好设置路径
const SETTINGS_PATH: String = "user://settings.json"

## 模式字符串常量（写入 meta.mode）
const MODE_PVE_LOW: String = "PVE_LOW"
const MODE_PVE_MEDIUM: String = "PVE_MEDIUM"
const MODE_PVE_HIGH: String = "PVE_HIGH"
const MODE_PVP: String = "PVP"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(RECORDS_DIR)

## 把当前对局棋谱写入 `user://records/{timestamp}.json`（G2）
## state: 当前 BoardState（move_history 已含全部走法）
## meta: 元信息 Dictionary，至少包含 theme_id / mode / difficulty / result；
##       若缺 timestamp / turns 由本函数补齐
## 返回写入的文件绝对路径；写入失败返回空字符串
func save_record(state: BoardState, meta: Dictionary) -> String:
	var ts: String = Time.get_datetime_string_from_system(false, true)
	var safe_ts: String = ts.replace(":", "-").replace(" ", "T")
	var path: String = "%s/%s%s" % [RECORDS_DIR, safe_ts, RECORD_EXT]
	var full_meta: Dictionary = meta.duplicate(true)
	full_meta["timestamp"] = full_meta.get("timestamp", ts)
	full_meta["turns"] = full_meta.get("turns", state.move_history.size())
	var moves_arr: Array = []
	for m in state.move_history:
		moves_arr.append(m.to_dict())
	var data: Dictionary = {
		"meta": full_meta,
		"initial_state": BoardState.initial().to_dict(),
		"moves": moves_arr,
	}
	if _write_json(path, data):
		GameLogger.info("[SaveManager] record saved: %s (%d moves)" % [path, moves_arr.size()])
		return path
	GameLogger.error("[SaveManager] failed to save record: %s" % path)
	return ""

## 读取棋谱 JSON（返回空字典表示失败/不存在）
func load_record(path: String) -> Dictionary:
	return _read_json(path)

## 列出所有历史棋谱（按文件名降序，最新优先）
## 每项 {path: String, filename: String, timestamp: String, meta: Dictionary}
func list_records() -> Array:
	var dir: DirAccess = DirAccess.open(RECORDS_DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(RECORDS_DIR)
		return []
	var records: Array = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(RECORD_EXT):
			var full_path: String = "%s/%s" % [RECORDS_DIR, fname]
			var meta: Dictionary = _read_meta_only(full_path)
			records.append({
				"path": full_path,
				"filename": fname,
				"timestamp": String(meta.get("timestamp", fname.get_basename())),
				"meta": meta,
			})
		fname = dir.get_next()
	dir.list_dir_end()
	# 按文件名降序（timestamp 字典序与时间序一致，最新在前）
	records.sort_custom(func(a, b): return String(a["filename"]) > String(b["filename"]))
	return records

## 自动存档：写当前局面 + 设置到 user://save.json（G5）
func auto_save(state: BoardState, settings: Dictionary) -> void:
	var data: Dictionary = {
		"state": state.to_dict(),
		"settings": settings.duplicate(true),
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"has_save": true,
	}
	if _write_json(AUTO_SAVE_PATH, data):
		GameLogger.debug("[SaveManager] auto-save updated")
	else:
		GameLogger.warn("[SaveManager] auto-save failed")

## 读取自动存档（返回空字典表示无存档/损坏）
func load_auto_save() -> Dictionary:
	if not FileAccess.file_exists(AUTO_SAVE_PATH):
		return {}
	return _read_json(AUTO_SAVE_PATH)

## 删除自动存档（重开新对局时调用，避免续局提示）
func clear_auto_save() -> void:
	if FileAccess.file_exists(AUTO_SAVE_PATH):
		DirAccess.remove_absolute(AUTO_SAVE_PATH)

## 写用户偏好到 user://settings.json
func save_settings(settings: Dictionary) -> void:
	_write_json(SETTINGS_PATH, settings.duplicate(true))

## 读用户偏好（无文件返回空字典）
func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return {}
	return _read_json(SETTINGS_PATH)

## 仅读取棋谱 meta 字段（轻量，供 list_records 展示用）
func _read_meta_only(path: String) -> Dictionary:
	var d: Dictionary = _read_json(path)
	if d.is_empty():
		return {}
	return d.get("meta", {})

## 写 JSON 文件（pretty-print），成功返回 true
func _write_json(path: String, data: Variant) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		GameLogger.error("[SaveManager] cannot open for write: %s (err=%d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true

## 读 JSON 文件，解析失败返回空字典
func _read_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("[SaveManager] invalid JSON: %s" % path)
		return {}
	return parsed
