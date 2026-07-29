## 单棋子视觉（AnimatedSprite2D）
## 关联：scripts/core/piece.gd、scripts/theme/theme_resource.gd、scripts/view/board_perspective.gd
##       docs/plans/2026-07-28-moechess-design.md §6.2、§6.3、§6.5
##       docs/development/acceptance-standard.md D2 / D5 / E1 / E2 / E3
##
## 职责：
##   - 加载皮肤对应的 SpriteFrames（14 项之一），按 AnimState 切换 5 状态动画
##   - 按所在 row 计算缩放（row 0→1.0，row 9→0.75）和 Y 偏移（D2）
##   - 移动用 Tween 过渡（受加速倍率影响，正常 2.5 秒/动作，加速 1.25 秒；E2/E3）
##   - 贴图不随翻转旋转（D5）；翻转视角时只重算 position / scale，rotation 始终为 0
class_name PieceView
extends AnimatedSprite2D

## 信号：移动动画完成（便于上层状态机进入下一状态）
signal move_finished(piece: Piece)

## 信号：killed 动画播放完成（便于上层移除节点 / 触发清场）
signal killed_finished(piece: Piece)

## 正常速度下移动 Tween 时长（秒）——参考 E2 "2-3 秒/动作"
const MOVE_DURATION_NORMAL: float = 2.5

## killed 动画的最长等待时长（避免缺帧卡死状态机）
const KILLED_TIMEOUT: float = 3.0

## 当前棋子数据
var piece: Piece = null

## 当前是否处于翻转视角（仅用于重算位置，不影响贴图朝向）
var flipped: bool = false

## 加速倍率（CoreConstants.SpeedMode）
var _speed_mode: int = CoreConstants.SpeedMode.NORMAL

## 当前移动 Tween（用于 kill/重启）
var _move_tween: Tween = null

## killed 计时器（防卡死）
var _killed_timer: SceneTreeTimer = null

## killed 信号是否已发出（防止 animation_finished 与兜底定时器重复触发）
var _killed_emitted: bool = false

func _ready() -> void:
	# 默认不播放，等 set_piece 后再 play
	# 注意：AnimatedSprite2D 没有 playing 属性，用 stop() 停止播放
	stop()
	animation_changed.connect(_on_animation_changed)

## 设置当前棋子并加载皮肤对应的 SpriteFrames
## 满足 C9：皮肤切换后视觉层正确重载棋子贴图
func set_piece(p_piece: Piece, theme: ThemeResource) -> void:
	piece = p_piece
	if theme == null or piece == null:
		sprite_frames = null
		return
	var key: String = "%s_%s" % [
		CoreConstants.SIDE_TO_KEY.get(piece.side, "red"),
		CoreConstants.TYPE_TO_KEY.get(piece.type, "pawn"),
	]
	if theme.pieces.has(key) and theme.pieces[key] != null:
		sprite_frames = theme.pieces[key]
	else:
		# 皮肤资源缺失时 push_warning 并保持空帧（不应发生，ThemeResource 已校验）
		push_warning("[PieceView] missing SpriteFrames for key=%s in theme=%s" % [key, theme.theme_id])
		sprite_frames = null
	# 重新计算位置和缩放
	refresh_transform(flipped)
	# 应用当前 speed_scale
	_apply_speed_scale()
	# 默认进入 idle（不立即播放）
	if sprite_frames != null and sprite_frames.has_animation(CoreConstants.ANIM_STATE_TO_KEY[CoreConstants.AnimState.IDLE]):
		play(CoreConstants.ANIM_STATE_TO_KEY[CoreConstants.AnimState.IDLE])

## 播放 5 状态动画之一（E1：选中/移动/击杀/被击杀/待机）
func play_state(anim_state: int) -> void:
	var key: String = CoreConstants.ANIM_STATE_TO_KEY.get(anim_state, "idle")
	if sprite_frames == null or not sprite_frames.has_animation(key):
		# 资源缺失时静默降级（不阻塞状态机）
		if anim_state == CoreConstants.AnimState.KILLED:
			_notify_killed_finished()
		return
	# killed 状态前重置标志
	if anim_state == CoreConstants.AnimState.KILLED:
		_killed_emitted = false
	# 重启该动画
	play(key)
	# killed 状态：动画结束后通知上层（用 SceneTreeTimer 兜底，避免无 animation_finished 信号时卡死）
	if anim_state == CoreConstants.AnimState.KILLED:
		# 监听一次 animation_finished
		if not animation_finished.is_connected(_on_killed_anim_finished):
			animation_finished.connect(_on_killed_anim_finished, CONNECT_ONE_SHOT)
		# 兜底定时器：动画时长 + 缓冲
		var dur: float = _state_duration_seconds(key)
		_killed_timer = get_tree().create_timer(dur + 0.5)
		_killed_timer.timeout.connect(_notify_killed_finished, CONNECT_ONE_SHOT)

## 移动到目标格子（Tween 过渡，受加速倍率影响）
## 满足 E3：加速按钮影响所有动效播放速度
func move_to(to_col: int, to_row: int, animated: bool) -> void:
	if piece == null:
		return
	# 取消上一次未完成的 Tween
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
		_move_tween = null
	# 更新棋子逻辑坐标
	piece = Piece.new(piece.type, piece.side, to_col, to_row)
	var target_pos: Vector2 = BoardPerspective.board_to_screen(Vector2i(to_col, to_row), flipped)
	var target_scale: float = BoardPerspective.scale_at_row(to_row, flipped)
	if not animated:
		position = target_pos
		scale = Vector2(target_scale, target_scale)
		move_finished.emit(piece)
		return
	_move_tween = create_tween()
	var duration: float = MOVE_DURATION_NORMAL / CoreConstants.SPEED_SCALE.get(_speed_mode, 1.0)
	_move_tween.set_parallel(true)
	_move_tween.tween_property(self, "position", target_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_method(_set_scale_uniform, scale.x, target_scale, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.chain().tween_callback(func(): move_finished.emit(piece))
	_move_tween.set_parallel(false)

## 设置加速倍率（E3）；立即应用到当前动画的 speed_scale 与在途 Tween
func set_speed_mode(mode: int) -> void:
	_speed_mode = mode
	_apply_speed_scale()

## 设置当前视角（重算 position / scale，不旋转贴图 D5）
func set_flipped(p_flipped: bool) -> void:
	if flipped == p_flipped:
		return
	flipped = p_flipped
	refresh_transform(flipped)

## 重算 position / scale（不修改 rotation，D5）
func refresh_transform(p_flipped: bool) -> void:
	if piece == null:
		return
	flipped = p_flipped
	position = BoardPerspective.board_to_screen(Vector2i(piece.col, piece.row), flipped)
	var s: float = BoardPerspective.scale_at_row(piece.row, flipped)
	scale = Vector2(s, s)
	rotation = 0.0  # D5：贴图不随翻转旋转

## 当前 speed_mode（供外部读取）
func get_speed_mode() -> int:
	return _speed_mode

# ---------- 内部辅助 ----------

func _set_scale_uniform(s: float) -> void:
	scale = Vector2(s, s)

func _apply_speed_scale() -> void:
	# AnimatedSprite2D.speed_scale 控制动画帧播放速度（E3）
	speed_scale = CoreConstants.SPEED_SCALE.get(_speed_mode, 1.0)

func _state_duration_seconds(anim_name: String) -> float:
	if sprite_frames == null or not sprite_frames.has_animation(anim_name):
		return 1.0
	var fc: int = sprite_frames.get_frame_count(anim_name)
	if fc <= 0:
		return 1.0
	var fps: float = sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		fps = 12.0
	return float(fc) / fps / CoreConstants.SPEED_SCALE.get(_speed_mode, 1.0)

func _on_animation_changed() -> void:
	# 切换动画时维持当前 speed_scale（Godot 4 默认会保留，但显式保险）
	_apply_speed_scale()

func _on_killed_anim_finished() -> void:
	_notify_killed_finished()

func _notify_killed_finished() -> void:
	# 防止重复触发（animation_finished 与兜底定时器都可能调用本函数）
	if _killed_emitted:
		return
	if not is_inside_tree():
		return
	_killed_emitted = true
	# 提前结束兜底定时器
	if _killed_timer != null and _killed_timer.time_left > 0.0:
		_killed_timer.time_left = 0.0
	# 断开一次性连接（若仍连着）
	if animation_finished.is_connected(_on_killed_anim_finished):
		animation_finished.disconnect(_on_killed_anim_finished)
	killed_finished.emit(piece)
