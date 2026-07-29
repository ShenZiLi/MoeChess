## 结算面板（验收 F5/E7：将死进入 Gameover，播放胜负动画）
## 关联：scripts/theme/theme_resource.gd、scripts/core/constants.gd、
##       docs/development/acceptance-standard.md F5/E7、docs/plans/2026-07-28-moechess-design.md §4.5、§7.1
##
## 显示胜负文字 + 播放当前皮肤的 victory_anim / defeat_anim；下方三按钮：重开/回菜单/复盘。
## show_result 接收 GameController.check_game_over 返回的 result Dictionary：
##   {over: bool, result: "red_win" / "black_win" / "draw" / null}
## 视觉层可订阅 AnimatedSprite2D 的 animation_finished 信号做后续效果；本类只确保动画被触发。
class_name GameoverPanel
extends Control

## 重开——回 SelectMode 或重启 Playing
signal restart_pressed()

## 回菜单——回 MainMenu
signal menu_pressed()

## 复盘——进入 Replay 状态
signal replay_pressed()

## 当前主题资源
var _theme: ThemeResource = null

## 当前结果字符串
var _result: String = ""

@onready var _result_label: Label = $Center/Panel/VBox/ResultLabel
@onready var _anim_sprite: AnimatedSprite2D = $Center/Panel/VBox/AnimWrap/AnimSprite
@onready var _restart_button: Button = $Center/Panel/VBox/ButtonRow/RestartButton
@onready var _menu_button: Button = $Center/Panel/VBox/ButtonRow/MenuButton
@onready var _replay_button: Button = $Center/Panel/VBox/ButtonRow/ReplayButton

func _ready() -> void:
	_restart_button.pressed.connect(func(): restart_pressed.emit())
	_menu_button.pressed.connect(func(): menu_pressed.emit())
	_replay_button.pressed.connect(func(): replay_pressed.emit())
	hide()

## 显示结算
## result: GameController.check_game_over 返回的 Dictionary
## theme: 当前 ThemeResource（用于播放 victory_anim / defeat_anim）
## 玩家方为红方：result == "red_win" → 玩家胜 → 播放 victory_anim；
##               result == "black_win" → 玩家败 → 播放 defeat_anim；
##               result == "draw" → 和棋 → 默认显示和棋文字，不播动画
func show_result(result: Dictionary, theme: ThemeResource) -> void:
	_theme = theme
	_result = String(result.get("result", ""))
	show()
	_apply_result_text()
	_play_result_anim()

## 设置玩家方（用于判定胜负归属），默认红方为玩家方
## 若需支持玩家执黑，由上层扩展本类
func _apply_result_text() -> void:
	match _result:
		"red_win":
			_result_label.text = "胜利！"
		"black_win":
			_result_label.text = "战败…"
		"draw":
			_result_label.text = "和棋"
		_:
			_result_label.text = "对局结束"

## 根据胜负播放对应全队动画（E7：胜利/战败触发对应全队动画 + 音效）
## 音效由视觉层在 animation_finished 时或同一帧触发（本类不直接播放音效）
func _play_result_anim() -> void:
	if _theme == null or _anim_sprite == null:
		return
	match _result:
		"red_win":
			if _theme.victory_anim != null:
				_anim_sprite.sprite_frames = _theme.victory_anim
				_anim_sprite.play("victory")
		"black_win":
			if _theme.defeat_anim != null:
				_anim_sprite.sprite_frames = _theme.defeat_anim
				_anim_sprite.play("defeat")
		# 和棋不播动画

## 隐藏结算面板
func hide_panel() -> void:
	if _anim_sprite != null:
		_anim_sprite.stop()
	hide()
