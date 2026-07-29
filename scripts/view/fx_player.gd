## 特效与音效播放器（Node2D）
## 关联：scripts/theme/theme_resource.gd、scripts/theme/theme_sfx_resource.gd、
##       docs/plans/2026-07-28-moechess-design.md §4.5 / §4.6 / §4.7
##       docs/development/acceptance-standard.md E1-E8
##
## 职责：
##   - 实例化 theme.kill_fx / killed_fx PackedScene 播放击杀/被击杀特效（E5/E6）
##   - 播放皮肤级 7 项 SFX（formation / select / move / kill / killed / victory / defeat）
##   - 胜利/战败时实例化全屏 AnimatedSprite2D 播放 victory_anim / defeat_anim（E7）
##   - set_speed_mode 影响所有特效动画 speed_scale（E3）
class_name FxPlayer
extends Node2D

## 信号：击杀特效完成（便于状态机进入下一阶段）
signal kill_fx_finished()

## 信号：被击杀特效完成
signal killed_fx_finished()

## 信号：胜利动画完成
signal victory_finished()

## 信号：战败动画完成
signal defeat_finished()

## 全队动画默认时长（兜底，E7）
const TEAM_ANIM_DURATION: float = 4.0

## 加速倍率
var _speed_mode: int = CoreConstants.SpeedMode.NORMAL

## 音效播放器
var _sfx_player: AudioStreamPlayer = null

## 当前活跃的特效节点列表（用于 set_speed_mode 批量更新）
var _active_fx: Array = []

## 当前活跃的全队动画节点
var _team_anim: AnimatedSprite2D = null

## 全队动画兜底定时器
var _team_timer: SceneTreeTimer = null

func _ready() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SFXPlayer"
	_sfx_player.bus = "Master"
	add_child(_sfx_player)

## 播放击杀特效 + kill_sfx（E5）
func play_kill_fx(at_pos: Vector2, theme: ThemeResource) -> void:
	_play_sfx(theme, "kill_sfx")
	_play_fx_scene(theme, "kill_fx", at_pos, kill_fx_finished)

## 播放被击杀特效 + killed_sfx（E6）
func play_killed_fx(at_pos: Vector2, theme: ThemeResource) -> void:
	_play_sfx(theme, "killed_sfx")
	_play_fx_scene(theme, "killed_fx", at_pos, killed_fx_finished)

## 选中音效
func play_select_sfx(theme: ThemeResource) -> void:
	_play_sfx(theme, "select_sfx")

## 移动音效
func play_move_sfx(theme: ThemeResource) -> void:
	_play_sfx(theme, "move_sfx")

## 列阵音效（双人对战换边时触发，E8）
func play_formation_sfx(theme: ThemeResource) -> void:
	_play_sfx(theme, "formation_sfx")

## 胜利：全队动画 + victory_sfx（E7）
func play_victory(theme: ThemeResource) -> void:
	_play_sfx(theme, "victory_sfx")
	_play_team_anim(theme, "victory_anim", "victory", victory_finished)

## 战败：全队动画 + defeat_sfx（E7）
func play_defeat(theme: ThemeResource) -> void:
	_play_sfx(theme, "defeat_sfx")
	_play_team_anim(theme, "defeat_anim", "defeat", defeat_finished)

## 设置加速倍率（影响特效动画 speed_scale，E3）
func set_speed_mode(mode: int) -> void:
	_speed_mode = mode
	var sc: float = CoreConstants.SPEED_SCALE.get(mode, 1.0)
	for fx in _active_fx:
		if is_instance_valid(fx):
			_apply_speed_to_node(fx, sc)
	if is_instance_valid(_team_anim):
		_team_anim.speed_scale = sc

# ---------- 内部辅助 ----------

## 播放皮肤级 SFX（缺失时静默降级）
func _play_sfx(theme: ThemeResource, field: String) -> void:
	if theme == null or theme.sfx == null:
		return
	var stream: AudioStream = theme.sfx.get(field)
	if stream == null:
		return
	_sfx_player.stream = stream
	_sfx_player.play()

## 实例化 PackedScene 特效并定位（E5/E6）
func _play_fx_scene(theme: ThemeResource, field: String, at_pos: Vector2, finished_signal: Signal) -> void:
	if theme == null:
		finished_signal.emit()
		return
	var packed: PackedScene = theme.get(field)
	if packed == null:
		# 占位场景缺失：画一个短促粒子作为兜底
		_spawn_placeholder_fx(at_pos, finished_signal)
		return
	var inst: Node2D = packed.instantiate() as Node2D
	if inst == null:
		finished_signal.emit()
		return
	inst.position = at_pos
	add_child(inst)
	_active_fx.append(inst)
	_apply_speed_to_node(inst, CoreConstants.SPEED_SCALE.get(_speed_mode, 1.0))
	# 监听子 AnimatedSprite2D 完成或用定时器兜底（FX 时长 1.5s）
	var life: float = 1.5 / CoreConstants.SPEED_SCALE.get(_speed_mode, 1.0)
	var t: SceneTreeTimer = get_tree().create_timer(life)
	var cb: Callable = func() -> void:
		if is_instance_valid(inst):
			inst.queue_free()
		_active_fx.erase(inst)
		finished_signal.emit()
	t.timeout.connect(cb, CONNECT_ONE_SHOT)

## 兜底特效（PLACEHOLDER 模式：theme.kill_fx 缺失时）
func _spawn_placeholder_fx(at_pos: Vector2, finished_signal: Signal) -> void:
	var placeholder: Node2D = Node2D.new()
	placeholder.name = "PlaceholderFX"
	placeholder.position = at_pos
	add_child(placeholder)
	_active_fx.append(placeholder)
	# 用一个简单的 Tween 画一个扩散圈（程序化，非常驻几何圈——这是短暂反馈，非调试辅助层）
	var draw: DrawFx = DrawFx.new()
	draw.color = Color(1.0, 0.5, 0.2, 0.8)
	placeholder.add_child(draw)
	var tween: Tween = create_tween()
	tween.tween_property(draw, "scale", Vector2(2.0, 2.0), 0.6 / CoreConstants.SPEED_SCALE.get(_speed_mode, 1.0)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(draw, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		if is_instance_valid(placeholder):
			placeholder.queue_free()
		_active_fx.erase(placeholder)
		finished_signal.emit()
	)

## 全队动画（E7）
func _play_team_anim(theme: ThemeResource, field: String, anim_name: String, finished_signal: Signal) -> void:
	if theme == null or theme.get(field) == null:
		finished_signal.emit()
		return
	# 清理上一个全队动画与兜底定时器（避免旧回调误清新实例）
	if _team_timer != null and _team_timer.time_left > 0.0:
		# 设为 0 会立即触发回调；为避免回调引用即将被替换的 _team_anim，先标记 null
		var prev_anim: AnimatedSprite2D = _team_anim
		_team_anim = null
		_team_timer.time_left = 0.0
		_team_timer = null
		if is_instance_valid(prev_anim):
			prev_anim.queue_free()
	if is_instance_valid(_team_anim):
		_team_anim.queue_free()
	_team_anim = AnimatedSprite2D.new()
	_team_anim.name = "TeamAnim"
	_team_anim.sprite_frames = theme.get(field)
	_team_anim.position = Vector2(BoardPerspective.CENTER_X, BoardPerspective.BG_H / 2.0)
	_team_anim.scale = Vector2(2.0, 2.0)  # 全屏放大
	_team_anim.speed_scale = CoreConstants.SPEED_SCALE.get(_speed_mode, 1.0)
	add_child(_team_anim)
	if _team_anim.sprite_frames != null and _team_anim.sprite_frames.has_animation(anim_name):
		_team_anim.play(anim_name)
	# 兜底定时器
	var dur: float = TEAM_ANIM_DURATION / CoreConstants.SPEED_SCALE.get(_speed_mode, 1.0)
	var anim_ref: AnimatedSprite2D = _team_anim
	_team_timer = get_tree().create_timer(dur)
	var cb: Callable = func() -> void:
		if is_instance_valid(anim_ref):
			anim_ref.queue_free()
		if _team_anim == anim_ref:
			_team_anim = null
		finished_signal.emit()
	_team_timer.timeout.connect(cb, CONNECT_ONE_SHOT)

## 给节点树批量应用 speed_scale（递归 AnimatedSprite2D）
func _apply_speed_to_node(node: Node, sc: float) -> void:
	if node is AnimatedSprite2D:
		(node as AnimatedSprite2D).speed_scale = sc
	if node is AnimationPlayer:
		(node as AnimationPlayer).speed_scale = sc
	for child in node.get_children():
		if child is Node:
			_apply_speed_to_node(child, sc)


## 内部小型自绘 FX 节点（用于 PLACEHOLDER 模式缺 theme.kill_fx 时）
class DrawFx:
	extends Node2D
	var color: Color = Color(1.0, 0.5, 0.2, 0.8)
	var radius: float = 24.0
	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)
