## 统一日志 GameLogger（autoload 单例，已在 project.godot 注册为 `GameLogger`）
## 关联：docs/development/acceptance-standard.md I1、docs/plans/2026-07-28-moechess-design.md §10.2
##
## 提供 DEBUG / INFO / WARN / ERROR 四级日志，自动带时间戳与级别前缀。
## 日志同时输出到 stdout 与 `user://logs/moechess_{date}.log` 文件。
## 默认级别 INFO；可通过 `GameLogger.set_level(level)` 调整。
##
## 纯 GDScript 实现，不依赖 EditorPlugin，可在 GUT 测试中直接调用：
##   GameLogger.info("hello")
##   GameLogger.set_level(GameLogger.Level.DEBUG)
##
## 注意：autoload 名用 GameLogger 而非 Logger——Godot 4.x 有原生 Logger 类，
## 同名会触发 "Class Logger hides a native class" 报错。
## 不声明 class_name，通过 project.godot autoload 注册为全局单例。
extends Node

enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

const LEVEL_TAG: Dictionary = {
	Level.DEBUG: "DEBUG",
	Level.INFO: "INFO",
	Level.WARN: "WARN",
	Level.ERROR: "ERROR",
}

const DEFAULT_LOG_DIR: String = "user://logs"

var _level: int = Level.INFO
var _log_dir: String = DEFAULT_LOG_DIR
var _file: FileAccess = null
var _current_log_path: String = ""
var _file_output_enabled: bool = true

func _ready() -> void:
	if _file_output_enabled:
		_ensure_log_dir()
		_open_log_file()
	# 读取命令行参数 --log-level 覆盖默认级别
	var args: PackedStringArray = OS.get_cmdline_args()
	var idx: int = args.find("--log-level")
	if idx >= 0 and idx + 1 < args.size():
		_apply_level_string(args[idx + 1])

## 设置日志级别（低于此级别的日志不输出）
func set_level(level: int) -> void:
	_level = level

## 通过字符串设置级别（"DEBUG"/"INFO"/"WARN"/"ERROR"），便于命令行/配置传入
func set_level_by_name(name: String) -> void:
	_apply_level_string(name)

func _apply_level_string(name: String) -> void:
	match name.to_upper():
		"DEBUG":
			_level = Level.DEBUG
		"INFO":
			_level = Level.INFO
		"WARN":
			_level = Level.WARN
		"ERROR":
			_level = Level.ERROR

## 获取当前日志级别
func get_level() -> int:
	return _level

## 启用/关闭文件写入（测试场景可在测试开始时关闭以避免污染 user 目录）
func set_file_output(enabled: bool) -> void:
	_file_output_enabled = enabled
	if not enabled and _file != null:
		_file.close()
		_file = null
	elif enabled and _file == null:
		_ensure_log_dir()
		_open_log_file()

## 当前日志文件路径（用于测试断言）
func get_current_log_path() -> String:
	return _current_log_path

func debug(msg: Variant) -> void:
	_log(Level.DEBUG, msg)

func info(msg: Variant) -> void:
	_log(Level.INFO, msg)

func warn(msg: Variant) -> void:
	_log(Level.WARN, msg)

func error(msg: Variant) -> void:
	_log(Level.ERROR, msg)

## 显式刷新文件缓冲（测试用）
func flush() -> void:
	if _file != null:
		_file.flush()

func _log(level: int, msg: Variant) -> void:
	if level < _level:
		return
	var line: String = _format_line(level, msg)
	print(line)
	if _file != null:
		_file.store_line(line)

func _format_line(level: int, msg: Variant) -> String:
	var ts: String = Time.get_datetime_string_from_system(false, true)
	return "[%s][%s] %s" % [ts, LEVEL_TAG.get(level, "?"), str(msg)]

func _ensure_log_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_log_dir)

func _open_log_file() -> void:
	var date_str: String = Time.get_datetime_string_from_system(false, false).split(" ")[0]
	_current_log_path = "%s/moechess_%s.log" % [_log_dir, date_str]
	# 读写模式：追加；若不存在则创建
	_file = FileAccess.open(_current_log_path, FileAccess.READ_WRITE)
	if _file == null:
		_file = FileAccess.open(_current_log_path, FileAccess.WRITE_READ)
	if _file != null:
		_file.seek_end()
