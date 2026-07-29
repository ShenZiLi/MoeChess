## 核心层常量与枚举（纯逻辑，零渲染依赖）
## 关联：scripts/core/*.gd、docs/plans/2026-07-28-moechess-design.md §3.2
##
## 注意：保留 class_name CoreConstants——本脚本非 autoload，class_name 是
## 全局访问入口；所有 CoreConstants.xxx 调用依赖此声明，不可删除。
class_name CoreConstants
extends RefCounted

# 棋子类型（遵循"状态机用枚举"规范）
enum PieceType { KING, ADVISOR, ELEPHANT, HORSE, CHARIOT, CANNON, PAWN }

# 阵营
enum Side { RED, BLACK }

# 棋盘尺寸：9 列 × 10 行
const COLS: int = 9
const ROWS: int = 10

# 红方区域 row 0-4（玩家方/下方）；黑方区域 row 5-9（电脑方/上方）
const RED_HOME_ROWS: Array[int] = [0, 1, 2, 3, 4]
const BLACK_HOME_ROWS: Array[int] = [5, 6, 7, 8, 9]

# 九宫范围（红方 row 0-2 / cols 3-5；黑方 row 7-9 / cols 3-5）
const PALACE_COLS: Array[int] = [3, 4, 5]
const RED_PALACE_ROWS: Array[int] = [0, 1, 2]
const BLACK_PALACE_ROWS: Array[int] = [7, 8, 9]

# 河界：红方 row 4 南岸；黑方 row 5 北岸
const RED_RIVER_ROW: int = 4
const BLACK_RIVER_ROW: int = 5

# 子力价值（经典中国象棋估值，对应 docs §5.2）
const PIECE_VALUE: Dictionary = {
	PieceType.KING: 10000,
	PieceType.ADVISOR: 200,
	PieceType.ELEPHANT: 200,
	PieceType.HORSE: 400,
	PieceType.CHARIOT: 900,
	PieceType.CANNON: 450,
	PieceType.PAWN: 100,
}

# 棋子类型 → 字符串键名（与 assets/themes 命名一致）
const TYPE_TO_KEY: Dictionary = {
	PieceType.KING: "king",
	PieceType.ADVISOR: "advisor",
	PieceType.ELEPHANT: "elephant",
	PieceType.HORSE: "horse",
	PieceType.CHARIOT: "chariot",
	PieceType.CANNON: "cannon",
	PieceType.PAWN: "pawn",
}

# 阵营 → 字符串键名
const SIDE_TO_KEY: Dictionary = {
	Side.RED: "red",
	Side.BLACK: "black",
}

# 棋子 5 动画状态（与 SpriteFrames 命名一致）
enum AnimState { IDLE, SELECTED, MOVING, KILLING, KILLED }

const ANIM_STATE_TO_KEY: Dictionary = {
	AnimState.IDLE: "idle",
	AnimState.SELECTED: "selected",
	AnimState.MOVING: "moving",
	AnimState.KILLING: "killing",
	AnimState.KILLED: "killed",
}

# 难度（AI 三档）
enum Difficulty { LOW, MEDIUM, HIGH }

# 加速倍率
enum SpeedMode { NORMAL, FAST }
const SPEED_SCALE: Dictionary = {
	SpeedMode.NORMAL: 1.0,
	SpeedMode.FAST: 2.0,
}

# 长将判和的连续将军回合数阈值
const PERPETUAL_CHECK_LIMIT: int = 6

## 工具：阵营取反
static func opponent(side: int) -> int:
	return Side.BLACK if side == Side.RED else Side.RED

## 工具：坐标是否在棋盘内
static func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < COLS and row >= 0 and row < ROWS

## 工具：坐标是否在指定阵营九宫内
static func in_palace(col: int, row: int, side: int) -> bool:
	if not PALACE_COLS.has(col):
		return false
	if side == Side.RED:
		return RED_PALACE_ROWS.has(row)
	return BLACK_PALACE_ROWS.has(row)

## 工具：坐标是否在己方半场（未过河）
## 注意：本函数不依赖 col，仅按 row 判断半场；保留 col 参数以对齐其他工具函数签名
static func in_home_half(_col: int, row: int, side: int) -> bool:
	if side == Side.RED:
		return row <= RED_RIVER_ROW
	return row >= BLACK_RIVER_ROW

## 工具：阵营的"前进方向"（row 增量）
## 设计约定：row 0 = 红方底线（玩家方/下方），row 9 = 黑方底线（电脑方/上方）
## 红方在 row 0-4，向 row 5-9（黑方半场）推进 → forward = +1
## 黑方在 row 5-9，向 row 0-4（红方半场）推进 → forward = -1
static func forward(side: int) -> int:
	return 1 if side == Side.RED else -1

## 工具：兵是否已过河（进入对方半场）
static func pawn_crossed_river(row: int, side: int) -> bool:
	if side == Side.RED:
		return row > RED_RIVER_ROW  # 红方过河 = 进入黑方半场 row >= 5
	return row < BLACK_RIVER_ROW  # 黑方过河 = 进入红方半场 row <= 4
