## 图鉴面板（验收 3.6 辅助功能 / 设计 §4.2 职务道具）
## 关联：scripts/theme/theme_resource.gd、scripts/core/constants.gd、
##       docs/plans/2026-07-28-moechess-design.md §4.2（道具→棋子对照）、§7.1
##
## 展示当前皮肤的"道具 → 棋子"对照（皇冠=将、盾牌=士、象鼻帽=象、木马=马、战车=车、炮筒=炮、兵帽=兵）。
## 首次进入显示一行引导文字（设计 §4.2 末段："游戏内配图鉴页展示道具→棋子对照，首次进入引导一次"）。
## 上层订阅 back_pressed 返回上一状态（MainMenu 或 Settings）。
##
## 本面板只读；道具图标贴图由视觉层后续接入，这里先用文字 + 占位色块表达，确保数据流正确。
class_name CodexPanel
extends Control

## 选"返回"
signal back_pressed()

## 跨皮肤统一的职务道具名称（与设计 §4.2 表格一致）
## 用于在不依赖贴图时显示文字版对照
const PROP_NAMES: Dictionary = {
	CoreConstants.PieceType.KING: "皇冠",
	CoreConstants.PieceType.ADVISOR: "盾牌",
	CoreConstants.PieceType.ELEPHANT: "象鼻帽",
	CoreConstants.PieceType.HORSE: "木马",
	CoreConstants.PieceType.CHARIOT: "战车",
	CoreConstants.PieceType.CANNON: "炮筒",
	CoreConstants.PieceType.PAWN: "兵帽",
}

## 棋子类型中文名（仅显示用）
const PIECE_CN: Dictionary = {
	CoreConstants.PieceType.KING: "将/帅",
	CoreConstants.PieceType.ADVISOR: "士",
	CoreConstants.PieceType.ELEPHANT: "象",
	CoreConstants.PieceType.HORSE: "马",
	CoreConstants.PieceType.CHARIOT: "车",
	CoreConstants.PieceType.CANNON: "炮",
	CoreConstants.PieceType.PAWN: "兵/卒",
}

## 当前主题
var _theme: ThemeResource = null

## 是否首次进入（用于显示引导文字）
var _first_visit: bool = true

@onready var _hint_label: Label = $VBox/HintLabel
@onready var _grid: GridContainer = $VBox/Scroll/Grid
@onready var _back_button: Button = $VBox/BackButton

func _ready() -> void:
	_back_button.pressed.connect(func(): back_pressed.emit())
	_build_grid()

## 设置当前主题，刷新道具→棋子对照（含皮肤专属品种名）
## 注意：函数名不能是 set_theme——会覆盖 Control.set_theme(Theme) 属性 setter
func set_theme_resource(theme: ThemeResource) -> void:
	_theme = theme
	_build_grid()

## 标记已访问过（上层在用户首次离开后调用，下次进入不再显示引导文字）
func mark_visited() -> void:
	_first_visit = false

## 构建道具→棋子对照网格
## 每行 2 列：[道具名 + 棋子名 + 皮肤品种名（若 piece_mapping 提供）]
func _build_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	# 列标题
	_grid.add_child(_make_cell("道具"))
	_grid.add_child(_make_cell("棋子"))
	_grid.add_child(_make_cell("本皮肤品种"))
	for pt in [CoreConstants.PieceType.KING, CoreConstants.PieceType.ADVISOR, CoreConstants.PieceType.ELEPHANT,
			CoreConstants.PieceType.HORSE, CoreConstants.PieceType.CHARIOT, CoreConstants.PieceType.CANNON,
			CoreConstants.PieceType.PAWN]:
		_grid.add_child(_make_cell(String(PROP_NAMES.get(pt, "?"))))
		_grid.add_child(_make_cell(String(PIECE_CN.get(pt, "?"))))
		_grid.add_child(_make_cell(_lookup_piece_label(pt)))
	# 引导文字（首次进入显示）
	if _hint_label != null:
		_hint_label.text = "道具 → 棋子对照：同种道具在不同皮肤下对应同种棋子，学一次通吃 6 类皮肤。" if _first_visit else ""

## 从当前 theme.piece_mapping 反查品种名（key=品种名, value=棋子类型字符串）
## piece_mapping 形如 {"布偶": "king", "英短": "chariot", ...}
func _lookup_piece_label(pt: int) -> String:
	if _theme == null or _theme.piece_mapping == null:
		return "—"
	var type_key: String = String(CoreConstants.TYPE_TO_KEY.get(pt, ""))
	for breed in _theme.piece_mapping.keys():
		if String(_theme.piece_mapping[breed]) == type_key:
			return String(breed)
	return "—"

## 工厂：构造一个简单 Label 单元格
func _make_cell(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
