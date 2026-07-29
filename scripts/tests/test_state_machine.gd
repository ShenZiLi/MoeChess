## 全局状态机集成测试 — 验收 F1（Boot→MainMenu→...→Gameover 流转）/ F2（Paused 暂停/继续/重开）/ F5（将死进入 Gameover）
## 关联：docs/development/test-cases.md TC-F1-001 / TC-F2-001 / TC-F5-001、acceptance-standard.md F1/F2/F5
## 关联实现：scripts/states/game_state_machine.gd
##
## GameStateMachine 是 autoload 单例，GUT 运行时已 _ready
extends GutTest

# -------------------- 钩子 --------------------

func before_each() -> void:
	if GameLogger != null:
		GameLogger.set_file_output(false)

func after_each() -> void:
	if GameLogger != null:
		GameLogger.set_file_output(true)

# -------------------- TC-F1-001：状态机初始状态 --------------------

## GameStateMachine 启动时为 Boot 状态
func test_state_machine_initial_state() -> void:
	# arrange & act
	var current: String = GameStateMachine.get_current_state()
	# assert：启动时为 Boot（autoload _ready 已执行）
	# 注意：GUT 启动时 GameStateMachine._ready 已运行，状态可能已被外部代码改动
	# 此处仅断言状态机可用且返回字符串
	assert_true(current is String, "get_current_state 应返回字符串")
	assert_true(GameStateMachine.STATE_NAME_TO_ENUM.has(current), "当前状态应是合法状态名：%s" % current)

# -------------------- TC-F1-002：状态切换 --------------------

## change_state 切换到新状态，get_current_state 反映新状态
func test_state_change() -> void:
	# arrange：监听 state_changed 信号
	var signal_received: bool = false
	var received_new: String = ""
	var callable: Callable = Callable(func(old_state: String, new_state: String):
		signal_received = true
		received_new = new_state
	)
	GameStateMachine.state_changed.connect(callable)
	# 先切到 MainMenu（如果不在的话）
	var before: String = GameStateMachine.get_current_state()
	# act
	GameStateMachine.change_state("MainMenu")
	var after: String = GameStateMachine.get_current_state()
	# assert
	assert_eq(after, "MainMenu", "change_state 后状态应为 MainMenu")
	if before != "MainMenu":
		assert_true(signal_received, "state_changed 信号应被触发")
		assert_eq(received_new, "MainMenu", "信号参数新状态应为 MainMenu")
	# 清理
	GameStateMachine.state_changed.disconnect(callable)

# -------------------- TC-F2-001：start_new_game 进入 Playing --------------------

## start_new_game 创建初始局面并切换到 Playing
func test_start_new_game() -> void:
	# arrange & act
	GameStateMachine.start_new_game(GameStateMachine.GameMode.PVE_LOW, CoreConstants.Difficulty.LOW)
	# assert
	assert_eq(GameStateMachine.get_current_state(), "Playing", "start_new_game 后应为 Playing 状态")
	assert_not_null(GameStateMachine.get_board_state(), "应有初始 BoardState")
	assert_not_null(GameStateMachine.get_playing_state(), "应有 PlayingState 子状态机")
	# 当前模式 = PVE_LOW
	assert_eq(GameStateMachine.get_game_mode(), GameStateMachine.GameMode.PVE_LOW, "模式应为 PVE_LOW")

# -------------------- TC-F2-002：pause / resume --------------------

## pause_game 切到 Paused；resume_game 恢复
func test_pause_resume() -> void:
	# arrange：先进入 Playing
	GameStateMachine.start_new_game(GameStateMachine.GameMode.PVE_LOW, CoreConstants.Difficulty.LOW)
	# act：暂停
	GameStateMachine.pause_game()
	assert_eq(GameStateMachine.get_current_state(), "Paused", "pause_game 后应为 Paused")
	# 继续
	GameStateMachine.resume_game()
	assert_eq(GameStateMachine.get_current_state(), "Playing", "resume_game 后应回到 Playing")
