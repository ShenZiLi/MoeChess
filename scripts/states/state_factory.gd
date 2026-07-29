## 状态对象工厂（RefCounted）
## 关联：docs/plans/2026-07-28-moechess-design.md §7
##
## 职责：集中创建各状态对象，便于后续扩展（如 Replay 状态、自定义状态等）。
## 当前主要创建 PlayingState 及其依赖；其他全局状态由 GameStateMachine 用字符串标识。
##
## 使用方式：
##   var ps := StateFactory.create_playing_state(ai_worker)
##   var aw := StateFactory.create_ai_worker()
class_name StateFactory
extends RefCounted

## 创建 PlayingState 子状态机
## ai_worker: 可选，注入 AI Worker；为 null 时 PlayingState 无法启动 AI 计算
## 返回的 PlayingState 需由调用方设置 game_mode / difficulty 后调用 enter(state)
static func create_playing_state(ai_worker: AIWorker = null) -> PlayingState:
	var ps: PlayingState = PlayingState.new()
	if ai_worker != null:
		ps.set_ai_worker(ai_worker)
	return ps

## 创建 AIWorker 节点（供 GameStateMachine 持有为子节点）
static func create_ai_worker() -> AIWorker:
	return AIWorker.new()

## 创建 BoardState 初始局面
static func create_initial_board_state() -> BoardState:
	return BoardState.initial()

## 创建 InputProvider 节点（供 view/ui 层挂到场景树）
static func create_input_provider() -> InputProvider:
	return InputProvider.new()

## 创建 PlatformConfig 实例
static func create_platform_config() -> PlatformConfig:
	return PlatformConfig.new()

## 根据模式枚举返回对应的难度
## PVE_LOW → LOW, PVE_MEDIUM → MEDIUM, PVE_HIGH → HIGH, PVP → LOW（不用 AI）
static func difficulty_for_mode(mode: int) -> int:
	match mode:
		GameStateMachine.GameMode.PVE_LOW:
			return CoreConstants.Difficulty.LOW
		GameStateMachine.GameMode.PVE_MEDIUM:
			return CoreConstants.Difficulty.MEDIUM
		GameStateMachine.GameMode.PVE_HIGH:
			return CoreConstants.Difficulty.HIGH
		_:
			return CoreConstants.Difficulty.LOW
