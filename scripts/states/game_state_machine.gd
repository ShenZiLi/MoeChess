## 全局游戏流程状态机（autoload，已在 project.godot 注册为 GameStateMachine）
## 关联：docs/plans/2026-07-28-moechess-design.md §7.1、docs/development/acceptance-standard.md F1/F2
##
## 职责：
## - 管理 Boot→MainMenu→SelectTheme→SelectMode→Playing→Gameover 全局流程（F1）
## - Paused 状态可暂停/继续/重开/返回菜单（F2）
## - 持有当前 BoardState、对局模式、难度、皮肤 id
## - 持有 AIWorker 子节点，注入到 PlayingState
## - 通过 state_changed 信号通知 UI 层切换场景/面板
##
## 状态用字符串名标识（"Boot"/"MainMenu"/"SelectTheme"/"SelectMode"/"Playing"/"Paused"/"Gameover"/"Replay"），
## 内部维护 GameState 枚举便于 switch；外部通过 change_state(name) / get_current_state() 交互。
##
## 注意：不声明 class_name GameStateMachine——本脚本通过 project.godot 注册为
## autoload 单例 `GameStateMachine`，所有 GameStateMachine.xxx 调用走 autoload 名。
## 保留 class_name 会触发 "Class GameStateMachine hides an autoload singleton" 报错。
extends Node

# 全局状态枚举（F1）
enum GameState {
	BOOT,
	MAIN_MENU,
	SELECT_THEME,
	SELECT_MODE,
	PLAYING,
	PAUSED,
	GAMEOVER,
	REPLAY,
}

# 对局模式枚举
enum GameMode {
	PVE_LOW,     # 人机 低难度（搜索深度 2）
	PVE_MEDIUM,  # 人机 中难度（搜索深度 4）
	PVE_HIGH,    # 人机 高难度（搜索深度 6）
	PVP,         # 双人本地
}

# 状态名 ↔ 枚举映射（change_state / get_current_state 用字符串名）
const STATE_NAME_TO_ENUM: Dictionary = {
	"Boot": GameState.BOOT,
	"MainMenu": GameState.MAIN_MENU,
	"SelectTheme": GameState.SELECT_THEME,
	"SelectMode": GameState.SELECT_MODE,
	"Playing": GameState.PLAYING,
	"Paused": GameState.PAUSED,
	"Gameover": GameState.GAMEOVER,
	"Replay": GameState.REPLAY,
}

const STATE_ENUM_TO_NAME: Dictionary = {
	GameState.BOOT: "Boot",
	GameState.MAIN_MENU: "MainMenu",
	GameState.SELECT_THEME: "SelectTheme",
	GameState.SELECT_MODE: "SelectMode",
	GameState.PLAYING: "Playing",
	GameState.PAUSED: "Paused",
	GameState.GAMEOVER: "Gameover",
	GameState.REPLAY: "Replay",
}

## 状态切换信号（UI 层订阅此信号切换场景/面板）
## old_state / new_state 为状态名字符串
signal state_changed(old_state: String, new_state: String)

## 当前全局状态（枚举）
var _current_state: int = GameState.BOOT

## 当前 BoardState（Playing 期间有效，每次走子后替换为新对象）
var _board_state: BoardState = null

## 当前对局模式
var _game_mode: int = GameMode.PVE_LOW

## 当前难度（CoreConstants.Difficulty，人机模式有效；PVP 模式忽略）
var _difficulty: int = CoreConstants.Difficulty.LOW

## 当前皮肤 id
var _theme_id: String = ""

## 暂停前的状态（用于 resume_game 恢复，通常为 Playing）
var _state_before_pause: int = GameState.PLAYING

## Playing 子状态机
var _playing_state: PlayingState = null

## AI Worker 子节点（持有人机计算的线程）
var _ai_worker: AIWorker = null

func _ready() -> void:
	_ai_worker = AIWorker.new()
	_ai_worker.name = "AIWorker"
	add_child(_ai_worker)
	GameLogger.info("[GameStateMachine] ready, state=Boot")

## 切换全局状态（F1）
## new_state 必须是 STATE_NAME_TO_ENUM 的键之一
## 切换后发 state_changed 信号
func change_state(new_state: String) -> void:
	if not STATE_NAME_TO_ENUM.has(new_state):
		push_warning("[GameStateMachine] unknown state: %s" % new_state)
		return
	var new_enum: int = STATE_NAME_TO_ENUM[new_state]
	if new_enum == _current_state:
		return
	var old_name: String = STATE_ENUM_TO_NAME[_current_state]
	_current_state = new_enum
	GameLogger.info("[GameStateMachine] %s -> %s" % [old_name, new_state])
	state_changed.emit(old_name, new_state)

## 获取当前状态名（字符串）
func get_current_state() -> String:
	return STATE_ENUM_TO_NAME[_current_state]

## 获取当前状态枚举
func get_current_state_enum() -> int:
	return _current_state

## 开始新对局（F1：SelectMode → Playing）
## mode: GameMode.{PVE_LOW/PVE_MEDIUM/PVE_HIGH/PVP}
## difficulty: CoreConstants.Difficulty.{LOW/MEDIUM/HIGH}（PVP 模式忽略）
func start_new_game(mode: int, difficulty: int) -> void:
	# 清理旧 PlayingState（若存在）
	if _playing_state != null:
		_playing_state.exit()
		_playing_state = null
	# 取消未完成的 AI 计算
	if _ai_worker != null and _ai_worker.is_computing():
		_ai_worker.cancel()
	_game_mode = mode
	_difficulty = difficulty
	if mode == GameMode.PVP:
		_difficulty = CoreConstants.Difficulty.LOW  # PVP 不用 AI
	# 创建初始局面
	_board_state = BoardState.initial()
	# 记录当前皮肤 id
	var theme = ThemeManager.get_current()
	_theme_id = theme.theme_id if theme != null else ""
	# 创建 Playing 子状态机
	_playing_state = PlayingState.new()
	_playing_state.set_ai_worker(_ai_worker)
	_playing_state.set_game_mode(mode)
	_playing_state.set_difficulty(_difficulty)
	_playing_state.set_player_side(CoreConstants.Side.RED)
	# 连接 game_over 信号转发到全局状态切换（F5）
	if not _playing_state.game_over.is_connected(_on_playing_game_over):
		_playing_state.game_over.connect(_on_playing_game_over)
	_playing_state.enter(_board_state)
	# 清除旧自动存档（开新局）
	SaveManager.clear_auto_save()
	change_state("Playing")
	GameLogger.info("[GameStateMachine] start_new_game mode=%d difficulty=%d theme=%s" % [mode, _difficulty, _theme_id])

## 暂停游戏（F2：Playing → Paused）
func pause_game() -> void:
	if _current_state != GameState.PLAYING:
		return
	_state_before_pause = _current_state
	change_state("Paused")
	if _playing_state != null:
		_playing_state.on_paused()

## 继续游戏（F2：Paused → 暂停前状态，通常为 Playing）
func resume_game() -> void:
	if _current_state != GameState.PAUSED:
		return
	change_state(STATE_ENUM_TO_NAME[_state_before_pause])
	if _playing_state != null:
		_playing_state.on_resumed()

## 重开（F2：Paused/Gameover → Playing，按当前模式/难度重新初始化）
func restart_game() -> void:
	start_new_game(_game_mode, _difficulty)

## 返回主菜单（F2）
func return_to_menu() -> void:
	if _playing_state != null:
		_playing_state.exit()
		_playing_state = null
	_board_state = null
	if _ai_worker != null and _ai_worker.is_computing():
		_ai_worker.cancel()
	change_state("MainMenu")

## 进入复盘模式（G3：Gameover/MainMenu → Replay）
## 加载指定棋谱并创建 ReplayController
func enter_replay(record_path: String) -> void:
	if _playing_state != null:
		_playing_state.exit()
		_playing_state = null
	if _ai_worker != null and _ai_worker.is_computing():
		_ai_worker.cancel()
	_replay_controller = ReplayController.new()
	_replay_controller.load(record_path)
	change_state("Replay")
	GameLogger.info("[GameStateMachine] enter_replay: %s" % record_path)

## 启动时若存在自动存档则续局（G5）
## 返回 true 表示已恢复对局，false 表示无自动存档
func resume_from_auto_save() -> bool:
	var data: Dictionary = SaveManager.load_auto_save()
	if not data.get("has_save", false):
		return false
	var state_dict: Dictionary = data.get("state", {})
	if state_dict.is_empty():
		return false
	var settings: Dictionary = data.get("settings", {})
	# 恢复模式/难度/皮肤
	var mode_str: String = settings.get("mode", "PVE_LOW")
	_game_mode = _mode_from_string(mode_str)
	_difficulty = int(settings.get("difficulty", CoreConstants.Difficulty.LOW))
	if _game_mode == GameMode.PVP:
		_difficulty = CoreConstants.Difficulty.LOW
	var theme_id: String = settings.get("theme_id", "")
	if theme_id != "" and ThemeManager != null:
		ThemeManager.switch_to(theme_id)
	_theme_id = theme_id
	# 恢复局面
	_board_state = BoardState.from_dict(state_dict)
	# 创建 Playing 子状态机
	_playing_state = PlayingState.new()
	_playing_state.set_ai_worker(_ai_worker)
	_playing_state.set_game_mode(_game_mode)
	_playing_state.set_difficulty(_difficulty)
	_playing_state.set_player_side(CoreConstants.Side.RED)
	if not _playing_state.game_over.is_connected(_on_playing_game_over):
		_playing_state.game_over.connect(_on_playing_game_over)
	_playing_state.enter(_board_state)
	change_state("Playing")
	GameLogger.info("[GameStateMachine] resumed from auto_save, mode=%d difficulty=%d theme=%s" % [_game_mode, _difficulty, _theme_id])
	return true

## 走子完成后触发自动存档（G5）
## 由 PlayingState 在 _apply_move_and_animate 后调用
func notify_move_applied(new_state: BoardState) -> void:
	_board_state = new_state
	# 所有模式都自动存档
	var settings: Dictionary = _build_settings_dict()
	SaveManager.auto_save(_board_state, settings)

## 构建设置字典（用于自动存档）
func _build_settings_dict() -> Dictionary:
	return {
		"mode": _mode_string(_game_mode),
		"difficulty": _difficulty,
		"theme_id": _theme_id,
		"speed_mode": _speed_mode,
	}

var _speed_mode: int = CoreConstants.SpeedMode.NORMAL

## 设置加速模式（HUD 加速按钮调用）
func set_speed_mode(mode: int) -> void:
	_speed_mode = mode

## 获取当前 ReplayController（Replay 状态有效）
func get_replay_controller() -> ReplayController:
	return _replay_controller

## 模式字符串 → 枚举
func _mode_from_string(s: String) -> int:
	match s:
		SaveManager.MODE_PVE_LOW:
			return GameMode.PVE_LOW
		SaveManager.MODE_PVE_MEDIUM:
			return GameMode.PVE_MEDIUM
		SaveManager.MODE_PVE_HIGH:
			return GameMode.PVE_HIGH
		SaveManager.MODE_PVP:
			return GameMode.PVP
		_:
			return GameMode.PVE_LOW

## 当前 ReplayController（Replay 状态有效）
var _replay_controller: ReplayController = null

## 获取当前 BoardState
func get_board_state() -> BoardState:
	return _board_state

## 获取当前对局模式
func get_game_mode() -> int:
	return _game_mode

## 获取当前难度
func get_difficulty() -> int:
	return _difficulty

## 获取当前皮肤 id
func get_theme_id() -> String:
	return _theme_id

## 设置当前皮肤 id（SelectTheme 状态调用）
func set_theme_id(theme_id: String) -> void:
	_theme_id = theme_id

## 获取 Playing 子状态机（UI 层调用以注入输入 / 订阅信号）
func get_playing_state() -> PlayingState:
	return _playing_state

## 获取 AI Worker（测试/调试用）
func get_ai_worker() -> AIWorker:
	return _ai_worker

## PlayingState 触发 game_over 信号时切换到 Gameover 状态（F5）
## result: {over: bool, result: "red_win"/"black_win"/"draw"/null}
func _on_playing_game_over(result: Dictionary) -> void:
	GameLogger.info("[GameStateMachine] game_over received: %s" % result)
	# 保存棋谱到 records（G2）
	if _board_state != null:
		var meta: Dictionary = {
			"theme_id": _theme_id,
			"mode": _mode_string(_game_mode),
			"difficulty": _difficulty if _game_mode != GameMode.PVP else -1,
			"result": result.get("result", null),
		}
		SaveManager.save_record(_board_state, meta)
		SaveManager.clear_auto_save()
	change_state("Gameover")

## 模式枚举转字符串（写入棋谱 meta.mode，与 SaveManager 约定一致）
func _mode_string(mode: int) -> String:
	match mode:
		GameMode.PVE_LOW:
			return SaveManager.MODE_PVE_LOW
		GameMode.PVE_MEDIUM:
			return SaveManager.MODE_PVE_MEDIUM
		GameMode.PVE_HIGH:
			return SaveManager.MODE_PVE_HIGH
		GameMode.PVP:
			return SaveManager.MODE_PVP
		_:
			return "UNKNOWN"
