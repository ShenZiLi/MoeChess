## 置换表（Zobrist hashing 缓存已搜局面）
## 关联：docs/plans/2026-07-28-moechess-design.md §5.3、docs/development/acceptance-standard.md B8
##
## 设计：
## - Zobrist hashing：7 棋子类型 × 2 阵营 × 90 位置 = 1260 个 64 位随机数 + side_to_move 1 个
## - 用固定种子生成（保证可复现）
## - flag: EXACT（精确值）/ LOWER_BOUND（下界，beta 截断）/ UPPER_BOUND（上界，alpha 截断）
##
## lookup 语义：
## - found=true 仅当缓存项 depth >= 查询 depth（score 可直接使用）
## - found=false 时仍可能返回 best_move（用于走法排序提示，depth 不足但走法仍有效）
## - hit_count 只要 hash 命中即 +1（无论 depth 是否足够）
class_name TranspositionTable
extends RefCounted

## 置换表项 flag 枚举
enum Flag { EXACT, LOWER_BOUND, UPPER_BOUND }

const PT = CoreConstants.PieceType
const SD = CoreConstants.Side
const _NUM_TYPES: int = 7
const _NUM_SIDES: int = 2
const _NUM_CELLS: int = CoreConstants.ROWS * CoreConstants.COLS  # 90
const _PIECE_ARRAY_SIZE: int = _NUM_TYPES * _NUM_SIDES * _NUM_CELLS  # 1260

## Zobrist 随机数表（扁平数组，索引 = t*180 + s*90 + r*9 + c）
static var _zobrist_pieces: Array = []
## side_to_move 的随机数（_zobrist_side[side]）
static var _zobrist_side: Array = []
static var _initialized: bool = false

## 主存储：Dictionary[hash] = {depth, score, flag, best_move}
var _table: Dictionary = {}
## 哈希命中计数（测试断言用）
var hit_count: int = 0

## 静态初始化：用固定种子生成 Zobrist 随机数（类首次使用时调用一次）
static func _static_init() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# 固定种子 0x4D6F6543 = "MoeC"，保证可复现
	rng.seed = 0x4D6F6543
	_zobrist_pieces.resize(_PIECE_ARRAY_SIZE)
	for t in range(_NUM_TYPES):
		for s in range(_NUM_SIDES):
			for r in range(CoreConstants.ROWS):
				for c in range(CoreConstants.COLS):
					_zobrist_pieces[_zobrist_index(t, s, r, c)] = _rand64(rng)
	_zobrist_side.resize(_NUM_SIDES)
	for s in range(_NUM_SIDES):
		_zobrist_side[s] = _rand64(rng)
	_initialized = true

## 扁平索引：t=type(0..6), s=side(0..1), r=row(0..9), c=col(0..8)
static func _zobrist_index(t: int, s: int, r: int, c: int) -> int:
	return t * (_NUM_SIDES * _NUM_CELLS) + s * _NUM_CELLS + r * CoreConstants.COLS + c

## 生成 64 位随机数（GDScript int 是 64 位有符号，XOR 运算不关心符号）
static func _rand64(rng: RandomNumberGenerator) -> int:
	var hi: int = rng.randi()
	var lo: int = rng.randi()
	return (hi << 32) | lo

## 计算 BoardState 的 Zobrist hash
## hash = XOR(所有棋子的 type×side×位置 随机数) XOR side_to_move 随机数
func compute_hash(state: BoardState) -> int:
	var h: int = 0
	for r in range(CoreConstants.ROWS):
		var row_arr: Array = state.grid[r]
		for c in range(CoreConstants.COLS):
			var p: Piece = row_arr[c]
			if p != null:
				h = h ^ _zobrist_pieces[_zobrist_index(p.type, p.side, r, c)]
	h = h ^ _zobrist_side[state.side_to_move]
	return h

## 存储置换表项
func store(hash: int, depth: int, score: int, flag: int, best_move: Move) -> void:
	_table[hash] = {
		"depth": depth,
		"score": score,
		"flag": flag,
		"best_move": best_move,
	}

## 查询置换表
## 返回 {found: bool, score: int, flag: int, best_move: Move}
## - found=true：缓存项 depth >= 查询 depth，score 可直接使用
## - found=false：depth 不足或未命中；best_move 可能为非空（用于走法排序提示）
func lookup(hash: int, depth: int) -> Dictionary:
	if not _table.has(hash):
		return {"found": false, "score": 0, "flag": Flag.EXACT, "best_move": null}
	hit_count += 1
	var entry: Dictionary = _table[hash]
	if entry["depth"] >= depth:
		return {
			"found": true,
			"score": int(entry["score"]),
			"flag": int(entry["flag"]),
			"best_move": entry["best_move"],
		}
	return {
		"found": false,
		"score": 0,
		"flag": int(entry["flag"]),
		"best_move": entry["best_move"],
	}

## 清空置换表（重置命中计数）
func clear() -> void:
	_table.clear()
	hit_count = 0

## 表项数量
func size() -> int:
	return _table.size()
