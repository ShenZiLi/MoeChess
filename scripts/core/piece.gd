## 棋子值对象（不可变）
## 关联：scripts/core/constants.gd、docs/plans/2026-07-28-moechess-design.md §3.3
class_name Piece
extends RefCounted

var type: int        # CoreConstants.PieceType
var side: int        # CoreConstants.Side
var col: int
var row: int

func _init(p_type: int = CoreConstants.PieceType.PAWN, p_side: int = CoreConstants.Side.RED, p_col: int = 0, p_row: int = 0) -> void:
	type = p_type
	side = p_side
	col = p_col
	row = p_row

## 不可变复制（返回新对象，便于 AI 搜索分支）
func duplicate_at(p_col: int, p_row: int) -> Piece:
	return Piece.new(type, side, p_col, p_row)

func pos() -> Vector2i:
	return Vector2i(col, row)

func equals(other: Piece) -> bool:
	if other == null:
		return false
	return type == other.type and side == other.side and col == other.col and row == other.row

func to_dict() -> Dictionary:
	return {
		"type": type,
		"side": side,
		"col": col,
		"row": row,
	}

static func from_dict(d: Dictionary) -> Piece:
	return Piece.new(int(d.get("type", CoreConstants.PieceType.PAWN)), int(d.get("side", CoreConstants.Side.RED)), int(d.get("col", 0)), int(d.get("row", 0)))

func _to_string() -> String:
	return "%s_%s(%d,%d)" % [CoreConstants.SIDE_TO_KEY.get(side, "?"), CoreConstants.TYPE_TO_KEY.get(type, "?"), col, row]
