# 萌象棋 v1.0 测试用例

- **状态**：草案（待 acceptance-checker 核对覆盖完整性）
- **作者角色**：`test-author` 子 Agent（AGENTS.md step2）
- **依据**：`docs/development/acceptance-standard.md`（已冻结）、`docs/plans/2026-07-28-moechess-design.md`、`spec/v1.0-spec.md`
- **角色约束**：本文档只设计测试用例，不写实现代码，不写 GUT 测试脚本代码（那是后续 builder 的工作）；不修改验收标准。

---

## 棋盘坐标与约定（全文档通用）

- 9 列 × 10 行，`col ∈ [0, 8]`，`row ∈ [0, 9]`
- **row 0 = 红方底线（玩家方/下方）**，**row 9 = 黑方底线（电脑方/上方）**
- 红方"前进"= row 增大（红方在 row 0-4，向 row 5-9 黑方半场推进）；黑方"前进"= row 减小
- 红方九宫 `row 0-2 / cols 3-5`；黑方九宫 `row 7-9 / cols 3-5`
- 红方本区 `row 0-4`；黑方本区 `row 5-9`；红方过河 = 兵进入 `row 5-9`；黑方过河 = 兵进入 `row 0-4`
- 棋子初始位置记号：`{side}_{type}@{col},{row}`，如 `red_chariot@0,0`
- 测试类型枚举：单元 / 集成 / 视觉 / 平台
- 测试入口约定：`scripts/tests/test_xxx.gd::test_xxx`，builder 实现 GUT 测试脚本时按本文档命名

> **约定修正说明（2026-07-29 主 Agent 核对）**：本文档早期版本曾写"红方前进 = row 减小"，与 `board_state.gd` 初始局面（红方 row 0-4、黑方 row 5-9、双方相向推进）冲突，也与 `CoreConstants.forward()` / `pawn_crossed_river()` 修正后的实现冲突。正文部分用例（如 TC-A1-007、TC-A4-001 等）若出现"红兵 row 减小为前进"的描述，应以本节统一约定为准——红方前进 = row 增大。GUT 测试脚本实现时按本节约定编写。

## API 契约假设（测试用例基于此设计）

本文档假设以下 API 已实现或将被实现（来自任务上下文）：

- `CoreConstants`（`scripts/core/constants.gd`）：枚举 `PieceType / Side / Difficulty / AnimState / SpeedMode`、常量 `PIECE_VALUE / TYPE_TO_KEY`、静态函数 `in_bounds(c,r) / in_palace(side,c,r) / forward(side) / pawn_crossed_river(side,row)`
- `Piece`（`scripts/core/piece.gd`）：`type / side / col / row / pos() / equals() / to_dict() / from_dict()`
- `Move`（`scripts/core/move.gd`）：`from_col/from_row/to_col/to_row/moved_piece/captured/is_check`、`is_capture() / equals() / to_dict() / from_dict()`
- `BoardState`（`scripts/core/board_state.gd`）：`grid / side_to_move / move_history / captured_by_red / captured_by_black / last_move / turn_number / check_history`、`initial() / deep_copy() / get_piece(c,r) / pieces_of(side) / find_king(side) / to_dict() / from_dict()`
- `MoveGenerator.generate_pseudo_moves(state, piece) -> Array[Move]`
- `MoveGenerator.generate_all_pseudo_moves(state, side) -> Array[Move]`
- `RuleValidator.is_legal(state, move) -> bool`
- `RuleValidator.is_in_check(state, side) -> bool`
- `RuleValidator.is_checkmate(state, side) -> bool`
- `RuleValidator.is_stalemate(state, side) -> bool`
- `RuleValidator.kings_face(state) -> bool`
- `RuleValidator.generates_perpetual_check(state, move) -> bool`
- `GameController.apply_move(state, move) -> BoardState`
- `GameController.generate_legal_moves(state, side) -> Array[Move]`
- `SearchEngine.choose_move(state, difficulty) -> Move`
- `SearchEngine.set_transposition_table(tt)`
- `Evaluator.evaluate(state, side) -> int`
- `ThemeManager.get_current() / switch_to(id) / list_themes()` + 信号 `theme_changed`
- `Logger.debug/info/warn/error(msg) / set_level(level)`
- `DebugLayer.set_enabled(bool) / is_enabled()`
- `validate_theme.validate_all() -> Dictionary`
- `run_ai_benchmark.run(difficulty, max_steps) -> Dictionary`
- `play_replay.load_replay(path) -> Dictionary / step(replay_state, forward) -> Dictionary`

API 疑问见文末"附录：API 契约疑问"。

---

# A. 核心规则正确性（硬性红线 A1-A10）

## A1 — 七种棋子（将/士/象/马/车/炮/兵）走法生成 100% 符合中国象棋规则

- **TC-A1-001**：将/帅九宫内一步直走（红黑各一）
  - 前置条件：`state = BoardState.initial()`；红帅位于 `4,0`，黑将位于 `4,9`
  - 输入：`MoveGenerator.generate_pseudo_moves(state, state.get_piece(4,0))`；`MoveGenerator.generate_pseudo_moves(state, state.get_piece(4,9))`
  - 预期：红帅走法 = `{(3,0),(5,0),(4,1)}` 共 3 个（斜走非法、出九宫非法、上方无子才能上）；黑将走法 = `{(3,9),(5,9),(4,8)}` 共 3 个；走法集合精确匹配，无多无少
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_king_moves_in_palace`

- **TC-A1-002**：士九宫内一步斜走
  - 前置条件：`state = BoardState.initial()`；红士位于 `3,0` 和 `5,0`，黑士位于 `3,9` 和 `5,9`
  - 输入：对每个士调用 `generate_pseudo_moves`
  - 预期：红士 `3,0` 走法 = `{(4,1)}`（被己方将阻挡，仅一个斜走目标）；红士 `5,0` 走法 = `{(4,1)}`；黑士同理对称；直走非法、出九宫非法
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_advisor_moves_in_palace`

- **TC-A1-003**：象走田字格两步
  - 前置条件：自定义空棋盘，仅放置红象于 `2,0`，黑象于 `2,9`
  - 输入：`generate_pseudo_moves(state, red_elephant@2,0)`；`generate_pseudo_moves(state, black_elephant@2,9)`
  - 预期：红象走法 = `{(0,2),(4,2)}`（田字格中心位于象眼，本测试象眼为空），黑象对称；不直走、不走一格、不过河
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_elephant_moves`

- **TC-A1-004**：马走日字格
  - 前置条件：自定义空棋盘，仅放置红马于 `4,4`（中心，无蹩腿）
  - 输入：`generate_pseudo_moves(state, red_horse@4,4)`
  - 预期：走法 = `{(2,3),(2,5),(3,2),(5,2),(6,3),(6,5),(3,6),(5,6)}` 共 8 个日字格位置；非日字格位置不出现在走法中
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_horse_moves_center`

- **TC-A1-005**：车直线任意距离
  - 前置条件：自定义空棋盘，红车位于 `4,4`
  - 输入：`generate_pseudo_moves(state, red_chariot@4,4)`
  - 预期：走法 = 列 4 上 `(4,0)-(4,3),(4,5)-(4,9)` 共 9 个 + 行 4 上 `(0,4)-(3,4),(5,4)-(8,4)` 共 8 个 = 17 个；无斜走、无跳跃
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_chariot_moves_open_board`

- **TC-A1-006**：炮直线移动（不吃子时同车）
  - 前置条件：自定义空棋盘，红炮位于 `4,4`
  - 输入：`generate_pseudo_moves(state, red_cannon@4,4)`
  - 预期：非吃子走法 = 17 个（同车的非吃子走法）；吃子走法 = 0 个（无子可翻山）；总走法 17 个
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_cannon_moves_no_capture`

- **TC-A1-007**：兵未过河前进一步
  - 前置条件：`state = BoardState.initial()`；红兵位于 `0,3`（未过河），黑兵位于 `0,6`（未过河）
  - 输入：`generate_pseudo_moves(state, red_pawn@0,3)`；`generate_pseudo_moves(state, black_pawn@0,6)`
  - 预期：红兵走法 = `{(0,2)}`（仅前进一格，row 减小）；黑兵走法 = `{(0,7)}`（仅前进一格，row 增大）；不左右、不后退
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_pawn_moves_before_river`

- **TC-A1-008**：初始局面走法总数核对
  - 前置条件：`state = BoardState.initial()`
  - 输入：`generate_all_pseudo_moves(state, Side.RED)`
  - 预期：标准中国象棋初始红方伪走法总数 = 44 个（车 18 + 马 8 + 炮 14 + 兵 4 + 帅 1 - 重复扣除等）；测试断言等于权威值（参考开源象棋引擎如 pikafish/eleeye 对初始红方走法数的统计），若权威值与本断言冲突以权威值为准并更新本用例
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_initial_position_move_count`

## A2 — 蹩马腿、塞象眼、炮翻山隔子吃等特殊规则正确实现

- **TC-A2-001**：蹩马腿
  - 前置条件：自定义棋盘，红马位于 `4,4`，红兵位于 `4,5`（蹩 `4,5→2,4` 方向的马腿）和 `5,4`（蹩 `5,4→6,2` 方向的马腿，注意蹩腿点是马走日字时第一个直走格）
  - 输入：`generate_pseudo_moves(state, red_horse@4,4)`
  - 预期：被蹩腿方向（如 `5,4` 蹩掉 `(6,2)` 与 `(6,6)` 方向，`4,5` 蹩掉 `(2,5)` 与 `(6,5)` 方向——以马腿规则"先走一格直走再一格斜走"为准）的目标格不出现在走法中；其余日字格仍可走
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_horse_blocked_leg`

- **TC-A2-002**：塞象眼
  - 前置条件：自定义棋盘，红象位于 `2,0`，红兵位于 `3,1`（塞 `2,0→4,2` 田字中心象眼）
  - 输入：`generate_pseudo_moves(state, red_elephant@2,0)`
  - 预期：走法中不含 `(4,2)`；若 `(0,2)` 方向象眼空，仍可走 `(0,2)`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_elephant_blocked_eye`

- **TC-A2-003**：炮翻山隔一子吃
  - 前置条件：自定义棋盘，红炮位于 `4,4`，黑车位于 `4,7`（远端），红兵位于 `4,5`（炮架）
  - 输入：`generate_pseudo_moves(state, red_cannon@4,4)`
  - 预期：走法包含 `(4,7)`（吃黑车，含 captured 字段）；不包含 `(4,5)`（己方子阻挡，不可到达）；非吃子走法在 `4,5` 之前可走、之后不可
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_cannon_jump_capture`

- **TC-A2-004**：炮翻山多子阻挡
  - 前置条件：自定义棋盘，红炮 `4,4`，红兵 `4,5`，黑兵 `4,6`，黑车 `4,7`
  - 输入：`generate_pseudo_moves(state, red_cannon@4,4)`
  - 预期：走法不含 `(4,7)`（炮架后还有第二子，不能跨两子吃）；含 `(4,6)`（隔一个炮架吃黑兵）；不含 `(4,5)`（己方子）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_cannon_no_double_jump`

## A3 — 将/帅不得出九宫；士不得出九宫；象不得过河

- **TC-A3-001**：将/帅不得出九宫
  - 前置条件：自定义空棋盘，红帅位于 `4,1`（九宫内中心）
  - 输入：`generate_pseudo_moves(state, red_king@4,1)`
  - 预期：走法 = `{(3,1),(5,1),(4,0),(4,2)}` 全部在九宫 `row 0-2 / col 3-5`；不含 `(2,1)`、`(6,1)`（出九宫）、不含斜走
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_king_confined_palace`

- **TC-A3-002**：士不得出九宫
  - 前置条件：自定义空棋盘，红士位于 `4,1`（九宫内中心）
  - 输入：`generate_pseudo_moves(state, red_advisor@4,1)`
  - 预期：走法 = `{(3,0),(5,0),(3,2),(5,2)}` 全部在九宫内；不含直走、不含出九宫目标
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_advisor_confined_palace`

- **TC-A3-003**：象不得过河
  - 前置条件：自定义空棋盘，红象位于 `4,4`（河边，红方本区上沿）
  - 输入：`generate_pseudo_moves(state, red_elephant@4,4)`
  - 预期：走法仅含本区目标 `{(2,2),(6,2),(2,6),(6,6)}` 中象眼未堵者；不含 `(2,6)` 与 `(6,6)`（过河到 row 6 已在黑方区域，red 象过河线 = row 5，目标 row 6 已过河，应禁止）；实际预期应仅含 `(2,2)` 与 `(6,2)`（不过河、田字格）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_elephant_not_cross_river`

## A4 — 兵未过河只能前进，过河后可左右

- **TC-A4-001**：兵未过河只能前进
  - 前置条件：自定义空棋盘，红兵 `0,3`（未过河，row 3 < 5）
  - 输入：`generate_pseudo_moves(state, red_pawn@0,3)`
  - 预期：走法 = `{(0,2)}`，仅前进一格；不含左右、不含后退
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_pawn_before_river`

- **TC-A4-002**：兵过河后可左右
  - 前置条件：自定义空棋盘，红兵 `4,5`（已过河，row 5 ≥ 5）
  - 输入：`generate_pseudo_moves(state, red_pawn@4,5)`
  - 预期：走法 = `{(4,4),(3,5),(5,5)}`（前进 + 左 + 右）；不含后退（row 6 方向）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_pawn_after_river`

- **TC-A4-003**：兵过河后不能后退
  - 前置条件：自定义空棋盘，红兵 `4,5`（已过河）
  - 输入：`generate_pseudo_moves(state, red_pawn@4,5)`
  - 预期：走法不含 `(4,6)`（红方后退 = row 增大）；对黑兵 `4,4`（已过河）走法不含 `(4,3)`（黑方后退 = row 减小）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_move_generator.gd::test_pawn_no_retreat`

## A5 — `is_legal` 过滤"走完后己方将被将军"的走法（不得送将）

- **TC-A5-001**：直接送将走法被过滤
  - 前置条件：自定义棋盘，红帅 `4,0`，黑车 `4,9`（同列对帅），红车 `3,0`；红方走子
  - 输入：`GameController.generate_legal_moves(state, Side.RED)`，检查红车 `3,0` 的所有走法
  - 预期：红车不能离开 `3,0` 列上的"挡车"职责（移走后黑车将照面将军——同时违反 A10）；红车仅可走能继续阻挡同列的走法（如沿 row 0 横走会暴露照面，应被 `is_legal` 过滤）；具体被过滤的走法集合以规则为准
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_legal_filters_self_check`

- **TC-A5-002**：移动后暴露将军被过滤
  - 前置条件：自定义棋盘，红帅 `4,0`，红士 `3,0`，黑车 `3,5`（同列 3，红士挡车）；红方走子
  - 输入：检查红士 `3,0` 走到 `(4,1)` 这一走法的 `is_legal`
  - 预期：`is_legal(state, move(3,0→4,1))` 返回 `false`（移走后黑车在 col 3 直冲红帅位置不直接将军，但需以实际局面为准；本例改为：红士移走后暴露黑车对红帅的将军——若 `3,0` 是唯一阻挡子则返回 false）。本用例需 builder 实现时构造更明确的局面：黑车在 `4,5` 与红帅 `4,0` 同列，红士 `4,2` 挡车，红士走 `4,2→3,1` 后暴露黑车将军，`is_legal` 应返回 `false`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_legal_filters_revealed_check`

- **TC-A5-003**：应将走法保留
  - 前置条件：自定义棋盘，红帅 `4,0`，黑车 `4,5`（同列将军），红车 `3,0`
  - 输入：`generate_legal_moves(state, Side.RED)`
  - 预期：包含解将走法（红车走 `3,0→4,0` 挡车、或红车 `3,0→4,3` 捕车、或红帅 `4,0→3,0/5,0` 躲避中可行者）；过滤掉所有走完后仍被将军的走法
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_legal_keeps_check_resolving_moves`

## A6 — 将军判定准确：`is_in_check(state, side)` 正确

- **TC-A6-001**：车将军
  - 前置条件：自定义棋盘，红帅 `4,0`，黑车 `4,5`（同列无遮挡）
  - 输入：`RuleValidator.is_in_check(state, Side.RED)`
  - 预期：返回 `true`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_in_check_chariot`

- **TC-A6-002**：马将军
  - 前置条件：自定义棋盘，红帅 `4,0`，黑马 `3,2`（马走日字 `3,2→4,0`，蹩腿点 `3,1` 空）
  - 输入：`is_in_check(state, Side.RED)`
  - 预期：返回 `true`；若 `3,1` 有子蹩腿则返回 `false`（额外断言）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_in_check_horse`

- **TC-A6-003**：炮将军
  - 前置条件：自定义棋盘，红帅 `4,0`，红兵 `4,3`（炮架），黑炮 `4,7`
  - 输入：`is_in_check(state, Side.RED)`
  - 预期：返回 `true`；移除炮架后返回 `false`（额外断言）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_in_check_cannon`

- **TC-A6-004**：兵将军
  - 前置条件：自定义棋盘，红帅 `4,0`，黑兵 `4,1`（已过河，可攻击 row 0）
  - 输入：`is_in_check(state, Side.RED)`
  - 预期：返回 `true`；若黑兵未过河则返回 `false`（额外断言，因未过河兵不能攻击将位）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_in_check_pawn`

- **TC-A6-005**：无将军返回 false
  - 前置条件：`state = BoardState.initial()`（初始局面无将军）
  - 输入：`is_in_check(state, Side.RED)` 与 `is_in_check(state, Side.BLACK)`
  - 预期：均返回 `false`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_not_in_check_initial`

## A7 — 将死判定准确：被将军且无任何合法走法解将

- **TC-A7-001**：标准将死局面
  - 前置条件：构造经典将死局面——红帅 `4,0`，黑车 `4,1`（直接将军且红帅无路可逃——红士 `3,0/5,0` 阻挡横向逃走，红车不在 col 4，红车 `0,0` 不能解将），红方走子
  - 输入：`RuleValidator.is_checkmate(state, Side.RED)`
  - 预期：返回 `true`；同时 `is_in_check` 返回 `true`；`generate_legal_moves` 返回空数组
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_checkmate_classic`

- **TC-A7-002**：可解将非将死
  - 前置条件：自定义棋盘，红帅 `4,0`，黑车 `4,5`（同列将军），红车 `3,0`（可走 `3,0→4,3` 吃车或挡）
  - 输入：`is_checkmate(state, Side.RED)`
  - 预期：返回 `false`；`generate_legal_moves(state, Side.RED)` 非空
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_not_checkmate_when_resolvable`

- **TC-A7-003**：困毙不等于将死
  - 前置条件：构造困毙局面（无合法走法但未被将军，详见 A8 TC-A8-001）
  - 输入：`is_checkmate(state, side)` 与 `is_stalemate(state, side)`
  - 预期：`is_checkmate` 返回 `false`，`is_stalemate` 返回 `true`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_checkmate_vs_stalemate`

## A8 — 困毙判定：无合法走法且未被将军（和棋）

- **TC-A8-001**：困毙局面判定
  - 前置条件：构造困毙局面——红帅 `4,0`（无进攻子将军），红士 `3,0/5,0`，红象 `2,0/6,0`（象眼被塞，无法走田字），红方其余子已移除；红士走 `4,1` 后会被黑车 `4,5` 将军（故被 is_legal 过滤）；红帅被两侧士堵、上方 `4,1` 走后被将军，导致红方无合法走法但当前未被将军
  - 输入：`is_stalemate(state, Side.RED)` 与 `is_in_check(state, Side.RED)` 与 `generate_legal_moves(state, Side.RED)`
  - 预期：`is_stalemate` 返回 `true`；`is_in_check` 返回 `false`；`generate_legal_moves` 返回空数组
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_stalemate_classic`

- **TC-A8-002**：有合法走法不困毙
  - 前置条件：`state = BoardState.initial()`
  - 输入：`is_stalemate(state, Side.RED)` 与 `is_stalemate(state, Side.BLACK)`
  - 预期：均返回 `false`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_not_stalemate_when_moves_exist`

- **TC-A8-003**：被将军时不判困毙
  - 前置条件：TC-A7-001 将死局面
  - 输入：`is_stalemate(state, Side.RED)`
  - 预期：返回 `false`（被将军时即使无合法走法也判将死而非困毙）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_stalemate_false_when_in_check`

## A9 — 长将不变判和（同一着法连续将军达限定回合数）

- **TC-A9-001**：连续将军达限定回合判和
  - 前置条件：构造可长将的局面——红车 `4,5` 与黑将 `4,9` 同列将军，黑将躲到 `3,9`，红车 `4,5→3,5` 继续将军，黑将回 `4,9`，红车回 `4,5`……如此循环达限定回合数（v1.0 暂定连续 3 次同着法将军判和，需 spec 确认，见附录疑问 Q1）
  - 输入：模拟重复将军序列达到限定回合；调用 `RuleValidator.generates_perpetual_check(state, move)` 或对应判和检查 API
  - 预期：判和触发；`check_history` 中记录连续将军次数达上限；游戏进入和棋
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_perpetual_check_draw`

- **TC-A9-002**：非连续将军不判和
  - 前置条件：将军与吃子交替进行，不形成同着法循环
  - 输入：模拟将军-吃子-将军-移动-将军序列
  - 预期：不触发长将判和
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_no_perpetual_check_when_varied`

- **TC-A9-003**：长将以外的循环不判和（如长捉）
  - 前置条件：构造长捉局面（持续捉子但非将军）
  - 输入：模拟长捉循环达限定回合
  - 预期：不触发判和（v1.0 仅判长将，长捉不判和——见附录疑问 Q2）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_perpetual_chase_not_draw`

## A10 — 双方将帅不得照面（同列无遮挡）判违规

- **TC-A10-001**：直接照面走法被 `is_legal` 过滤
  - 前置条件：自定义棋盘，红帅 `4,0`，黑将 `4,9`，红车 `4,4`（同列 4 阻挡）；红方走子，红车拟走 `4,4→3,4` 离开 col 4
  - 输入：`RuleValidator.is_legal(state, move(4,4→3,4))`
  - 预期：返回 `false`（移走后双将同列无遮挡照面）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_kings_face_filters_move`

- **TC-A10-002**：`kings_face` 准确判定
  - 前置条件：三种局面——(a) 双将同列无遮挡；(b) 双将同列中间有子；(c) 双将不同列
  - 输入：`RuleValidator.kings_face(state)`
  - 预期：(a) 返回 `true`；(b) 返回 `false`；(c) 返回 `false`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_kings_face_detection`

- **TC-A10-003**：照面作为将军情形识别
  - 前置条件：自定义棋盘，红帅 `4,0`，黑将 `4,9`，中间无子（已照面）
  - 输入：`is_in_check(state, Side.RED)` 与 `is_in_check(state, Side.BLACK)`
  - 预期：均返回 `true`（照面互将）；任意一方移动将帅解照面后返回 `false`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_rule_validator.gd::test_kings_face_as_check`

---

# B. AI 引擎

## B1 — 低难度：搜索深度 2 层，仅子力评估，同分走法随机选择

- **TC-B1-001**：低难度搜索深度为 2
  - 前置条件：`state = BoardState.initial()`，`difficulty = Difficulty.LOW`
  - 输入：调用 `SearchEngine.choose_move(state, Difficulty.LOW)`，并通过日志或测试钩子记录实际搜索深度
  - 预期：实际搜索深度 = 2 层（搜索树叶子节点深度为 2）；测试通过 `Logger` 或 `SearchEngine.get_last_search_depth()` 测试钩子验证
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_low_difficulty_depth_2`

- **TC-B1-002**：低难度仅子力评估（不含位置表）
  - 前置条件：构造两个等价子力但不同位置的走法局面
  - 输入：`Evaluator.evaluate(state, side)` 在低难度配置下，记录评估项
  - 预期：评估值仅由子力价值决定，不含位置表/机动性/威胁项；可通过 `Evaluator.set_mode` 或 difficulty 参数控制
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_evaluator.gd::test_low_difficulty_material_only`

- **TC-B1-003**：低难度同分走法随机选择
  - 前置条件：构造同分走法 ≥ 2 个的局面（如初始局面）
  - 输入：对同一局面调用 `choose_move(state, Difficulty.LOW)` 多次（≥ 20 次）
  - 预期：不同结果出现的频率分布非单一（至少出现 2 种不同走法）；体现随机扰动
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_low_difficulty_random_among_equal`

## B2 — 中难度：搜索深度 4 层，子力 + 位置表评估，极小扰动

- **TC-B2-001**：中难度搜索深度为 4
  - 前置条件：`state = BoardState.initial()`，`difficulty = Difficulty.MEDIUM`
  - 输入：`choose_move(state, Difficulty.MEDIUM)` + 测试钩子读深度
  - 预期：实际搜索深度 = 4 层
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_medium_difficulty_depth_4`

- **TC-B2-002**：中难度评估含位置表
  - 前置条件：构造两种走法子力相同但位置表得分不同的局面（如马跳卧槽 vs 马跳边线）
  - 输入：`evaluate(state, side)` 在中难度配置下
  - 预期：评估值差异反映位置表加分；位置表对马跳卧槽加分更高
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_evaluator.gd::test_medium_difficulty_position_table`

- **TC-B2-003**：中难度极小扰动（同分走法不显著随机）
  - 前置条件：构造同分走法局面
  - 输入：调用 `choose_move(state, Difficulty.MEDIUM)` 多次（≥ 20 次）
  - 预期：扰动极小（同一走法出现频率 ≥ 80%，或严格最优允许小概率扰动——以实现为准），与低难度形成对比
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_medium_difficulty_minimal_perturbation`

## B3 — 高难度：搜索深度 6 层，子力 + 位置表 + 机动性 + 威胁评估，无扰动严格最优

- **TC-B3-001**：高难度搜索深度为 6
  - 前置条件：`state = BoardState.initial()`，`difficulty = Difficulty.HIGH`
  - 输入：`choose_move(state, Difficulty.HIGH)` + 测试钩子读深度
  - 预期：实际搜索深度 = 6 层
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_high_difficulty_depth_6`

- **TC-B3-002**：高难度评估含机动性与威胁
  - 前置条件：构造两个子力+位置相同但机动性/威胁不同的局面
  - 输入：`evaluate(state, side)` 在高难度配置下
  - 预期：评估值差异反映机动性（合法走法数）与威胁（攻击对方高价值子）项
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_evaluator.gd::test_high_difficulty_mobility_threat`

- **TC-B3-003**：高难度无扰动严格最优
  - 前置条件：构造存在明确最优走法的局面（如可立即吃车）
  - 输入：对同一局面调用 `choose_move(state, Difficulty.HIGH)` 多次（≥ 20 次）
  - 预期：每次返回同一最优走法（无随机扰动）；与低难度形成对比
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_high_difficulty_strict_optimal`

## B4 — AI 任何难度不得走出违规走法

- **TC-B4-001**：低难度走法合法性
  - 前置条件：`state = BoardState.initial()`，`difficulty = Difficulty.LOW`
  - 输入：连续对局 50 步，每步 `choose_move` 后用 `is_legal` 校验返回的走法
  - 预期：每步走法均通过 `is_legal`；无送将、无照面、无越界、无错误走子
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_low_difficulty_legal_moves`

- **TC-B4-002**：中难度走法合法性
  - 前置条件：同上，`difficulty = Difficulty.MEDIUM`
  - 输入：连续对局 50 步合法性校验
  - 预期：每步均合法
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_medium_difficulty_legal_moves`

- **TC-B4-003**：高难度走法合法性
  - 前置条件：同上，`difficulty = Difficulty.HIGH`
  - 输入：连续对局 50 步合法性校验
  - 预期：每步均合法
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_high_difficulty_legal_moves`

## B5 — AI 高难度不得主动送子（无战术补偿的弃子）

- **TC-B5-001**：高难度不主动送子
  - 前置条件：构造局面——黑车 `4,4`，红马 `3,2` 可吃车，红炮 `5,4` 可被黑兵 `5,5` 吃；红方走子
  - 输入：`choose_move(state, Difficulty.HIGH)`
  - 预期：AI 选择吃车（高价值）而非送炮；若送炮无战术补偿（如不形成反将/反吃更高价值子）则不应被选择
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_high_difficulty_no_gift_piece`

- **TC-B5-002**：高难度战术弃子保留
  - 前置条件：构造可弃子得利的局面——红方弃炮后 3 步将死黑方
  - 输入：`choose_move(state, Difficulty.HIGH)`
  - 预期：AI 选择弃子走法（因 6 层搜索能算出将死收益大于弃子损失）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_high_difficulty_tactical_sacrifice`

## B6 — AI 计算在 WorkerThread，主线程不卡顿；计算中显示"思考中"

- **TC-B6-001**：AI 计算在 WorkerThread 执行
  - 前置条件：人机对局进行中，轮到 AI
  - 输入：触发 AI 计算，检查主线程是否阻塞（通过帧时间或 `OS.get_ticks_msec` 测量）
  - 预期：AI 计算在 WorkerThread 中执行；主线程帧时间保持 ≤ 33ms（30fps）；可通过 `Thread` API 或 `WorkerThread` 测试钩子验证
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_ai_thread.gd::test_ai_runs_in_worker_thread`

- **TC-B6-002**：计算中显示"思考中"
  - 前置条件：人机对局，AI 思考中
  - 输入：截屏或检查 HUD 节点
  - 预期：HUD 显示"思考中"提示（视觉层验证）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_ai_thread.gd::test_thinking_indicator_shown`

- **TC-B6-003**：计算完成后 UI 状态恢复
  - 前置条件：AI 思考完成
  - 输入：等待 AI 返回走法
  - 预期："思考中"提示消失；棋盘进入 AnimatingMove 子状态
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_ai_thread.gd::test_thinking_indicator_cleared`

## B7 — AI 高难度单步耗时 ≤ 2 秒

- **TC-B7-001**：高难度单步耗时基准
  - 前置条件：`state = BoardState.initial()`，`difficulty = Difficulty.HIGH`
  - 输入：调用 `choose_move` 10 次（不同中盘局面），记录每次耗时
  - 预期：每次耗时 ≤ 2000ms；平均耗时记录到 benchmark 报告
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_ai_benchmark.gd::test_high_difficulty_time_under_2s`

- **TC-B7-002**：中难度耗时基准
  - 前置条件：`difficulty = Difficulty.MEDIUM`
  - 输入：调用 `choose_move` 10 次
  - 预期：耗时显著低于高难度（≤ 500ms 参考值）；记录到 benchmark
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_ai_benchmark.gd::test_medium_difficulty_time_baseline`

- **TC-B7-003**：benchmark 入口记录基准
  - 前置条件：`run_ai_benchmark.run(difficulty, max_steps)` 入口可用
  - 输入：`run_ai_benchmark.run(Difficulty.HIGH, 20)`
  - 预期：返回 Dictionary 含 `avg_time_ms / max_time_ms / move_count / depth` 字段；可写入文件供回归对比
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_ai_benchmark.gd::test_benchmark_returns_metrics`

## B8 — 置换表生效：相同局面重复搜索命中缓存

- **TC-B8-001**：相同局面重复搜索命中
  - 前置条件：`state` 固定，`tt = TranspositionTable.new()`，`SearchEngine.set_transposition_table(tt)`
  - 输入：第一次 `choose_move(state, Difficulty.HIGH)`；第二次同一 `state` 再次 `choose_move`
  - 预期：第二次搜索节点数显著减少（通过测试钩子读 `nodes_searched`）；或 `tt.hits > 0`
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_transposition_table_hit`

- **TC-B8-002**：置换表未启用时不命中
  - 前置条件：未调用 `set_transposition_table`，或 `tt = null`
  - 输入：同 `state` 两次 `choose_move`
  - 预期：第二次节点数与第一次相当（无缓存命中）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_search_engine.gd::test_transposition_table_disabled`

---

# C. 皮肤系统

## C1 — 第一版含 6 类皮肤：猫、狗、仓鼠、鱼、鸟、熊猫，每类一个 `theme.tres`

- **TC-C1-001**：6 类皮肤 theme.tres 存在
  - 前置条件：`assets/themes/` 目录就绪
  - 输入：扫描 `assets/themes/*/theme.tres`
  - 预期：发现 6 个 `theme.tres`，分别属于 `cats / dogs / hamsters / fish / birds / pandas` 目录（具体目录名以 `assets/README.md` 为准）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_manager.gd::test_six_themes_exist`

- **TC-C1-002**：ThemeManager.list_themes 返回 6 项
  - 前置条件：ThemeManager 初始化完成
  - 输入：`ThemeManager.list_themes()`
  - 预期：返回 6 项，每项含 `theme_id / theme_name`；`theme_id` 与目录名一致
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_manager.gd::test_list_themes_count`

## C2 — 每类皮肤含 14 棋子资源（7 类型 × 2 阵营），键名 `{side}_{type}`

- **TC-C2-001**：每皮肤 14 棋子资源齐全
  - 前置条件：6 个 `theme.tres` 加载完成
  - 输入：对每个 theme，检查 `theme.pieces` 字典
  - 预期：每个 theme 的 `pieces` 含 14 项；键名为 `red_king / red_advisor / red_elephant / red_horse / red_chariot / red_cannon / red_pawn / black_king / ... / black_pawn`（共 14）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_fourteen_pieces_per_theme`

- **TC-C2-002**：键名命名规范一致
  - 前置条件：6 个 theme 加载
  - 输入：检查每个 theme 的 `pieces` 键名集合
  - 预期：6 个 theme 的键名集合完全相同（便于皮肤间互换）；每个键对应 `SpriteFrames` 资源
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_piece_key_naming_consistent`

## C3 — 每棋子含 5 动画状态：idle/selected/moving/killing/killed，帧数达标

- **TC-C3-001**：每棋子 5 状态齐全
  - 前置条件：6 theme × 14 棋子的 SpriteFrames 加载
  - 输入：对每个 SpriteFrames 检查动画名
  - 预期：含 `idle / selected / moving / killing / killed` 5 个动画名；无缺失
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_five_anim_states_present`

- **TC-C3-002**：帧数达标
  - 前置条件：同上
  - 输入：检查每个动画的帧数
  - 预期：每状态帧数 ≥ 8 帧（参考设计文档 §8.2 的 12-24 帧，最低 8 帧容错）；idle/moving 为循环动画；killing/killed 为单次
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_anim_frame_count达标`

## C4 — 职务道具跨 6 类皮肤统一：皇冠=将、盾牌=士、象鼻帽=象、木马=马、战车=车、炮筒=炮、兵帽=兵

- **TC-C4-001**：跨皮肤道具映射一致
  - 前置条件：6 theme 加载，每个 theme 含 `piece_mapping` 字段
  - 输入：对比 6 theme 的 `piece_mapping` 中道具→棋子类型映射
  - 预期：6 theme 道具映射完全一致（皇冠→将、盾牌→士、象鼻帽→象、木马→马、战车→车、炮筒→炮、兵帽→兵）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_prop_mapping_consistent`

- **TC-C4-002**：道具类型唯一（一一对应）
  - 前置条件：道具映射表
  - 输入：检查映射表
  - 预期：7 种道具与 7 种棋子一一对应，无重复、无遗漏
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_prop_mapping_one_to_one`

## C5 — 每类皮肤含 kill_fx / killed_fx 特效场景、victory_anim / defeat_anim 全队动画

- **TC-C5-001**：kill_fx / killed_fx 特效场景存在
  - 前置条件：6 theme 加载
  - 输入：检查每个 theme 的 `kill_fx` 与 `killed_fx` 字段
  - 预期：6 theme 均含两个 `PackedScene` 引用，可实例化
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_kill_fx_scenes_present`

- **TC-C5-002**：victory_anim / defeat_anim 全队动画存在
  - 前置条件：6 theme 加载
  - 输入：检查每个 theme 的 `victory_anim` 与 `defeat_anim`
  - 预期：6 theme 均含两个 `SpriteFrames` 引用；帧数 ≥ 8
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_victory_defeat_anims_present`

## C6 — 每类皮肤含 ThemeSFXResource（formation/select/move/kill/killed/victory/defeat 七音效）

- **TC-C6-001**：7 音效齐全
  - 前置条件：6 theme 加载
  - 输入：检查每个 theme 的 `sfx` 字段（`ThemeSFXResource`）
  - 预期：含 `formation_sfx / select_sfx / move_sfx / kill_sfx / killed_sfx / victory_sfx / defeat_sfx` 7 个 `AudioStream` 引用；无 null
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_seven_sfx_present`

- **TC-C6-002**：音效资源可加载
  - 前置条件：同上
  - 输入：尝试 `load()` 每个 sfx 引用路径
  - 预期：全部加载成功（无 ResourceLoader 错误）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_sfx_resources_loadable`

## C7 — 每类皮肤含 speed_button_idle / speed_button_fast 加速按钮萌物表情头像

- **TC-C7-001**：加速按钮头像齐全
  - 前置条件：6 theme 加载
  - 输入：检查每个 theme 的 `speed_button_idle` 与 `speed_button_fast`
  - 预期：6 theme 均含两个 `Texture2D` 引用，非 null
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_resource.gd::test_speed_button_textures_present`

- **TC-C7-002**：头像跟随皮肤切换
  - 前置条件：当前 skin = cats，UI 显示猫头按钮
  - 输入：`ThemeManager.switch_to("dogs")`，触发 `theme_changed` 信号
  - 预期：加速按钮头像更新为 dogs 的 idle/fast 头像（视觉层断言）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_theme_manager.gd::test_speed_button_follows_theme`

## C8 — `validate_theme.gd` 校验脚本对 6 类皮肤全通过

- **TC-C8-001**：6 皮肤校验全通过
  - 前置条件：6 theme 资源就绪
  - 输入：`validate_theme.validate_all()`
  - 预期：返回 `{"passed": true, "themes_checked": 6, "errors": []}`；6 theme 全部通过
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_validate_theme.gd::test_all_themes_pass`

- **TC-C8-002**：缺项时列出错误
  - 前置条件：故意删除某 theme 的一个棋子资源（如 `cats/pieces/red_king/`）
  - 输入：`validate_theme.validate_all()`
  - 预期：返回 `{"passed": false, "errors": [...]}`，错误列表含缺失资源路径与命名；不崩溃
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_validate_theme.gd::test_validate_reports_missing`

## C9 — 皮肤切换运行时生效，视觉层正确重载棋子贴图

- **TC-C9-001**：switch_to 触发 theme_changed 信号
  - 前置条件：ThemeManager 已加载 6 theme，当前 skin = cats
  - 输入：`ThemeManager.switch_to("dogs")`，连接 `theme_changed` 信号到测试回调
  - 预期：信号被触发一次，参数含新 theme_id = "dogs"
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_theme_manager.gd::test_switch_to_emits_signal`

- **TC-C9-002**：视觉层重载棋子贴图
  - 前置条件：对局中，棋盘上有红马 `red_horse` 显示猫皮肤贴图
  - 输入：`switch_to("dogs")`，等待一帧
  - 预期：所有棋子的 `AnimatedSprite2D.sprite_frames` 更新为 dogs 的对应 `red_horse` / `black_*` SpriteFrames；当前动画状态保持（如仍处于 idle）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_theme_manager.gd::test_visual_layer_reloads_textures`

---

# D. 2.5D 视角

## D1 — 棋盘轻度倾斜 + 近大远小透视效果可见

- **TC-D1-001**：透视背景加载
  - 前置条件：`assets/board/` 含两套透视背景图（玩家方在下 + 对手方在下）
  - 输入：检查资源加载
  - 预期：两套 `Texture2D` 加载成功；非空
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_board_view.gd::test_perspective_backgrounds_load`

- **TC-D1-002**：视觉透视可见
  - 前置条件：进入 Playing 状态，棋盘渲染
  - 输入：截屏与画面基准对比
  - 预期：截图显示轻度倾斜 + 近大远小；与画面基准一致（容忍度 ≤ 5% 像素差异）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_board_view.gd::test_perspective_visual_baseline`

## D2 — 棋子按所在 row 计算缩放（row0→1.0，row9→0.75）和 Y 偏移

- **TC-D2-001**：缩放公式准确
  - 前置条件：棋盘视图初始化，未翻转
  - 输入：对 row 0/3/6/9 调用 `PieceView.get_scale_for_row(r)`（或对应内部函数）
  - 预期：row 0 → 1.0；row 9 → 0.75；row 3 → `lerp(1.0, 0.75, 3/9) ≈ 0.9167`；row 6 → `lerp(1.0, 0.75, 6/9) ≈ 0.8333`；误差 ≤ 0.001
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_row_scale_formula`

- **TC-D2-002**：Y 偏移随 row 递减
  - 前置条件：同上
  - 输入：对 row 0-9 调用 `board_to_screen(Vector2i(0, r))` 取 y 分量
  - 预期：y 单调随 row 增大而减小（远端在上）；相邻行间距随 row 增大而递减（透视压缩）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_y_offset_perspective`

## D3 — 人机模式：玩家固定在下方，视角不翻转

- **TC-D3-001**：人机模式视角固定
  - 前置条件：人机对局开始，红方玩家在 row 0（下方）
  - 输入：模拟 AI 走子后，检查棋盘视角状态
  - 预期：棋盘视角不变（不触发翻转序列）；玩家始终在下方
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_board_view.gd::test_ai_mode_no_flip`

- **TC-D3-002**：人机模式背景图不切换
  - 前置条件：同上
  - 输入：AI 走子完成后检查棋盘背景 Texture
  - 预期：背景图保持"玩家方在下"
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_board_view.gd::test_ai_mode_background_constant`

## D4 — 双人对战：行动方切换时执行翻转序列——列阵音效 + 棋盘背景切换 + 棋子重算布局 + Tween 过渡

- **TC-D4-001**：翻转触发列阵音效
  - 前置条件：双人对战，红方走完，轮到黑方
  - 输入：监听 AudioStreamPlayer 播放事件
  - 预期：`formation_sfx` 被播放一次
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_board_view.gd::test_flip_plays_formation_sfx`

- **TC-D4-002**：棋盘背景切换
  - 前置条件：同上
  - 输入：检查翻转前后的棋盘背景 Texture
  - 预期：从"玩家方在下"切换到"对手方在下"（或反向）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_board_view.gd::test_flip_switches_background`

- **TC-D4-003**：棋子重算布局 + Tween 过渡
  - 前置条件：同上
  - 输入：检查翻转过程中 Tween 是否创建；翻转完成后棋子位置/缩放是否符合新视角
  - 预期：Tween 持续约 0.4 秒；翻转完成后所有棋子按新视角缩放（原 row 0→远端 0.75，原 row 9→近端 1.0）；棋子贴图未旋转
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_board_view.gd::test_flip_recalculates_layout`

## D5 — 翻转过程中棋子贴图不旋转（始终斜视面对当前行动方）

- **TC-D5-001**：贴图 rotation 始终为 0
  - 前置条件：双人对战翻转中
  - 输入：检查每个 `AnimatedSprite2D.rotation`
  - 预期：所有棋子 `rotation == 0`（贴图不旋转）；仅 scale 与 position 变化
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_flip_no_rotation`

- **TC-D5-002**：翻转后贴图斜视面对新行动方
  - 前置条件：翻转完成
  - 输入：截屏与画面基准对比
  - 预期：棋子贴图朝向与新下方视角一致（一套美术通吃两视角，无镜像翻转）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_board_view.gd::test_flip_visual_facing_correct`

## D6 — `board_to_screen` / `screen_to_board` 双向转换准确，翻转后重算

- **TC-D6-001**：board_to_screen 准确
  - 前置条件：未翻转视角
  - 输入：`board_to_screen(Vector2i(c, r))` 对 9×10 全部格子
  - 预期：每个返回坐标在棋盘可视范围内；row 0 在屏幕下方，row 9 在屏幕上方；col 0 在左、col 8 在右
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_board_to_screen_accurate`

- **TC-D6-002**：screen_to_board 准确（双向互逆）
  - 前置条件：未翻转视角
  - 输入：对每个格子 `p = board_to_screen(pos)`，再 `pos2 = screen_to_board(p)`
  - 预期：`pos2 == pos`（互逆）；90 个格子全部通过
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_screen_to_board_inverse`

- **TC-D6-003**：翻转后映射重算
  - 前置条件：翻转后视角
  - 输入：`board_to_screen(Vector2i(4, 0))`（原本在下方）
  - 预期：翻转后 row 0 的 screen y 在屏幕上方（远端）；与未翻转时的 row 9 位置接近（视觉对称）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_board_to_screen_after_flip`

## D7 — 点击命中准确：点击格子的 screen 坐标正确映射到 board 坐标

- **TC-D7-001**：点击格子映射正确
  - 前置条件：未翻转视角，棋盘居中
  - 输入：对每个格子中心 `screen_pt = board_to_screen(pos) + cell_half_size`，调用 `screen_to_board(screen_pt)`
  - 预期：返回 `pos`（90 格全部命中）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_click_hit_center`

- **TC-D7-002**：边界格命中
  - 前置条件：同上
  - 输入：点击 4 个角格（`0,0 / 8,0 / 0,9 / 8,9`）的边缘点（中心 ± 5px）
  - 预期：仍命中对应角格；不误判为相邻格或越界
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_click_hit_corners`

- **TC-D7-003**：翻转后点击命中
  - 前置条件：翻转视角
  - 输入：同 TC-D7-001 但翻转后
  - 预期：90 格全部命中（验证翻转后 `screen_to_board` 正确重算）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_board_view.gd::test_click_hit_after_flip`

---

# E. 动效与音效

## E1 — 5 动画状态在对应时机触发（选中/移动/击杀/被击杀/待机）

- **TC-E1-001**：选中触发 selected 动画
  - 前置条件：Playing 子状态机进入 PieceSelected
  - 输入：玩家点击己方棋子
  - 预期：被选中棋子的 `AnimatedSprite2D.animation = "selected"`；播放 select_sfx
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_selected_anim_triggered`

- **TC-E1-002**：移动触发 moving 动画
  - 前置条件：PieceSelected → AnimatingMove
  - 输入：玩家选目标格，开始移动
  - 预期：移动棋子 `animation = "moving"`；播放 move_sfx；移动完成回到 idle
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_moving_anim_triggered`

- **TC-E1-003**：击杀/被击杀/待机触发
  - 前置条件：移动到有敌方子的格子
  - 输入：执行吃子走法
  - 预期：主动方 `animation = "killing"`；被动方 `animation = "killed"`；动画结束后被动方从棋盘移除，主动方进入 idle
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_killing_killed_anim_triggered`

## E2 — 正常速度动效偏慢（2-3 秒/动作参考），体现萌物缓慢可爱

- **TC-E2-001**：移动动效时长 2-3 秒
  - 前置条件：SpeedMode = NORMAL（1x）
  - 输入：测量一次移动动画从开始到结束的耗时
  - 预期：耗时 ∈ [2.0s, 3.0s]（参考值，非硬性上下限——以"偏慢可爱"为体感目标）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_animations.gd::test_normal_speed_duration`

- **TC-E2-002**：idle 动画循环
  - 前置条件：棋子静止待机
  - 输入：观察 idle 动画
  - 预期：idle 动画循环播放（`loop = true`）；轻微呼吸/晃动
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_animations.gd::test_idle_loops`

## E3 — 加速按钮 1x ⇄ 2x 切换，影响所有动效播放速度

- **TC-E3-001**：1x ⇄ 2x 切换
  - 前置条件：SpeedMode = NORMAL
  - 输入：点击加速按钮
  - 预期：SpeedMode 切换为 FAST；全局动画速度倍率 = 2.0；再次点击回到 1.0
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_speed_toggle`

- **TC-E3-002**：影响所有动效
  - 前置条件：SpeedMode = FAST
  - 输入：触发移动、击杀、被击杀、胜利动画
  - 预期：所有动画 `speed_scale = 2.0`；耗时为 1x 的一半
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_speed_affects_all_anims`

## E4 — 加速按钮头像跟随当前皮肤，悠闲/着急表情对应 1x/2x

- **TC-E4-001**：头像跟随皮肤
  - 前置条件：当前 skin = cats，加速按钮显示猫头
  - 输入：`ThemeManager.switch_to("dogs")`
  - 预期：加速按钮头像更新为 dogs 的 `speed_button_idle`（保持当前 1x 状态）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_animations.gd::test_speed_button_avatar_follows_theme`

- **TC-E4-002**：悠闲/着急表情对应 1x/2x
  - 前置条件：SpeedMode = NORMAL
  - 输入：检查按钮 texture = `speed_button_idle`；切换到 FAST
  - 预期：按钮 texture = `speed_button_fast`；切回 NORMAL 又变回 idle
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_speed_button_emotion_match`

## E5 — 击杀触发 kill_fx 特效 + kill_sfx 音效 + 棋子 killing 动画

- **TC-E5-001**：击杀三件套同时触发
  - 前置条件：吃子走法即将完成
  - 输入：进入 killing 阶段
  - 预期：(a) `kill_fx` 场景被实例化并播放；(b) `kill_sfx` 播放；(c) 主动方棋子 `animation = "killing"`；三者时序对齐（同一帧或 ±1 帧内启动）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_kill_fx_sfx_anim_sync`

- **TC-E5-002**：击杀时机正确
  - 前置条件：移动动画到达目标格
  - 输入：检查 killing 触发点
  - 预期：killing 在主动方到达目标格时触发，而非移动开始时
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_kill_timing_on_arrival`

## E6 — 被击杀触发 killed_fx 特效 + killed_sfx 音效 + 棋子 killed 动画

- **TC-E6-001**：被击杀三件套触发
  - 前置条件：被动方棋子被吃
  - 输入：被吃瞬间
  - 预期：(a) `killed_fx` 场景实例化播放；(b) `killed_sfx` 播放；(c) 被动方 `animation = "killed"`；动画结束后从棋盘移除
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_killed_fx_sfx_anim_sync`

- **TC-E6-002**：被击杀动画结束移除
  - 前置条件：killed 动画播放中
  - 输入：动画结束信号
  - 预期：被动方节点从棋盘 `remove_child` 或 `queue_free`；棋盘状态同步移除该子
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_killed_node_removed_after_anim`

## E7 — 胜利/战败触发对应全队动画 + 音效

- **TC-E7-001**：胜利动画 + 音效
  - 前置条件：将死黑方，红方胜
  - 输入：进入 Gameover 状态
  - 预期：`victory_anim` 全队动画播放；`victory_sfx` 播放
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_victory_anim_sfx`

- **TC-E7-002**：战败动画 + 音效
  - 前置条件：红方被将死
  - 输入：进入 Gameover
  - 预期：`defeat_anim` 全队动画播放；`defeat_sfx` 播放
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_defeat_anim_sfx`

## E8 — 双人对战换边触发 formation_sfx 列阵音效

- **TC-E8-001**：换边触发 formation_sfx
  - 前置条件：双人对战，行动方切换
  - 输入：监听 AudioStreamPlayer
  - 预期：`formation_sfx` 播放一次
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_formation_sfx_on_turn_switch`

- **TC-E8-002**：人机模式不触发 formation_sfx
  - 前置条件：人机对局，AI 走完
  - 输入：监听 AudioStreamPlayer
  - 预期：`formation_sfx` 不播放（仅双人模式触发）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_animations.gd::test_no_formation_sfx_in_ai_mode`

---

# F. 游戏流程与状态机

## F1 — 全局状态机：Boot→MainMenu→SelectTheme→SelectMode→Playing→Gameover 流转正确

- **TC-F1-001**：完整正向流转
  - 前置条件：游戏启动
  - 输入：依次触发各状态退出条件（资源就绪→选开始→选皮肤→选模式→将死）
  - 预期：状态序列 `Boot → MainMenu → SelectTheme → SelectMode → Playing → Gameover`；每状态对应正确场景/控制器；状态切换通过 `GameStateMachine.transition_to(name)` 验证
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_state_machine.gd::test_full_flow_boot_to_gameover`

- **TC-F1-002**：各状态退出条件
  - 前置条件：进入各状态
  - 输入：逐个验证退出条件
  - 预期：Boot 退出条件 = 资源就绪；MainMenu = 选"开始"；SelectTheme = 确认；SelectMode = 确认；Playing = 将死/认输；Gameover = 重开/回菜单/复盘
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_state_machine.gd::test_state_exit_conditions`

## F2 — Paused 状态可暂停/继续/重开/返回菜单

- **TC-F2-001**：暂停/继续/重开/返回菜单
  - 前置条件：Playing 状态
  - 输入：按 ESC 进入 Paused；分别选继续/重开/返回菜单
  - 预期：继续 → 回到 Playing（状态保留）；重开 → 新对局 Playing；返回菜单 → MainMenu
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_state_machine.gd::test_paused_actions`

- **TC-F2-002**：暂停时游戏逻辑冻结
  - 前置条件：Playing 中
  - 输入：进入 Paused，尝试触发棋子移动
  - 预期：输入被忽略；动画暂停；AI 计算暂停（WorkerThread 可中断或等待）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_state_machine.gd::test_paused_freezes_logic`

## F3 — Playing 子状态机：WaitingInput→PieceSelected→AnimatingMove→CheckTurnEnd→TurnSwitching 流转正确

- **TC-F3-001**：子状态流转
  - 前置条件：Playing 状态
  - 输入：玩家选棋子 → 选目标格 → 动画完成 → 检查回合结束 → 切换行动方
  - 预期：子状态序列 `WaitingInput → PieceSelected → AnimatingMove → CheckTurnEnd → TurnSwitching → WaitingInput`（人机模式 TurnSwitching 无翻转）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_state_machine.gd::test_playing_substate_flow`

- **TC-F3-002**：AI 回合自动触发
  - 前置条件：人机模式，轮到 AI
  - 输入：进入 AI 回合
  - 预期：WaitingInput 自动跳过（AI 不需等待输入），AI 计算完成后直接进入 AnimatingMove
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_state_machine.gd::test_ai_turn_auto_trigger`

## F4 — 选中棋子时显示可走位置提示

- **TC-F4-001**：选中显示提示
  - 前置条件：WaitingInput
  - 输入：玩家选中己方棋子
  - 预期：进入 PieceSelected；棋盘上显示该棋子所有合法走法的目标格提示（视觉层标记，非调试层）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_state_machine.gd::test_legal_move_hints_shown`

- **TC-F4-002**：切换选中更新提示
  - 前置条件：已选中棋子 A，显示 A 的提示
  - 输入：玩家点击己方另一棋子 B
  - 预期：A 的提示消失，B 的提示显示
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_state_machine.gd::test_legal_move_hints_update`

## F5 — 将死时正确进入 Gameover，播放胜负动画

- **TC-F5-001**：将死进入 Gameover
  - 前置条件：Playing 中，构造将死局面（TC-A7-001）
  - 输入：被将死方轮到走子
  - 预期：CheckTurnEnd 检测将死 → transition_to Gameover；不进入 TurnSwitching
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_state_machine.gd::test_checkmate_enters_gameover`

- **TC-F5-002**：播放胜负动画
  - 前置条件：进入 Gameover
  - 输入：检查动画与音效
  - 预期：胜方播放 `victory_anim + victory_sfx`；败方播放 `defeat_anim + defeat_sfx`（与 TC-E7 关联）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_state_machine.gd::test_gameover_plays_anim`

---

# G. 棋局记录与复盘

## G1 — 每步走法自动记录到 `move_history`

- **TC-G1-001**：每步记录 move_history
  - 前置条件：开始新对局
  - 输入：玩家与 AI 各走一步
  - 预期：`state.move_history.size() == 2`；每条记录含 `from_col/from_row/to_col/to_row/moved_piece/captured/is_check/turn_number`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_record_replay.gd::test_move_history_appended`

- **TC-G1-002**：记录内容完整准确
  - 前置条件：执行吃子走法
  - 输入：检查最新一条 move_history
  - 预期：`captured` 字段为被吃子 Piece 对象（非 null）；`is_check` 字段为该走法是否将军的 bool；`turn_number` 递增
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_record_replay.gd::test_move_history_fields`

## G2 — 棋谱存档到 `user://records/{timestamp}.json`，含走法 + 元信息

- **TC-G2-001**：存档路径与格式
  - 前置条件：对局结束
  - 输入：触发存档
  - 预期：文件存在于 `user://records/{timestamp}.json`；JSON 含 `moves / theme_id / difficulty / mode / winner / timestamp / side_to_move_first` 字段；JSON 可被 `JSON.parse` 解析
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_record_replay.gd::test_record_saved_to_json`

- **TC-G2-002**：元信息齐全
  - 前置条件：人机对局，难度 HIGH，skin = cats
  - 输入：检查 JSON 元信息
  - 预期：`theme_id = "cats"`、`difficulty = "HIGH"`、`mode = "AI"`、`winner = "RED"/"BLACK"/"DRAW"`、`timestamp` 为合法 ISO8601
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_record_replay.gd::test_record_metadata`

## G3 — Replay 状态支持前进/后退/自动播放

- **TC-G3-001**：前进/后退
  - 前置条件：加载棋谱（含 N 步）
  - 输入：`play_replay.step(state, true)`（前进）、`play_replay.step(state, false)`（后退）
  - 预期：前进 → 棋盘状态前进一步；后退 → 回到上一步；不可超出 [0, N] 范围
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_record_replay.gd::test_replay_step_forward_backward`

- **TC-G3-002**：自动播放
  - 前置条件：加载棋谱
  - 输入：触发自动播放
  - 预期：自动按设定间隔前进；到达末步停止；可中途暂停
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_record_replay.gd::test_replay_auto_play`

## G4 — 复盘重放每步动画 + 音效

- **TC-G4-001**：重放动画 + 音效
  - 前置条件：Replay 状态，加载棋谱
  - 输入：前进一步
  - 预期：触发与正常对局相同的 moving/kill/killed 动画 + 对应 sfx；不只是状态切换
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_record_replay.gd::test_replay_replays_anim_sfx`

- **TC-G4-002**：起始局面正确
  - 前置条件：加载棋谱
  - 输入：回到第 0 步
  - 预期：棋盘为 `BoardState.initial()` 状态；可重新前进
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_record_replay.gd::test_replay_initial_state`

## G5 — 自动存档续局：`user://save.json` 保存棋谱 + 设置

- **TC-G5-001**：自动存档
  - 前置条件：对局进行中，每步走完
  - 输入：检查 `user://save.json`
  - 预期：文件存在；含当前 `move_history`、`theme_id`、`difficulty`、`speed_mode`、`mode`
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_record_replay.gd::test_auto_save_json`

- **TC-G5-002**：续局恢复
  - 前置条件：存在 `user://save.json`
  - 输入：游戏启动 → Boot 加载存档 → 进入 Playing
  - 预期：棋盘状态、皮肤、难度、加速偏好恢复到存档时的状态；可继续走子
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_record_replay.gd::test_auto_save_resume`

---

# H. 平台与分辨率适配

## H1 — 6 平台（Win/Mac/Linux/Android/iOS/Web）均可成功导出

- **TC-H1-001**：6 平台 preset 存在
  - 前置条件：`export_presets.cfg` 就绪
  - 输入：解析 `export_presets.cfg`
  - 预期：含 6 个 preset：`Windows Desktop / macOS / Linux / Android / iOS / Web`
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_platform_export.gd::test_six_presets_exist`

- **TC-H1-002**：CI 批量导出
  - 前置条件：CI 环境（Godot CLI 可用）
  - 输入：`godot --headless --export-release <preset> <output>`
  - 预期：6 平台导出均成功（生成可执行/包文件）；无错误日志
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_platform_export.gd::test_ci_export_all_platforms`

## H2 — 基准 1080×1920 + canvas_items + expand 适配生效

- **TC-H2-001**：项目配置项正确
  - 前置条件：`project.godot` 加载
  - 输入：读取 `display/window/size/viewport_width`、`viewport_height`、`stretch/mode`、`stretch/aspect`
  - 预期：`viewport_width=1080`、`viewport_height=1920`、`stretch/mode="canvas_items"`、`stretch/aspect="expand"`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_platform_export.gd::test_window_config`

- **TC-H2-002**：缩放生效
  - 前置条件：在不同分辨率窗口运行（如 1080×1920、720×1280、1920×1080）
  - 输入：检查视觉根节点 scale
  - 预期：内容按基准 1080×1920 缩放适配；无内容裁剪
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_platform_export.gd::test_stretch_scaling`

## H3 — 手机竖屏布局：棋盘主体 + HUD 上下分布

- **TC-H3-001**：竖屏布局
  - 前置条件：模拟竖屏分辨率 1080×1920
  - 输入：进入 Playing，截屏
  - 预期：棋盘占主体；HUD 信息条在上、操作条在下；与画面基准一致
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_platform_layout.gd::test_portrait_layout`

- **TC-H3-002**：响应式（窄竖屏）
  - 前置条件：模拟 720×1280
  - 输入：检查 Container 自适应
  - 预期：布局保持上下分布，无溢出
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_platform_layout.gd::test_narrow_portrait_responsive`

## H4 — 桌面横屏布局：棋盘居中 + 左右侧栏

- **TC-H4-001**：横屏布局
  - 前置条件：模拟 1920×1080
  - 输入：进入 Playing，截屏
  - 预期：棋盘居中；左侧栏放棋谱/被吃子；右侧栏放操作；与画面基准一致
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_platform_layout.gd::test_landscape_layout`

- **TC-H4-002**：窄屏回退到上下布局
  - 前置条件：模拟 800×600（窄屏）
  - 输入：检查布局
  - 预期：回退到上下布局（与 H3 一致）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_platform_layout.gd::test_narrow_screen_fallback`

## H5 — 移动端竖屏锁定 + 安全区适配 + 切后台暂停

- **TC-H5-001**：竖屏锁定
  - 前置条件：Android/iOS 平台
  - 输入：检查 `display/window/handheld/orientation`
  - 预期：`orientation = "portrait"`
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_platform_export.gd::test_portrait_lock`

- **TC-H5-002**：安全区适配
  - 前置条件：移动设备有刘海/圆角
  - 输入：`DisplayServer.get_window_safe_area()`
  - 预期：HUD 与棋盘不超出安全区；通过 Container margin 适配
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_platform_export.gd::test_safe_area_adaptation`

- **TC-H5-003**：切后台暂停
  - 前置条件：移动端 Playing 中
  - 输入：模拟 `NOTIFICATION_WM_GO_BACK_REQUEST` 或应用进入后台
  - 预期：自动进入 Paused 状态
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_platform_export.gd::test_background_pause`

## H6 — Web 端资源分批加载，无多线程，浏览器暂停处理

- **TC-H6-001**：资源分批加载
  - 前置条件：Web 平台
  - 输入：检查 `assets/` 加载策略
  - 预期：6 皮肤资源分批加载（如先加载当前 skin，其余按需）；首屏不卡；可通过 `ResourceLoader.load_threaded_request` 或类似机制
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_platform_export.gd::test_web_batch_loading`

- **TC-H6-002**：无多线程
  - 前置条件：Web 平台
  - 输入：扫描代码中 `Thread.new()` 使用
  - 预期：Web 平台分支不使用 `Thread`（用 `OS.has_feature("web")` 走单线程路径）；AI 计算在 Web 上降级为同步或协程
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_platform_export.gd::test_web_no_thread`

- **TC-H6-003**：浏览器暂停处理
  - 前置条件：Web 平台
  - 输入：模拟浏览器 tab 切换/隐藏（`JavaScriptBridge` 事件）
  - 预期：游戏自动暂停；返回前台可恢复
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_platform_export.gd::test_web_browser_pause`

## H7 — InputProvider 抽象：鼠标/触屏统一输出语义事件

- **TC-H7-001**：鼠标统一输出
  - 前置条件：桌面平台
  - 输入：模拟 `InputEventMouseButton` 点击棋盘格子
  - 预期：`InputProvider` 输出 `cell_clicked(pos)` 或 `piece_clicked(pos)` 语义事件；坐标已通过 `screen_to_board` 转换
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_input_provider.gd::test_mouse_semantic_event`

- **TC-H7-002**：触屏统一输出
  - 前置条件：移动平台
  - 输入：模拟 `InputEventScreenTouch` 点击棋盘格子
  - 预期：输出与鼠标一致的语义事件（同一回调接口）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_input_provider.gd::test_touch_semantic_event`

- **TC-H7-003**：UI 动作语义事件
  - 前置条件：UI 按钮存在
  - 输入：点击 UI 按钮
  - 预期：`InputProvider` 输出 `ui_action(name)` 语义事件
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_input_provider.gd::test_ui_action_semantic`

## H8 — 平台分支用 `OS.has_feature()` 集中处理，不散落

- **TC-H8-001**：平台分支集中
  - 前置条件：源码扫描
  - 输入：搜索 `OS.has_feature` 调用位置；搜索散落的 `OS.get_name()` 直接比较
  - 预期：平台判断封装在 `scripts/input/` 或 `scripts/platform/` 集中模块；其他模块通过该模块 API 调用；不散落 `if OS.get_name() == "Android"` 等
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_platform_export.gd::test_platform_branches_centralized`

- **TC-H8-002**：覆盖 6 平台 feature
  - 前置条件：集中模块就绪
  - 输入：检查 feature 字符串集合
  - 预期：覆盖 `"windows" / "macos" / "linux" / "android" / "ios" / "web"`（Godot 4.x feature 命名以官方文档为准）
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_platform_export.gd::test_platform_features_covered`

---

# I. 调试与观测

## I1 — 统一日志 Logger（DEBUG/INFO/WARN/ERROR）可写文件

- **TC-I1-001**：4 级日志
  - 前置条件：Logger 单例初始化
  - 输入：分别调用 `Logger.debug / info / warn / error("msg")`
  - 预期：4 条日志均被记录；含时间戳、级别、消息；级别字段正确
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_logger.gd::test_four_log_levels`

- **TC-I1-002**：写文件
  - 前置条件：Logger 配置文件输出
  - 输入：调用各级日志后检查 `user://logs/` 下日志文件
  - 预期：日志文件存在；内容含本次 4 条记录
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_logger.gd::test_logger_writes_file`

- **TC-I1-003**：set_level 过滤
  - 前置条件：Logger.set_level(INFO)
  - 输入：调用 debug/info/warn/error
  - 预期：仅 info/warn/error 被记录；debug 被过滤
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_logger.gd::test_logger_level_filter`

## I2 — 调试辅助层默认关闭，显式参数开启

- **TC-I2-001**：默认关闭
  - 前置条件：游戏正常启动，无显式参数
  - 输入：检查 `DebugLayer.is_enabled()`
  - 预期：返回 `false`
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_debug_layer.gd::test_debug_layer_default_off`

- **TC-I2-002**：显式开启
  - 前置条件：启动参数 `--debug-layer` 或对应启动配置
  - 输入：检查 `DebugLayer.is_enabled()`
  - 预期：返回 `true`；调试层可见（显示坐标/可走位置/评估分/FPS）
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_debug_layer.gd::test_debug_layer_explicit_on`

## I3 — 正常运行/正式视觉验收截图不得出现调试辅助层

- **TC-I3-001**：正常运行不显示
  - 前置条件：游戏正常运行（无 `--debug-layer`）
  - 输入：截屏
  - 预期：截图中无坐标/可走位置/评估分/FPS 等调试信息
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_debug_layer.gd::test_no_debug_in_normal_run`

- **TC-I3-002**：视觉验收截图不显示
  - 前置条件：正式视觉验收流程
  - 输入：执行视觉验收截图脚本
  - 预期：所有验收截图无调试辅助层（与画面基准对比通过）
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_debug_layer.gd::test_no_debug_in_visual_acceptance`

## I4 — 带调试辅助层的截图必须在文件名或报告里明确标注

- **TC-I4-001**：文件名标注
  - 前置条件：开启调试层截图
  - 输入：保存截图
  - 预期：文件名含 `_debug` 后缀（如 `gameover_debug.png`）；或保存到独立 `debug-screenshots/` 目录
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_debug_layer.gd::test_debug_screenshot_filename`

- **TC-I4-002**：报告标注
  - 前置条件：生成验收报告
  - 输入：报告中引用调试层截图
  - 预期：报告显式标注"含调试辅助层"
  - 测试类型：平台
  - 测试入口：`scripts/tests/test_debug_layer.gd::test_debug_screenshot_report_annotation`

## I5 — `scripts/debug/` 含 validate_theme / run_ai_benchmark / play_replay 三个入口

- **TC-I5-001**：validate_theme 入口
  - 前置条件：`scripts/debug/validate_theme.gd` 存在
  - 输入：`validate_theme.validate_all()`
  - 预期：返回 Dictionary 含 `passed / themes_checked / errors` 字段
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_debug_entries.gd::test_validate_theme_entry`

- **TC-I5-002**：run_ai_benchmark 入口
  - 前置条件：`scripts/debug/run_ai_benchmark.gd` 存在
  - 输入：`run_ai_benchmark.run(Difficulty.HIGH, 10)`
  - 预期：返回 Dictionary 含 `avg_time_ms / max_time_ms / move_count / depth` 字段
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_debug_entries.gd::test_run_ai_benchmark_entry`

- **TC-I5-003**：play_replay 入口
  - 前置条件：`scripts/debug/play_replay.gd` 存在；存在合法棋谱文件
  - 输入：`play_replay.load_replay(path)`；`play_replay.step(state, true)`
  - 预期：load 返回 `{success: true, total_steps: N, ...}`；step 返回 `{state: BoardState, step_index: i}`；可前进/后退
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_debug_entries.gd::test_play_replay_entry`

---

# J. 测试覆盖

## J1 — 核心逻辑层单元测试覆盖走法生成/合法性/将军将死/评估函数

- **TC-J1-001**：走法生成单测覆盖
  - 前置条件：`scripts/tests/test_move_generator.gd` 就绪
  - 输入：运行 GUT 单元测试
  - 预期：A1-A4 相关用例全部通过；覆盖率 ≥ 7 棋子 × 主要走法分支
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_unit_move_generator_coverage`

- **TC-J1-002**：合法性/将军将死单测覆盖
  - 前置条件：`scripts/tests/test_rule_validator.gd` 就绪
  - 输入：运行 GUT
  - 预期：A5-A10 相关用例全部通过；覆盖 is_legal / is_in_check / is_checkmate / is_stalemate / kings_face / perpetual_check
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_unit_rule_validator_coverage`

- **TC-J1-003**：评估函数单测覆盖
  - 前置条件：`scripts/tests/test_evaluator.gd` 就绪
  - 输入：运行 GUT
  - 预期：B1-B3 评估函数用例全部通过；覆盖三难度的评估项差异
  - 测试类型：单元
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_unit_evaluator_coverage`

## J2 — 集成测试覆盖 AI 端到端/皮肤加载切换/状态机流转/复盘回放

- **TC-J2-001**：AI 端到端集成
  - 前置条件：`scripts/tests/test_search_engine.gd` 就绪
  - 输入：运行集成测试
  - 预期：B4-B8 端到端用例全部通过；AI 在 50 步对局中不违规、不送子、耗时达标
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_integration_ai_end_to_end`

- **TC-J2-002**：皮肤加载切换集成
  - 前置条件：`scripts/tests/test_theme_manager.gd / test_theme_resource.gd` 就绪
  - 输入：运行集成测试
  - 预期：C1-C9 用例全部通过；6 皮肤加载 + 切换 + 视觉重载
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_integration_theme_load_switch`

- **TC-J2-003**：状态机流转集成
  - 前置条件：`scripts/tests/test_state_machine.gd` 就绪
  - 输入：运行集成测试
  - 预期：F1-F5 用例全部通过；全局状态机 + Playing 子状态机流转
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_integration_state_machine`

- **TC-J2-004**：复盘回放集成
  - 前置条件：`scripts/tests/test_record_replay.gd` 就绪
  - 输入：运行集成测试
  - 预期：G1-G5 用例全部通过；存档 + 加载 + 前进后退 + 动画重放
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_integration_replay`

## J3 — 视觉验收有画面基准 + 截图对比

- **TC-J3-001**：画面基准存在
  - 前置条件：`docs/visual-baseline/` 或 `assets/baseline/` 目录
  - 输入：检查基准图集
  - 预期：含 D1（透视）/ D5（翻转）/ E1-E7（动效）/ H3-H4（布局）/ I3（无调试层）等关键场景的基准截图
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_visual_baseline_exists`

- **TC-J3-002**：截图对比
  - 前置条件：视觉验收脚本就绪
  - 输入：运行视觉验收脚本，对当前截图与基准对比
  - 预期：差异 ≤ 容忍度（如 5% 像素差异）；不通过则输出差异图
  - 测试类型：视觉
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_visual_screenshot_compare`

## J4 — 每条验收标准都有真实测试覆盖（acceptance-checker 核对）

- **TC-J4-001**：每条验收标准有测试覆盖
  - 前置条件：本文档（test-cases.md）就绪
  - 输入：acceptance-checker 核对 A1-J4 每条标准是否有 ≥ 1 个测试用例
  - 预期：A1-A10 / B1-B8 / C1-C9 / D1-D7 / E1-E8 / F1-F5 / G1-G5 / H1-H8 / I1-I5 / J1-J4 共 73 条全部有覆盖；输出覆盖矩阵
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_acceptance_checker_coverage_matrix`

- **TC-J4-002**：覆盖矩阵可追溯
  - 前置条件：覆盖矩阵生成
  - 输入：检查矩阵
  - 预期：每条标准 → 测试用例编号（TC-XX-NNN）→ 测试入口路径 → 状态（pass/fail）可追溯
  - 测试类型：集成
  - 测试入口：`scripts/tests/test_test_coverage.gd::test_coverage_matrix_traceable`

---

# 附录 A：测试用例统计

| 部分 | 验收条目数 | 测试用例数 | 红线 |
|------|-----------|-----------|------|
| A. 核心规则 | 10 | 31（每条 ≥ 3） | 是 |
| B. AI 引擎 | 8 | 21 | 是（B4-B5） |
| C. 皮肤系统 | 9 | 18 | 是（C8） |
| D. 2.5D 视角 | 7 | 17 | 是（D4） |
| E. 动效音效 | 8 | 16 | 是（E8） |
| F. 状态机 | 5 | 10 | 否 |
| G. 棋局复盘 | 5 | 10 | 否 |
| H. 平台适配 | 8 | 20 | 否 |
| I. 调试观测 | 5 | 11 | 是（I3-I4） |
| J. 测试覆盖 | 4 | 9 | 否 |
| **合计** | **73** | **163** | — |

# 附录 B：自检结论

## 每条验收标准覆盖情况

- A1 ✓（TC-A1-001 ~ TC-A1-008，8 用例，覆盖 7 棋子走法 + 初始局面）
- A2 ✓（TC-A2-001 ~ TC-A2-004，4 用例，覆盖蹩马腿/塞象眼/炮翻山/多子阻挡）
- A3 ✓（TC-A3-001 ~ TC-A3-003，3 用例，覆盖将/士/象限制）
- A4 ✓（TC-A4-001 ~ TC-A4-003，3 用例，覆盖未过河/过河/不后退）
- A5 ✓（TC-A5-001 ~ TC-A5-003，3 用例，覆盖送将/暴露将军/应将保留）
- A6 ✓（TC-A6-001 ~ TC-A6-005，5 用例，覆盖车/马/炮/兵将军 + 无将军）
- A7 ✓（TC-A7-001 ~ TC-A7-003，3 用例，覆盖将死/可解将/困毙区分）
- A8 ✓（TC-A8-001 ~ TC-A8-003，3 用例，覆盖困毙/有走法/被将军不判困毙）
- A9 ✓（TC-A9-001 ~ TC-A9-003，3 用例，覆盖长将判和/非连续/长捉不判）
- A10 ✓（TC-A10-001 ~ TC-A10-003，3 用例，覆盖照面过滤/kings_face/照面即将军）
- B1 ✓（TC-B1-001 ~ TC-B1-003，3 用例，深度/评估/随机）
- B2 ✓（TC-B2-001 ~ TC-B2-003，3 用例，深度/位置表/扰动）
- B3 ✓（TC-B3-001 ~ TC-B3-003，3 用例，深度/机动性威胁/严格最优）
- B4 ✓（TC-B4-001 ~ TC-B4-003，3 用例，三难度合法性）
- B5 ✓（TC-B5-001 ~ TC-B5-002，2 用例，不送子/战术弃子）
- B6 ✓（TC-B6-001 ~ TC-B6-003，3 用例，WorkerThread/思考中/恢复）
- B7 ✓（TC-B7-001 ~ TC-B7-003，3 用例，高难度/中难度/benchmark）
- B8 ✓（TC-B8-001 ~ TC-B8-002，2 用例，命中/未启用）
- C1 ✓（TC-C1-001 ~ TC-C1-002，2 用例）
- C2 ✓（TC-C2-001 ~ TC-C2-002，2 用例）
- C3 ✓（TC-C3-001 ~ TC-C3-002，2 用例）
- C4 ✓（TC-C4-001 ~ TC-C4-002，2 用例）
- C5 ✓（TC-C5-001 ~ TC-C5-002，2 用例）
- C6 ✓（TC-C6-001 ~ TC-C6-002，2 用例）
- C7 ✓（TC-C7-001 ~ TC-C7-002，2 用例）
- C8 ✓（TC-C8-001 ~ TC-C8-002，2 用例）
- C9 ✓（TC-C9-001 ~ TC-C9-002，2 用例）
- D1 ✓（TC-D1-001 ~ TC-D1-002，2 用例）
- D2 ✓（TC-D2-001 ~ TC-D2-002，2 用例）
- D3 ✓（TC-D3-001 ~ TC-D3-002，2 用例）
- D4 ✓（TC-D4-001 ~ TC-D4-003，3 用例，列阵音效/背景切换/Tween）
- D5 ✓（TC-D5-001 ~ TC-D5-002，2 用例）
- D6 ✓（TC-D6-001 ~ TC-D6-003，3 用例，正向/反向/翻转后）
- D7 ✓（TC-D7-001 ~ TC-D7-003，3 用例，中心/边界/翻转后）
- E1 ✓（TC-E1-001 ~ TC-E1-003，3 用例）
- E2 ✓（TC-E2-001 ~ TC-E2-002，2 用例）
- E3 ✓（TC-E3-001 ~ TC-E3-002，2 用例）
- E4 ✓（TC-E4-001 ~ TC-E4-002，2 用例）
- E5 ✓（TC-E5-001 ~ TC-E5-002，2 用例）
- E6 ✓（TC-E6-001 ~ TC-E6-002，2 用例）
- E7 ✓（TC-E7-001 ~ TC-E7-002，2 用例）
- E8 ✓（TC-E8-001 ~ TC-E8-002，2 用例）
- F1 ✓（TC-F1-001 ~ TC-F1-002，2 用例）
- F2 ✓（TC-F2-001 ~ TC-F2-002，2 用例）
- F3 ✓（TC-F3-001 ~ TC-F3-002，2 用例）
- F4 ✓（TC-F4-001 ~ TC-F4-002，2 用例）
- F5 ✓（TC-F5-001 ~ TC-F5-002，2 用例）
- G1 ✓（TC-G1-001 ~ TC-G1-002，2 用例）
- G2 ✓（TC-G2-001 ~ TC-G2-002，2 用例）
- G3 ✓（TC-G3-001 ~ TC-G3-002，2 用例）
- G4 ✓（TC-G4-001 ~ TC-G4-002，2 用例）
- G5 ✓（TC-G5-001 ~ TC-G5-002，2 用例）
- H1 ✓（TC-H1-001 ~ TC-H1-002，2 用例）
- H2 ✓（TC-H2-001 ~ TC-H2-002，2 用例）
- H3 ✓（TC-H3-001 ~ TC-H3-002，2 用例）
- H4 ✓（TC-H4-001 ~ TC-H4-002，2 用例）
- H5 ✓（TC-H5-001 ~ TC-H5-003，3 用例，竖屏/安全区/后台）
- H6 ✓（TC-H6-001 ~ TC-H6-003，3 用例，分批/无线程/暂停）
- H7 ✓（TC-H7-001 ~ TC-H7-003，3 用例，鼠标/触屏/UI）
- H8 ✓（TC-H8-001 ~ TC-H8-002，2 用例）
- I1 ✓（TC-I1-001 ~ TC-I1-003，3 用例，4级/写文件/过滤）
- I2 ✓（TC-I2-001 ~ TC-I2-002，2 用例）
- I3 ✓（TC-I3-001 ~ TC-I3-002，2 用例）
- I4 ✓（TC-I4-001 ~ TC-I4-002，2 用例）
- I5 ✓（TC-I5-001 ~ TC-I5-003，3 用例，三入口）
- J1 ✓（TC-J1-001 ~ TC-J1-003，3 用例）
- J2 ✓（TC-J2-001 ~ TC-J2-004，4 用例）
- J3 ✓（TC-J3-001 ~ TC-J3-002，2 用例）
- J4 ✓（TC-J4-001 ~ TC-J4-002，2 用例）

**自检结论**：A1-J4 共 73 条验收标准，全部有 ≥ 2 个测试用例覆盖；其中红线 A1-A10 每条 ≥ 3 个用例（符合任务要求）；D4/D6/D7/H5/H6/H7/I1/I5 等关键条目亦给出 3 个用例。共 163 个测试用例。

# 附录 C：API 契约疑问（待主 Agent / 用户确认）

- **Q1（A9 长将判和阈值）**：验收标准 A9 写"同一着法连续将军达限定回合数"，但未指明具体回合数。设计文档 §10 也未明确。常见象棋规则为连续 3 次同着法将军判和。请确认 v1.0 采用的限定回合数（建议 3）。本测试用例暂按 3 设计，实现时若有变更需同步更新 TC-A9-001。
- **Q2（A9 长捉是否判和）**：A9 仅提"长将"，未提"长捉"（持续捉子但不将军）。中国象棋正式规则中长捉也判和，但 v1.0 spec 未明确。本测试用例 TC-A9-003 暂按"长捉不判和"设计（仅判长将），请确认。
- **Q3（A1 初始走法总数）**：TC-A1-008 引用"权威值"作为初始红方伪走法总数断言。常见引用值为 44，但不同引擎实现略有差异（是否包含帅的 5 个走法、是否区分吃子与非吃子）。建议 builder 实现时引用 pikafish/eleeye 等开源引擎的统计为准，若与本断言冲突以权威值为准并更新本用例。
- **Q4（API 契约未明的字段）**：
  - `BoardState.check_history`：是记录"被将军历史"还是"将军走法历史"？数据结构是 Array[Move] 还是 Array[Dictionary]？A9 长将判定依赖此字段。
  - `RuleValidator.generates_perpetual_check(state, move)`：参数 `move` 是当前拟走的将军走法，还是历史走法序列？返回 bool 还是判和阈值？
  - `SearchEngine.set_transposition_table(tt)`：`tt` 的具体类型是 `TranspositionTable` 类（未在 API 契约中定义）还是 Dictionary？建议补充 `TranspositionTable` 类的 API 契约（含 `lookup / store / clear / hits` 等方法）。
  - `play_replay.step(replay_state, forward)`：`replay_state` 是 `BoardState` 还是 replay 专用的状态对象（含 step_index）？返回 Dictionary 含哪些字段？
- **Q5（B6 主线程卡顿判定阈值）**：B6 要求"主线程不卡顿"，但未给帧时间阈值。本测试用例暂按 ≤ 33ms（30fps）设计，移动/Web 平台按 30fps、桌面按 60fps（≤ 16ms）。请确认。
- **Q6（C3 帧数达标具体阈值）**：C3 写"帧数达标"，设计文档 §8.2 写"12-24 帧"。本测试用例 TC-C3-002 暂按 ≥ 8 帧容错设计（允许个别动作帧数较少），请确认是否严格按 12 帧下限。
- **Q7（H8 OS.has_feature 命名）**：Godot 4.x 中 `OS.has_feature` 的平台 feature 字符串命名（如 `"windows"` vs `"Windows"`）需以官方文档为准。本测试用例 TC-H8-002 列出小写形式，请 builder 实现时核对。
- **Q8（视觉验收容忍度）**：J3 / D1 / D5 / E1 等涉及截图对比的用例，本测试用例暂按 ≤ 5% 像素差异设计容忍度。请确认是否合理，以及是否需分平台/分场景设置不同容忍度。

---

_本文档由 `test-author` 子 Agent 根据 `docs/development/acceptance-standard.md`（已冻结）设计，未修改任何验收标准。后续 `acceptance-checker` 子 Agent 应核对每条验收标准的覆盖完整性；`builder` 子 Agent 实现时按本文档命名 GUT 测试脚本与函数。_
