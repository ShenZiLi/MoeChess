## 复盘控制器集成测试 — 验收 G3（前进/后退/自动播放）/ G4（重放动画+音效）
## 关联：docs/development/test-cases.md TC-G3-001 / TC-G3-002、acceptance-standard.md G3/G4
## 关联实现：scripts/core/replay_controller.gd、scripts/core/save_manager.gd
##
## ReplayController 是 RefCounted，无节点依赖；通过 SaveManager 保存的棋谱加载
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

# -------------------- 工具：构造测试棋谱 --------------------

## 构造一个含 N 步走法的棋谱，返回保存路径
func _build_record_path(step_count: int) -> String:
	var state: BoardState = BoardState.initial()
	# 走 step_count 步红黑交替的简单走法
	var temp_state: BoardState = state
	for i in range(step_count):
		var legal_moves: Array = GameController.generate_legal_moves(temp_state, temp_state.side_to_move)
		if legal_moves.is_empty():
			break
		# 选第一个合法走法
		var move: Move = legal_moves[0]
		temp_state = GameController.apply_move(temp_state, move)
	var meta: Dictionary = {
		"theme_id": "cats",
		"mode": SaveManager.MODE_PVE_LOW,
		"difficulty": CoreConstants.Difficulty.LOW,
		"result": null,
	}
	return SaveManager.save_record(temp_state, meta)

# -------------------- TC-G3-001：step_forward 前进 --------------------

## step_forward 前进一步，current_step +1
func test_replay_step_forward() -> void:
	# arrange：3 步棋谱
	var path: String = _build_record_path(3)
	assert_false(path == "", "前置：测试棋谱应保存成功")
	var rc: ReplayController = ReplayController.new()
	var loaded: bool = rc.load(path)
	assert_true(loaded, "ReplayController.load 应成功")
	# 初始 current_step = 0
	assert_eq(rc.get_current_step(), 0, "加载后 current_step 应为 0")
	assert_eq(rc.get_total_steps(), 3, "total_steps 应为 3")
	# act：前进一步
	var move: Move = rc.step_forward()
	# assert
	assert_not_null(move, "step_forward 应返回非空 Move")
	assert_eq(rc.get_current_step(), 1, "前进后 current_step 应为 1")
	# 再前进一步
	var move2: Move = rc.step_forward()
	assert_eq(rc.get_current_step(), 2, "再前进后 current_step 应为 2")
	# 前进到末步后再调用返回 null
	rc.step_forward()  # 到 3
	assert_eq(rc.get_current_step(), 3, "到末步 current_step 应为 3")
	var move4: Move = rc.step_forward()
	assert_null(move4, "到末步后 step_forward 应返回 null")

# -------------------- TC-G3-002：step_backward 后退 --------------------

## step_backward 后退一步，current_step -1
func test_replay_step_backward() -> void:
	# arrange：3 步棋谱，先前进 2 步
	var path: String = _build_record_path(3)
	var rc: ReplayController = ReplayController.new()
	rc.load(path)
	rc.step_forward()
	rc.step_forward()
	assert_eq(rc.get_current_step(), 2, "前置：前进 2 步后 current_step 应为 2")
	# act：后退一步
	var move: Move = rc.step_backward()
	# assert
	assert_eq(rc.get_current_step(), 1, "后退后 current_step 应为 1")
	# 后退到初始局面后再调用返回 null
	rc.step_backward()  # 到 0
	assert_eq(rc.get_current_step(), 0, "再后退后 current_step 应为 0")
	var move2: Move = rc.step_backward()
	assert_null(move2, "在初始局面 step_backward 应返回 null")

# -------------------- TC-G3-003：auto_play 自动播放 --------------------

## auto_play 启动后 is_auto_playing 返回 true；stop_auto_play 后返回 false
func test_replay_auto_play() -> void:
	# arrange：3 步棋谱
	var path: String = _build_record_path(3)
	var rc: ReplayController = ReplayController.new()
	rc.load(path)
	# 初始未在播放
	assert_false(rc.is_auto_playing(), "加载后 is_auto_playing 应为 false")
	# act：启动自动播放
	rc.auto_play(10.0)  # 10 步/秒（快进）
	# assert
	assert_true(rc.is_auto_playing(), "auto_play 后 is_auto_playing 应为 true")
	# 停止
	rc.stop_auto_play()
	assert_false(rc.is_auto_playing(), "stop_auto_play 后 is_auto_playing 应为 false")
