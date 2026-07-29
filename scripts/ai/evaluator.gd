## AI 评估函数（子力 + 位置表 + 机动性 + 威胁 + 防御）
## 关联：docs/plans/2026-07-28-moechess-design.md §5.2、docs/development/acceptance-standard.md B1-B3
##
## 难度梯度（由 SearchEngine 通过 set_difficulty 切换）：
## - LOW：仅子力评估
## - MEDIUM：子力 + 位置表
## - HIGH：子力 + 位置表 + 机动性 + 威胁 + 防御
##
## 评估从 side 视角返回分（己方加分，对方减分）。
## 位置表为红方视角（row 0 = 红方底线），黑方按 row 镜像查同一张表。
class_name Evaluator
extends RefCounted

const PT = CoreConstants.PieceType
const SD = CoreConstants.Side
const DF = CoreConstants.Difficulty

## 位置表（红方视角，row 0 = 红方底线，row 9 = 黑方底线）
## 每行 9 个整数（col 0..8），10 行（row 0..9），用空白分隔
# 将/帅：鼓励守九宫深处，惩罚前出
const PST_KING: String = """
1 0 1 0 2 0 1 0 1
0 0 0 1 3 1 0 0 0
0 0 0 0 -5 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
"""
# 士：鼓励在九宫中行
const PST_ADVISOR: String = """
0 0 0 0 0 0 0 0 0
0 0 0 0 3 0 0 0 0
0 0 0 2 0 2 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
"""
# 象：本区田字位
const PST_ELEPHANT: String = """
0 0 2 0 0 0 2 0 0
0 0 0 0 0 0 0 0 0
2 0 0 0 3 0 0 0 2
0 0 0 0 0 0 0 0 0
2 0 0 0 2 0 0 0 2
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
"""
# 马：卧槽位 + 中心
const PST_HORSE: String = """
4 0 0 0 0 0 0 0 4
0 0 0 0 0 0 0 0 0
0 0 4 0 6 0 4 0 0
0 0 0 0 0 0 0 0 0
0 2 0 4 0 4 0 2 0
0 2 0 4 0 4 0 2 0
0 0 4 0 6 0 4 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
4 0 0 0 0 0 0 0 4
"""
# 车：底线 + 巡河
const PST_CHARIOT: String = """
6 0 0 0 0 0 0 0 6
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 2 0 0 0 2 0 0
0 0 2 0 0 0 2 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
6 0 0 0 0 0 0 0 6
"""
# 炮：中央 + 巡河
const PST_CANNON: String = """
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 6 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 2 0 0 0 2 0 0
0 0 2 0 0 0 2 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
"""
# 兵：过河后大幅加分（红方过河 = row 5..9）
const PST_PAWN: String = """
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0
9 9 9 11 13 11 9 9 9
9 9 9 11 13 11 9 9 9
9 9 9 11 13 11 9 9 9
9 9 9 11 13 11 9 9 9
9 9 9 11 13 11 9 9 9
"""

## 解析后的位置表（红方视角）：_pst_red[type] = Array[Array[int]]，[row][col]
static var _pst_red: Dictionary = {}

## 当前评估难度
var _difficulty: int = DF.LOW

## 权重常量
const MOBILITY_WEIGHT: int = 5
const THREAT_WEIGHT: float = 0.5
const DEFENSE_WEIGHT: float = 0.15

## 静态初始化：解析位置表字符串为二维数组（类首次使用时调用一次）
static func _static_init() -> void:
	_pst_red[PT.KING] = _parse_pst(PST_KING)
	_pst_red[PT.ADVISOR] = _parse_pst(PST_ADVISOR)
	_pst_red[PT.ELEPHANT] = _parse_pst(PST_ELEPHANT)
	_pst_red[PT.HORSE] = _parse_pst(PST_HORSE)
	_pst_red[PT.CHARIOT] = _parse_pst(PST_CHARIOT)
	_pst_red[PT.CANNON] = _parse_pst(PST_CANNON)
	_pst_red[PT.PAWN] = _parse_pst(PST_PAWN)

## 解析位置表字符串为二维数组 [row][col]
## 用 split(" ", false) 拆分：allow_empty=false 自动丢弃连续空白产生的空字段
static func _parse_pst(s: String) -> Array:
	var rows: PackedStringArray = s.strip_edges().split("\n")
	var table: Array = []
	for row_str in rows:
		var trimmed: String = row_str.strip_edges()
		if trimmed.is_empty():
			continue
		var cells: PackedStringArray = trimmed.split(" ", false)
		var row_arr: Array = []
		for cell in cells:
			row_arr.append(int(cell))
		table.append(row_arr)
	return table

## 设置评估难度（影响评估精度：LOW 仅子力；MEDIUM 加位置表；HIGH 加机动性/威胁/防御）
func set_difficulty(difficulty: int) -> void:
	_difficulty = difficulty

## 主评估函数：返回 side 视角的局面分（己方加分，对方减分）
func evaluate(state: BoardState, side: int) -> int:
	var opp: int = CoreConstants.opponent(side)
	var score: int = 0
	var use_position: bool = _difficulty >= DF.MEDIUM
	var use_advanced: bool = _difficulty >= DF.HIGH

	# 子力 + 位置表
	var my_pieces: Array = state.pieces_of(side)
	var opp_pieces: Array = state.pieces_of(opp)
	for p in my_pieces:
		score += int(CoreConstants.PIECE_VALUE.get(p.type, 0))
		if use_position:
			score += _pst_value(p, side)
	for p in opp_pieces:
		score -= int(CoreConstants.PIECE_VALUE.get(p.type, 0))
		if use_position:
			score -= _pst_value(p, opp)

	# 高难度额外项：机动性 + 威胁/防御
	if use_advanced:
		score += _mobility_score(state, side)
		score += _threat_defense_score(state, side)

	return score

## 取位置表加分（红方直接查，黑方按 row 镜像查同一张表）
func _pst_value(p: Piece, side: int) -> int:
	var table: Array = _pst_red.get(p.type, [])
	if table.is_empty():
		return 0
	var row: int = p.row
	if side == SD.BLACK:
		row = CoreConstants.ROWS - 1 - p.row
	if row < 0 or row >= table.size():
		return 0
	var row_arr: Array = table[row]
	if p.col < 0 or p.col >= row_arr.size():
		return 0
	return int(row_arr[p.col])

## 机动性分：双方伪走法数差 × 权重（HIGH 难度项）
func _mobility_score(state: BoardState, side: int) -> int:
	var opp: int = CoreConstants.opponent(side)
	var my_moves: int = MoveGenerator.generate_all_pseudo_moves(state, side).size()
	var opp_moves: int = MoveGenerator.generate_all_pseudo_moves(state, opp).size()
	return (my_moves - opp_moves) * MOBILITY_WEIGHT

## 威胁 + 防御分（HIGH 难度项）
## 威胁：扫描对方伪走法，取最大可吃子价值，按 THREAT_WEIGHT 惩罚
## 防御：扫描己方伪走法中带 capture 的走法（反威胁潜力），按 DEFENSE_WEIGHT 加分
## 真正的"保护己方子"由 minimax 深度搜索自然体现，此处用反威胁近似
func _threat_defense_score(state: BoardState, side: int) -> int:
	var opp: int = CoreConstants.opponent(side)
	var score: int = 0

	# 威胁：对方下一步能吃我方子的最大价值
	var opp_moves: Array = MoveGenerator.generate_all_pseudo_moves(state, opp)
	var threatened_value: int = 0
	for m in opp_moves:
		if m.captured != null:
			var v: int = int(CoreConstants.PIECE_VALUE.get(m.captured.type, 0))
			if v > threatened_value:
				threatened_value = v
	score -= int(threatened_value * THREAT_WEIGHT)

	# 防御：己方能吃对方子的潜力（反威胁），累计 captured 价值
	var my_moves: Array = MoveGenerator.generate_all_pseudo_moves(state, side)
	var defense_value: int = 0
	for m in my_moves:
		if m.captured != null:
			defense_value += int(CoreConstants.PIECE_VALUE.get(m.captured.type, 0))
	score += int(defense_value * DEFENSE_WEIGHT)

	return score
