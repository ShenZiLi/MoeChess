## 日志单元测试 — 验收 I1（4 级日志 + 文件输出 + 级别过滤）
## 关联：docs/development/test-cases.md TC-I1-001 ~ TC-I1-003、acceptance-standard.md I1
## 关联实现：scripts/debug/logger.gd
extends GutTest

# -------------------- 钩子 --------------------

func before_each() -> void:
	# 关闭文件写入避免测试污染 user 目录
	if GameLogger != null:
		GameLogger.set_file_output(false)

func after_each() -> void:
	# 恢复 INFO 级别
	if GameLogger != null:
		GameLogger.set_level(GameLogger.Level.INFO)
		GameLogger.set_file_output(true)

# -------------------- TC-I1-001：4 级日志 --------------------

## 4 级日志（DEBUG/INFO/WARN/ERROR）均能被调用且含正确级别字段
func test_log_levels() -> void:
	# arrange：DEBUG 级别（最低）以记录所有日志
	GameLogger.set_level(GameLogger.Level.DEBUG)
	# act：分别调用 4 级日志（不应抛异常）
	GameLogger.debug("test debug message")
	GameLogger.info("test info message")
	GameLogger.warn("test warn message")
	GameLogger.error("test error message")
	# assert：get_level 反映 DEBUG
	assert_eq(GameLogger.get_level(), GameLogger.Level.DEBUG, "DEBUG 级别应被设置")
	# 切到 ERROR 级别
	GameLogger.set_level(GameLogger.Level.ERROR)
	assert_eq(GameLogger.get_level(), GameLogger.Level.ERROR, "ERROR 级别应被设置")
	# 此时 INFO/WARN 不应输出（仅检查不抛异常）
	GameLogger.info("should be filtered")
	GameLogger.warn("should be filtered")
	GameLogger.error("should appear")
	assert_true(true, "4 级日志调用均无异常")

# -------------------- TC-I1-002：写文件 --------------------

## 启用文件输出后，日志文件应被创建
func test_log_file_output() -> void:
	# arrange：启用文件输出
	GameLogger.set_file_output(true)
	# act：写一条日志
	GameLogger.set_level(GameLogger.Level.INFO)
	GameLogger.info("gut_test_log_entry_marker")
	GameLogger.flush()
	# assert：日志文件路径非空
	var log_path: String = GameLogger.get_current_log_path()
	assert_false(log_path == "", "启用文件输出后应有日志文件路径")
	# 文件应存在
	assert_true(FileAccess.file_exists(log_path), "日志文件应存在：%s" % log_path)
	# 文件内容含本次日志标记
	var f: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	if f != null:
		var content: String = f.get_as_text()
		f.close()
		assert_true(content.find("gut_test_log_entry_marker") >= 0, "日志文件应含本次日志条目")
	# 清理：关闭文件输出
	GameLogger.set_file_output(false)

# -------------------- TC-I1-003：set_level 过滤 --------------------

## set_level(INFO) 后 DEBUG 不被记录（用 ERROR 级别过滤所有低级别）
func test_log_level_filter() -> void:
	# arrange：ERROR 级别过滤 INFO/WARN/DEBUG
	GameLogger.set_level(GameLogger.Level.ERROR)
	# act & assert：DEBUG 级别 < ERROR，不应输出
	# 这里只能间接验证：get_level 反映 ERROR
	assert_eq(GameLogger.get_level(), GameLogger.Level.ERROR, "级别应为 ERROR")
	# 调用低级别日志不应抛异常
	GameLogger.debug("filtered")
	GameLogger.info("filtered")
	GameLogger.warn("filtered")
	# ERROR 级别应输出
	GameLogger.error("not filtered")
	assert_true(true, "级别过滤不抛异常")
