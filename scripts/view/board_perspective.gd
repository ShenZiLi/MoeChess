## 2.5D 棋盘透视计算（纯数学，零节点依赖）
## 关联：docs/plans/2026-07-28-moechess-design.md §6.2、§6.4
##       docs/development/acceptance-standard.md D1/D2/D6/D7
##
## 负责 board 坐标 (col, row) ⇄ screen 坐标 (x, y) 的双向映射，以及
## 每行棋子的程序化透视缩放与 Y 偏移。所有计算基于一个梯形视体：
##   - 近边（near，scale=1.0）：屏幕底部，宽度大
##   - 远边（far，scale=0.75）：屏幕顶部，宽度小
## 翻转视角（双人对战换边）时，row 0↔row 9 互换远近，但棋盘整体方向不旋转。
##
## 坐标系约定（与 board_player.png / board_opponent.png 占位图保持一致）：
##   - 原点在 BoardView 节点本地坐标系左上角
##   - x 向右增大，y 向下增大
##   - 棋盘背景图尺寸 = BG_W × BG_H
class_name BoardPerspective
extends RefCounted

## 棋盘背景图宽度（与 assets/board/board_*.png 占位图一致）
const BG_W: int = 1080

## 棋盘背景图高度
const BG_H: int = 1280

## 棋盘水平中心 X
const CENTER_X: float = float(BG_W) / 2.0

## 近边（屏幕底部）Y 坐标
const NEAR_Y: float = 1220.0

## 远边（屏幕顶部）Y 坐标
const FAR_Y: float = 60.0

## 近边半宽（左右各距离中心）
const NEAR_HALF_WIDTH: float = 496.0

## 远边半宽
const FAR_HALF_WIDTH: float = 345.0

## 近边缩放
const SCALE_NEAR: float = 1.0

## 远边缩放
const SCALE_FAR: float = 0.75

## row 0 透视深度 t（玩家视角：row0=near=0.0；对手视角：row0=far=1.0）
## t = 0 → 近边；t = 1 → 远边
static func t_at_row(row: int, flipped: bool) -> float:
	var frow: float = clampf(float(row), 0.0, float(CoreConstants.ROWS - 1))
	var t: float = frow / float(CoreConstants.ROWS - 1)
	if flipped:
		t = 1.0 - t
	return t

## 给定 t（0=near, 1=far）返回行中心 Y 坐标
static func y_at_t(t: float) -> float:
	var tt: float = clampf(t, 0.0, 1.0)
	return lerpf(NEAR_Y, FAR_Y, tt)

## 给定 t 返回行半宽
static func half_width_at_t(t: float) -> float:
	var tt: float = clampf(t, 0.0, 1.0)
	return lerpf(NEAR_HALF_WIDTH, FAR_HALF_WIDTH, tt)

## 给定 t 返回该行的棋子缩放（D2：row 0→1.0，row 9→0.75）
static func scale_at_t(t: float) -> float:
	var tt: float = clampf(t, 0.0, 1.0)
	return lerpf(SCALE_NEAR, SCALE_FAR, tt)

## row 0→1.0，row 9→0.75（玩家视角）；翻转后 row 0→0.75，row 9→1.0
## 满足验收 D2：棋子按所在 row 计算缩放
static func scale_at_row(row: int, flipped: bool) -> float:
	return scale_at_t(t_at_row(row, flipped))

## 返回该行中心 Y 坐标（D2：Y 偏移随 row 递减体现近大远小）
static func y_offset_at_row(row: int, flipped: bool) -> float:
	return y_at_t(t_at_row(row, flipped))

## 返回 (col, row) 在屏幕上的中心坐标（D6：board_to_screen）
## col 范围 0..8，row 范围 0..9
static func board_to_screen(pos: Vector2i, flipped: bool) -> Vector2:
	var col: int = clampi(pos.x, 0, CoreConstants.COLS - 1)
	var row: int = clampi(pos.y, 0, CoreConstants.ROWS - 1)
	var t: float = t_at_row(row, flipped)
	var half: float = half_width_at_t(t)
	var cy: float = y_at_t(t)
	# col 0..8 映射到 [-half, +half]
	var col_ratio: float = float(col) / float(CoreConstants.COLS - 1) * 2.0 - 1.0
	var x: float = CENTER_X + half * col_ratio
	return Vector2(x, cy)

## 屏幕坐标反查棋盘坐标（D6/D7：点击命中）
## 算法：
##   1. 由 y 求出 t（梯形纵向比例），进而得 half_width、cy；
##   2. 由 x 与中心偏差除以当前 half_width 求 col_ratio；
##   3. 由 t 反求 row（依赖 flipped）；
##   4. 若 col_ratio 超出 [-1, 1] 或 t 越界则视为点击空白。
static func screen_to_board(point: Vector2, flipped: bool) -> Vector2i:
	# 1. t 由 y 求出
	var t: float = (NEAR_Y - point.y) / (NEAR_Y - FAR_Y)
	t = clampf(t, 0.0, 1.0)
	# 2. 当前行半宽
	var half: float = half_width_at_t(t)
	# 3. col_ratio
	var col_ratio: float = (point.x - CENTER_X) / half
	var col_f: float = (col_ratio + 1.0) * 0.5 * float(CoreConstants.COLS - 1)
	var col: int = roundi(col_f)
	# 4. row 由 t 反推
	var row_f: float = t * float(CoreConstants.ROWS - 1)
	if flipped:
		row_f = float(CoreConstants.ROWS - 1) - row_f
	var row: int = roundi(row_f)
	# 越界返回 (-1, -1) 作为哨兵，由调用方判断
	if col < 0 or col >= CoreConstants.COLS:
		return Vector2i(-1, -1)
	if row < 0 or row >= CoreConstants.ROWS:
		return Vector2i(-1, -1)
	# 容差检查：col_ratio 越界过多视为点空白（点击命中准确 D7）
	if absf(col_ratio) > 1.15:
		return Vector2i(-1, -1)
	if t < -0.05 or t > 1.05:
		return Vector2i(-1, -1)
	return Vector2i(col, row)

## 返回棋盘背景图可视尺寸（供 BoardView 摆放背景 Sprite 用）
static func board_bg_size() -> Vector2i:
	return Vector2i(BG_W, BG_H)
