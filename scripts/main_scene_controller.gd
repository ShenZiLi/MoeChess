## 主场景编排脚本（视图/UI/状态机 信号连线）
## 关联：scenes/main.tscn、scripts/states/game_state_machine.gd、scripts/states/playing_state.gd
## 覆盖验收：D4（翻转序列）、E1-E8（动画/音效触发）、F4（可走位置提示）、F5（胜负动画）
##
## 本脚本是 visual-reviewer/reviewer 指出的"编排层缺失"根因修复：
## - 实例化 HUD / GameoverPanel / PausePanel / MainMenu / DebugLayer 到 UI CanvasLayer
## - 注入 BoardView.fx_player
## - 订阅 PlayingState 的视觉信号 → 调用 BoardView/FxPlayer/MoveHintLayer 对应方法
## - 订阅 BoardView 的点击信号 → 转发到 PlayingState
## - 订阅 GameStateMachine.state_changed → 切换 UI 面板
class_name MainSceneController
extends Node2D

@onready var _board_view: Node2D = $BoardView
@onready var _fx_player: Node2D = $FxPlayer
@onready var _move_hint_layer: Node2D = $MoveHintLayer
@onready var _ui_layer: CanvasLayer = $UI

var _hud: Control = null
var _main_menu: Control = null
var _pause_panel: Control = null
var _gameover_panel: Control = null
var _debug_layer: Control = null

var _playing_state: PlayingState = null
var _input_provider: InputProvider = null

func _ready() -> void:
	# 注入 FxPlayer 到 BoardView（D4/E8 翻转时自动播 formation_sfx）
	if _board_view.has_method("set_fx_player"):
		_board_view.set_fx_player(_fx_player)
	elif "fx_player" in _board_view:
		_board_view.fx_player = _fx_player

	# 实例化 UI 面板
	_instantiate_ui_panels()

	# 实例化 InputProvider
	_input_provider = InputProvider.new()
	_input_provider.name = "InputProvider"
	add_child(_input_provider)
	_input_provider.set_board_view(_board_view)
	_input_provider.set_enabled(false)
	_input_provider.piece_clicked.connect(_on_piece_clicked)
	_input_provider.cell_clicked.connect(_on_cell_clicked)
	_input_provider.pause_requested.connect(_on_pause_requested)

	# 订阅 GameStateMachine 状态切换
	var gsm: Node = GameStateMachine
	gsm.state_changed.connect(_on_state_changed)
	gsm.start_new_game_requested.connect(_on_start_new_game_requested) if gsm.has_signal("start_new_game_requested") else null

	# 启动：尝试续局，否则进入主菜单
	_start_session()

## 实例化 UI 面板到 UI CanvasLayer
func _instantiate_ui_panels() -> void:
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn")
	_hud = hud_scene.instantiate()
	_ui_layer.add_child(_hud)
	_hud.speed_toggled.connect(_on_speed_toggled)
	_hud.pause_pressed.connect(_on_pause_pressed)

	var main_menu_scene: PackedScene = load("res://scenes/ui/main_menu.tscn")
	_main_menu = main_menu_scene.instantiate()
	_ui_layer.add_child(_main_menu)
	_main_menu.start_pressed.connect(_on_start_pressed)
	_main_menu.quit_pressed.connect(_on_quit_pressed)

	var pause_scene: PackedScene = load("res://scenes/ui/pause_panel.tscn")
	_pause_panel = pause_scene.instantiate()
	_ui_layer.add_child(_pause_panel)
	_pause_panel.resume_pressed.connect(_on_resume_pressed)
	_pause_panel.restart_pressed.connect(_on_restart_pressed)
	_pause_panel.menu_pressed.connect(_on_menu_pressed)
	_pause_panel.visible = false

	var gameover_scene: PackedScene = load("res://scenes/ui/gameover_panel.tscn")
	_gameover_panel = gameover_scene.instantiate()
	_ui_layer.add_child(_gameover_panel)
	_gameover_panel.restart_pressed.connect(_on_restart_pressed)
	_gameover_panel.menu_pressed.connect(_on_menu_pressed)
	_gameover_panel.replay_pressed.connect(_on_replay_pressed)
	_gameover_panel.visible = false

	# DebugLayer（默认关闭，I2/I3 红线）
	var debug_script: GDScript = load("res://scripts/debug/debug_layer.gd")
	_debug_layer = Control.new()
	_debug_layer.set_script(debug_script)
	_debug_layer.name = "DebugLayer"
	_ui_layer.add_child(_debug_layer)

	# 订阅 ThemeManager 切换 → HUD 头像刷新（E4）
	ThemeManager.theme_changed.connect(_on_theme_changed)
	_on_theme_changed(ThemeManager.get_current())

## 启动会话：若有自动存档则续局，否则主菜单
func _start_session() -> void:
	var gsm: Node = GameStateMachine
	if gsm.has_method("resume_from_auto_save"):
		if gsm.resume_from_auto_save():
			return
	gsm.change_state("MainMenu")
	_show_panel("MainMenu")

## 状态切换处理（F1）
func _on_state_changed(_old: String, new_state: String) -> void:
	_show_panel(new_state)
	match new_state:
		"Playing":
			_playing_state = GameStateMachine.get_playing_state()
			_connect_playing_state_signals()
			_input_provider.set_board_state(GameStateMachine.get_board_state())
			_input_provider.set_enabled(true)
			_hud.set_turn(GameStateMachine.get_board_state().side_to_move)
		"Paused":
			_input_provider.set_enabled(false)
		"Gameover":
			_input_provider.set_enabled(false)
			var result: Dictionary = {"over": true, "result": "draw"}
			_gameover_panel.show_result(result, ThemeManager.get_current())
		"Replay":
			_input_provider.set_enabled(false)
		"MainMenu":
			_input_provider.set_enabled(false)
		_:
			_input_provider.set_enabled(false)

## 显示指定状态的 UI 面板
func _show_panel(state_name: String) -> void:
	_hud.visible = (state_name == "Playing" or state_name == "Paused")
	_main_menu.visible = (state_name == "MainMenu")
	_pause_panel.visible = (state_name == "Paused")
	_gameover_panel.visible = (state_name == "Gameover")

## 连接 PlayingState 视觉信号 → 视图调用（D4/E1-E8/F4/F5）
func _connect_playing_state_signals() -> void:
	if _playing_state == null:
		return
	# 清理旧连接（若有）
	_disconnect_playing_state_signals()
	# F4：选中棋子时显示可走位置提示
	_playing_state.request_show_hints.connect(_on_show_hints)
	_playing_state.request_clear_hints.connect(_on_clear_hints)
	# D4：双人对战换边触发视角翻转 + 列阵音效
	_playing_state.request_flip_view.connect(_on_flip_view)
	# E1/E2：走子动画
	_playing_state.move_started.connect(_on_move_started)
	# E1：棋子选中动画
	_playing_state.piece_selected.connect(_on_piece_selected)
	# F5：终局
	_playing_state.game_over.connect(_on_game_over)
	# AI 思考中
	if _playing_state.has_signal("ai_thinking_started"):
		_playing_state.ai_thinking_started.connect(_on_ai_thinking_started)
	if _playing_state.has_signal("ai_thinking_finished"):
		_playing_state.ai_thinking_finished.connect(_on_ai_thinking_finished)
	# 订阅 BoardView 点击信号
	if not _board_view.piece_clicked.is_connected(_on_board_piece_clicked):
		_board_view.piece_clicked.connect(_on_board_piece_clicked)
	if not _board_view.cell_clicked.is_connected(_on_board_cell_clicked):
		_board_view.cell_clicked.connect(_on_board_cell_clicked)
	# 订阅 BoardView 翻转完成
	if _board_view.has_signal("flip_finished") and not _board_view.flip_finished.is_connected(_on_flip_done):
		_board_view.flip_finished.connect(_on_flip_done)
	# 订阅棋子移动/击杀完成（驱动状态机推进）
	if _board_view.has_signal("piece_move_finished") and not _board_view.piece_move_finished.is_connected(_on_move_anim_done):
		_board_view.piece_move_finished.connect(_on_move_anim_done)

func _disconnect_playing_state_signals() -> void:
	if _playing_state == null:
		return
	for sig in [_playing_state.request_show_hints, _playing_state.request_clear_hints, _playing_state.request_flip_view, _playing_state.move_started, _playing_state.piece_selected, _playing_state.game_over]:
		for c in sig.get_connections():
			sig.disconnect(c.callable)

# -------------------- 信号处理 --------------------

func _on_piece_clicked(piece: Piece) -> void:
	if _playing_state != null:
		_playing_state.on_piece_clicked(piece)

func _on_cell_clicked(pos: Vector2i) -> void:
	if _playing_state != null:
		_playing_state.on_cell_clicked(pos)

func _on_board_piece_clicked(piece: Piece) -> void:
	if _playing_state != null:
		_playing_state.on_piece_clicked(piece)

func _on_board_cell_clicked(pos: Vector2i) -> void:
	if _playing_state != null:
		_playing_state.on_cell_clicked(pos)

func _on_move_anim_done(_piece: Piece) -> void:
	if _playing_state != null:
		_playing_state.on_move_anim_done()

func _on_flip_done(_flipped: bool) -> void:
	if _playing_state != null and _playing_state.has_method("on_flip_done"):
		_playing_state.on_flip_done()

func _on_show_hints(moves: Array) -> void:
	_move_hint_layer.show_hints(moves)

func _on_clear_hints() -> void:
	_move_hint_layer.clear_hints()

func _on_flip_view() -> void:
	# D4：翻转序列 = 列阵音效（BoardView.flip_view 内部触发） + 背景切换 + 重算布局 + Tween
	_board_view.flip_view()
	_move_hint_layer.set_flipped(not _move_hint_layer._flipped) if "flipped" in _move_hint_layer else null

func _on_move_started(move: Move) -> void:
	# E1/E2：触发棋子移动动画 + 移动音效
	_fx_player.play_move_sfx(ThemeManager.get_current())
	# 视觉层具体由 BoardView 内部驱动 PieceView.move_to，这里只触发音效
	if _board_view.has_method("play_move"):
		_board_view.play_move(move)
	else:
		# 兜底：直接通知 move anim done
		_on_move_anim_done(move.moved_piece)

func _on_piece_selected(piece: Piece) -> void:
	# E1：选中音效 + 选中动画
	_fx_player.play_select_sfx(ThemeManager.get_current())
	if _board_view.has_method("play_piece_state"):
		_board_view.play_piece_state(piece, CoreConstants.AnimState.SELECTED)

func _on_game_over(result: Dictionary) -> void:
	# F5：胜负动画 + 音效
	var theme: ThemeResource = ThemeManager.get_current()
	if result.get("result") == "red_win":
		_fx_player.play_victory(theme)
	elif result.get("result") == "black_win":
		_fx_player.play_defeat(theme)

func _on_ai_thinking_started() -> void:
	if _hud.has_method("set_thinking"):
		_hud.set_thinking(true)

func _on_ai_thinking_finished() -> void:
	if _hud.has_method("set_thinking"):
		_hud.set_thinking(false)

func _on_theme_changed(theme: ThemeResource) -> void:
	if _hud != null and _hud.has_method("set_theme_resource"):
		_hud.set_theme_resource(theme)
	# 棋盘背景同步切换（C9）
	if _board_view.has_method("set_theme"):
		_board_view.set_theme(theme)
	# DebugLayer 也可接收主题
	if _debug_layer != null and _debug_layer.has_method("update_info"):
		_debug_layer.update_info({"theme": theme.theme_id if theme != null else ""})

func _on_speed_toggled() -> void:
	var gsm: Node = GameStateMachine
	var current_mode: int = CoreConstants.SpeedMode.NORMAL
	if gsm.has_method("get_speed_mode"):
		current_mode = gsm.get_speed_mode() if gsm.has_method("get_speed_mode") else CoreConstants.SpeedMode.NORMAL
	var new_mode: int = CoreConstants.SpeedMode.FAST if current_mode == CoreConstants.SpeedMode.NORMAL else CoreConstants.SpeedMode.NORMAL
	if gsm.has_method("set_speed_mode"):
		gsm.set_speed_mode(new_mode)
	if _board_view.has_method("set_speed_mode"):
		_board_view.set_speed_mode(new_mode)
	if _fx_player.has_method("set_speed_mode"):
		_fx_player.set_speed_mode(new_mode)
	if _hud.has_method("set_speed_mode"):
		_hud.set_speed_mode(new_mode)

func _on_pause_pressed() -> void:
	GameStateMachine.pause_game()

func _on_pause_requested() -> void:
	if GameStateMachine.get_current_state() == "Playing":
		GameStateMachine.pause_game()

func _on_resume_pressed() -> void:
	GameStateMachine.resume_game()

func _on_restart_pressed() -> void:
	GameStateMachine.restart_game()

func _on_menu_pressed() -> void:
	GameStateMachine.return_to_menu()

func _on_start_pressed() -> void:
	# 主菜单"开始" → SelectMode（简化：直接以中等难度人机开局）
	# 正式流程应由 SelectTheme / SelectMode 面板触发，这里做最小可用编排
	GameStateMachine.start_new_game(GameStateMachine.GameMode.PVE_MEDIUM, CoreConstants.Difficulty.MEDIUM)

func _on_start_new_game_requested(mode: int, difficulty: int) -> void:
	GameStateMachine.start_new_game(mode, difficulty)

func _on_replay_pressed() -> void:
	# 选择最近一份棋谱进入复盘
	var records: Array = SaveManager.list_records()
	if records.is_empty():
		return
	GameStateMachine.enter_replay(records[0]["path"])

func _on_quit_pressed() -> void:
	get_tree().quit()

func _is_flipped() -> bool:
	if _board_view != null and "flipped" in _board_view:
		return bool(_board_view.flipped)
	return false
