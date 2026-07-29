## 存档管理单元/集成测试 — 验收 G2（棋谱存档）/ G5（自动存档）
## 关联：docs/development/test-cases.md TC-G2-001 / TC-G5-001、acceptance-standard.md G2/G5
## 关联实现：scripts/core/save_manager.gd
##
## SaveManager 是 autoload 单例，GUT 运行时已 _ready（已创建 user://records 目录）
extends GutTest

const PT = CoreConstants.PieceType
const SD = CoreConstants.Side

# -------------------- 钩子 --------------------

func before_each() -> void:
	if GameLogger != null:
		GameLogger.set_file_output(false)

func after_each() -> void:
	if GameLogger != null:
		GameLogger.set_file_output(true)

# -------------------- TC-G2-001：save_record 写入棋谱 JSON --------------------

## save_record 写入棋谱 JSON 到 user://records/{timestamp}.json，返回非空路径
func test_save_record() -> void:
	# arrange：起始局面 + 一手走法
	var state: BoardState = BoardState.initial()
	var piece: Piece = state.get_piece(4, 3)
	var move: Move = Move.new(4, 3, 4, 4, piece, null)
	var new_state: BoardState = GameController.apply_move(state, move)
	var meta: Dictionary = {
		"theme_id": "cats",
		"mode": SaveManager.MODE_PVE_HIGH,
		"difficulty": CoreConstants.Difficulty.HIGH,
		"result": "red_win",
	}
	# act
	var path: String = SaveManager.save_record(new_state, meta)
	# assert：返回非空路径
	assert_false(path == "", "save_record 应返回非空路径")
	# 文件存在
	assert_true(FileAccess.file_exists(path), "棋谱文件应存在：%s" % path)
	# JSON 可解析
	var data: Dictionary = SaveManager.load_record(path)
	assert_false(data.is_empty(), "棋谱 JSON 应可解析")
	# 含 meta / moves / initial_state 字段
	assert_true(data.has("meta"), "棋谱应含 meta 字段")
	assert_true(data.has("moves"), "棋谱应含 moves 字段")
	assert_true(data.has("initial_state"), "棋谱应含 initial_state 字段")
	# moves 数组长度 = 1（仅一手）
	var moves: Array = data.get("moves", [])
	assert_eq(moves.size(), 1, "棋谱应含 1 步走法")
	# meta 含 theme_id / mode / difficulty / result
	var meta_loaded: Dictionary = data.get("meta", {})
	assert_eq(String(meta_loaded.get("theme_id", "")), "cats", "meta.theme_id 应为 cats")
	assert_eq(String(meta_loaded.get("mode", "")), SaveManager.MODE_PVE_HIGH, "meta.mode 应为 PVE_HIGH")

# -------------------- TC-G2-002：load_record 读取棋谱 --------------------

## load_record 读取已保存的棋谱 JSON
func test_load_record() -> void:
	# arrange：先保存一份
	var state: BoardState = BoardState.initial()
	var meta: Dictionary = {"theme_id": "cats", "mode": SaveManager.MODE_PVP, "result": "draw"}
	var path: String = SaveManager.save_record(state, meta)
	assert_false(path == "", "前置：save_record 应成功")
	# act
	var data: Dictionary = SaveManager.load_record(path)
	# assert
	assert_false(data.is_empty(), "load_record 应返回非空字典")
	assert_true(data.has("meta"), "数据应含 meta")
	assert_true(data.has("moves"), "数据应含 moves")

# -------------------- TC-G5-001：auto_save / load_auto_save --------------------

## auto_save 写入 user://save.json；load_auto_save 读取并恢复
func test_auto_save_load() -> void:
	# arrange
	var state: BoardState = BoardState.initial()
	var settings: Dictionary = {
		"theme_id": "cats",
		"difficulty": CoreConstants.Difficulty.HIGH,
		"speed_mode": CoreConstants.SpeedMode.NORMAL,
		"mode": SaveManager.MODE_PVE_HIGH,
	}
	# act
	SaveManager.auto_save(state, settings)
	var loaded: Dictionary = SaveManager.load_auto_save()
	# assert
	assert_false(loaded.is_empty(), "load_auto_save 应返回非空字典")
	# 含 state / settings / timestamp 字段
	assert_true(loaded.has("state"), "自动存档应含 state 字段")
	assert_true(loaded.has("settings"), "自动存档应含 settings 字段")
	assert_true(loaded.has("timestamp"), "自动存档应含 timestamp 字段")
	# settings 字段还原
	var loaded_settings: Dictionary = loaded.get("settings", {})
	assert_eq(String(loaded_settings.get("theme_id", "")), "cats", "settings.theme_id 应还原")
	assert_eq(String(loaded_settings.get("mode", "")), SaveManager.MODE_PVE_HIGH, "settings.mode 应还原")
	# state 可还原为 BoardState
	var state_dict: Dictionary = loaded.get("state", {})
	assert_false(state_dict.is_empty(), "state 字典应非空")
	var restored: BoardState = BoardState.from_dict(state_dict)
	assert_not_null(restored, "BoardState.from_dict 应返回非空对象")

# -------------------- TC-G2-003：list_records 列出历史棋谱 --------------------

## list_records 返回至少 1 条记录（前面测试已保存）
func test_list_records() -> void:
	# arrange：先保存一份确保有数据
	var state: BoardState = BoardState.initial()
	var meta: Dictionary = {"theme_id": "cats", "mode": SaveManager.MODE_PVP, "result": "draw"}
	SaveManager.save_record(state, meta)
	# act
	var records: Array = SaveManager.list_records()
	# assert
	assert_true(records.size() >= 1, "list_records 应返回至少 1 条记录，实际 %d" % records.size())
	# 每条记录含 path / filename / timestamp / meta 字段
	if not records.is_empty():
		var first: Dictionary = records[0]
		assert_true(first.has("path"), "记录应含 path 字段")
		assert_true(first.has("filename"), "记录应含 filename 字段")
		assert_true(first.has("timestamp"), "记录应含 timestamp 字段")
		assert_true(first.has("meta"), "记录应含 meta 字段")
