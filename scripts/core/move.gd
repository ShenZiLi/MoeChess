## 走法值对象（from + to + 可空 captured）
## 关联：scripts/core/piece.gd、docs/plans/2026-07-28-moechess-design.md §3.3
class_name Move
extends RefCounted

var from_col: int
var from_row: int
var to_col: int
var to_row: int
var captured: Piece   # 可空（无吃子）
var moved_piece: Piece  # 走动的棋子快照（便于复盘/动画）
var is_check: bool      # 走完后是否将军对方（用于复盘标记）
var notation: String    # 可选记谱文本（暂留空，后续可扩展标准记谱法）

func _init(p_from_col: int = 0, p_from_row: int = 0, p_to_col: int = 0, p_to_row: int = 0, p_piece: Piece = null, p_captured: Piece = null) -> void:
	from_col = p_from_col
	from_row = p_from_row
	to_col = p_to_col
	to_row = p_to_row
	moved_piece = p_piece
	captured = p_captured
	is_check = false

func from_pos() -> Vector2i:
	return Vector2i(from_col, from_row)

func to_pos() -> Vector2i:
	return Vector2i(to_col, to_row)

func is_capture() -> bool:
	return captured != null

func equals(other: Move) -> bool:
	if other == null:
		return false
	return from_col == other.from_col and from_row == other.from_row and to_col == other.to_col and to_row == other.to_row

func _to_string() -> String:
	var cap_str: String = ""
	if captured != null:
		cap_str = "x%s" % [captured]
	return "(%d,%d)->(%d,%d)%s" % [from_col, from_row, to_col, to_row, cap_str]

func to_dict() -> Dictionary:
	var d: Dictionary = {
		"from_col": from_col,
		"from_row": from_row,
		"to_col": to_col,
		"to_row": to_row,
		"is_check": is_check,
		"notation": notation,
	}
	if moved_piece != null:
		d["piece"] = moved_piece.to_dict()
	if captured != null:
		d["captured"] = captured.to_dict()
	return d

static func from_dict(d: Dictionary) -> Move:
	var mv: Move = Move.new(int(d.get("from_col", 0)), int(d.get("from_row", 0)), int(d.get("to_col", 0)), int(d.get("to_row", 0)))
	if d.has("piece"):
		mv.moved_piece = Piece.from_dict(d["piece"])
	if d.has("captured"):
		mv.captured = Piece.from_dict(d["captured"])
	mv.is_check = bool(d.get("is_check", false))
	mv.notation = String(d.get("notation", ""))
	return mv
