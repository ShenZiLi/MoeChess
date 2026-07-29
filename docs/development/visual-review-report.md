# 视觉复核报告

- 复核角色：visual-reviewer
- 复核日期：2026-07-29
- 复核方式：代码静态分析（本环境无 Godot 运行时，无法截图）
- 复核范围：board_view / piece_view / fx_player / move_hint_layer / board_perspective / hud / gameover_panel / main_menu 及其 .tscn、棋盘与 cats 皮肤占位资源
- 验收对照：docs/development/acceptance-standard.md（D1-D7 / E1-E8 / F4 / F5 / I3 / I4）

## 汇总

- 复核项：19
- 通过：7（均为"代码层通过"，其中多数仍待运行时观感验证）
- 不通过：9（根因均为视图/UI 编排层缺失，见下方"关键发现"）
- 部分通过/警告：2
- 不适用：1（I4 为流程规范，非代码可验证）
- 待运行时验证：11

### 关键发现（根因，影响多数不通过项）

**视图/UI 编排层（orchestration）整体缺失**，导致大量视觉行为在运行时不会触发。具体证据：

1. `scenes/main.tscn`：`Main`（Node2D）**无脚本**；其下仅有 `BoardView` / `FxPlayer` / `MoveHintLayer` 和一个**空的 `UI` CanvasLayer**。未实例化 `HUD` / `GameoverPanel` / `MainMenu` / `PausePanel` / `DebugLayer`。
2. `project.godot`：autoload 仅 `Logger` / `ThemeManager` / `GameStateMachine` / `SaveManager`，无视图编排节点。`run/main_scene = res://scenes/main.tscn`。
3. 全仓搜索（`*.gd`）确认以下方法**从未被任何代码调用**：
   - `BoardView.setup(state)`（`scripts/view/board_view.gd:107`）→ 运行时棋子不会创建、棋盘不会初始化。
   - `BoardView.flip_view()`（`scripts/view/board_view.gd:125`）→ D4 翻转不会发生。
   - `MoveHintLayer.show_hints()`（`scripts/view/move_hint_layer.gd:41`）→ F4 提示不会显示。
   - `PieceView.play_state()`（`scripts/view/piece_view.gd:75`）→ E1 的 selected/moving/killing/killed 状态动画不会触发。
   - `PieceView.move_to()`（`scripts/view/piece_view.gd:99`）→ 移动 Tween 不会播放。
   - `FxPlayer.play_kill_fx/play_killed_fx/play_victory/play_defeat/play_formation_sfx`（`scripts/view/fx_player.gd:51-80`）→ E5/E6/E7/E8 不会触发。
   - `GameoverPanel.show_result()`（`scripts/ui/gameover_panel.gd:45`）→ F5 胜负动画不会播放。
   - `HUD.set_theme()`（`scripts/ui/hud.gd:51`）→ E4 头像不会跟随皮肤更新。
4. `PlayingState`（`scripts/states/playing_state.gd`）发出的 `request_show_hints` / `request_clear_hints` / `request_flip_view` / `move_started` / `piece_selected` 信号**仅被 emit，无任何 connect 订阅**；`BoardView.piece_clicked` / `cell_clicked` 也无订阅者，故点击无法驱动状态机。
5. `GameStateMachine` 仅连接了 `PlayingState.game_over → _on_playing_game_over`（`scripts/states/game_state_machine.gd:144`），其余视觉信号全部悬空。
6. `BoardView.fx_player` 字段（`scripts/view/board_view.gd:63`）**从未被注入**，即使 `flip_view` 被调用也无法播放 formation_sfx。
7. `DebugLayer`（`scripts/debug/debug_layer.gd`）**从未被实例化进任何场景**，I3 红线"运行时不显示"因不存在而平凡满足，但 I2/I5 调试入口实际不可用。

> 结论：各组件**内部**视觉逻辑基本正确（见逐项"依据"），但**组件间连线全部缺失**。需补一个编排层（如 `main.gd` 挂到 `Main` 节点，或在 `GameStateMachine` 中持有 view/UI 引用并 connect 全部信号、实例化 HUD/GameoverPanel/DebugLayer、注入 `BoardView.fx_player`、调用 `BoardView.setup`）。在该编排层补齐前，D4/E1/E4/E5/E6/E7/E8/F4/F5 无法判定为通过。

---

## 逐项复核

### D1 棋盘轻度倾斜 + 近大远小透视
- 状态：✅ 通过（代码层）/ ⚠️ 待运行时验证观感
- 依据：
  - `scripts/view/board_perspective.gd:18-43` 定义梯形视体：`NEAR_HALF_WIDTH=496` > `FAR_HALF_WIDTH=345`，`NEAR_Y=1220`（底）> `FAR_Y=60`（顶），近大远小数学成立。
  - `scripts/view/board_view.gd:278-310` `_draw()` 在无贴图时画梯形 + 11 横/9 竖网格兜底。
  - `assets/board/board_player.png` / `board_opponent.png` 实测尺寸 1080×1280，与 `BG_W/BG_H` 常量一致，透视常数对齐。
- 问题：占位图为程序化生成（PLACEHOLDER），待正式美术替换后再次复核观感。

### D2 棋子按 row 缩放 + Y 偏移
- 状态：✅ 通过（代码层）/ ⚠️ 待运行时验证
- 依据：
  - `scripts/view/board_perspective.gd:65-72` `scale_at_t` lerp `SCALE_NEAR=1.0`→`SCALE_FAR=0.75`；`scale_at_row` row0→t=0→1.0、row9→t=1→0.75，符合 D2。
  - `scripts/view/board_perspective.gd:74-76` `y_offset_at_row` lerp NEAR_Y→FAR_Y。
  - `scripts/view/piece_view.gd:136-143` `refresh_transform` 应用 position + scale。
- 问题：无（代码层）。运行时观感待验证。

### D3 人机模式不翻转
- 状态：✅ 通过（代码层）
- 依据：`scripts/states/playing_state.gd:326-335` `_start_turn_switching` 仅在 `_game_mode == _MODE_PVP` 时 emit `request_flip_view`，否则直接 `_finish_turn_switching`；`_player_side` 固定 RED（`:77`、`:141`）。
- 问题：无。

### D4 双人对战翻转序列（列阵音效 + 背景切换 + 重算布局 + Tween）
- 状态：❌ 不通过
- 依据：
  - 组件实现齐全：`scripts/view/board_view.gd:125-151` `flip_view()` 依次播 formation_sfx（`:127-128`）、切背景（`:131-132`）、重算位置/缩放并 Tween 0.4s（`:137-150`），rotation 不改（D5）。
  - 但 `request_flip_view`（`playing_state.gd:46/331`）**无订阅者**；`BoardView.flip_view` 从未被调用；`BoardView.fx_player`（`board_view.gd:63`）从未被注入 → formation_sfx 即便触发也不会播。
- 问题：编排层缺失，运行时 D4 翻转序列不会发生。

### D5 翻转过程中棋子贴图不旋转
- 状态：✅ 通过（代码层）
- 依据：`scripts/view/piece_view.gd:143` `refresh_transform` 显式 `rotation = 0.0`；`board_view.gd:148-149` 翻转 Tween 只动 `position` 与统一 `scale`，不动 rotation。
- 问题：无。

### D6 坐标转换准确
- 状态：✅ 通过（代码层）/ ⚠️ 待运行时验证
- 依据：`scripts/view/board_perspective.gd:80-89` `board_to_screen` 与 `:97-122` `screen_to_board` 互为逆运算（t↔y、col_ratio↔x），含越界与容差判定（`:113-121`）。
- 问题：无（代码层）。建议运行时用边界格（0,0)/(8,9）与翻转态做点击回归。

### D7 点击命中准确
- 状态：✅ 通过（代码层）/ ⚠️ 待运行时验证
- 依据：`scripts/view/board_view.gd:185-199` `_unhandled_input` → `_global_to_local` → `BoardPerspective.screen_to_board` → 查 `board_state` 发 `piece_clicked`/`cell_clicked`。
- 问题：`piece_clicked`/`cell_clicked` 信号**无订阅者**，运行时点击不会驱动 `PlayingState`（编排缺失）。命中精度本身待运行时验证。

### E1 5 动画状态在对应时机触发
- 状态：❌ 不通过
- 依据：
  - `scripts/view/piece_view.gd:75-96` `play_state` 定义了 IDLE/SELECTED/MOVING/KILLING/KILLED 五态分支。
  - 但 `play_state` **从未被任何代码调用**；`move_to`（`:99-121`）用 Tween 过渡 position/scale，**未调用 `play_state(MOVING)`**，故 moving 动画帧不会播。
  - `PlayingState.piece_selected`/`move_started` 信号无订阅者。
- 问题：5 态动画实际只有 idle（`set_piece` 默认播 idle，`piece_view.gd:71-72`）会运行；selected/moving/killing/killed 均无触发路径。

### E2 正常速度动效偏慢（2-3 秒/动作）
- 状态：✅ 通过（代码层）
- 依据：`scripts/view/piece_view.gd:21` `MOVE_DURATION_NORMAL = 2.5` 秒；`move_to` 时长 `2.5 / SPEED_SCALE`（`:116`），落在 2-3 秒区间。
- 问题：无（但 E1 不通过，该时长当前无可生效路径）。

### E3 加速按钮 1x ⇄ 2x 切换
- 状态：⚠️ 部分通过
- 依据：
  - `scripts/core/constants.gd:72-76` `SPEED_SCALE={NORMAL:1.0, FAST:2.0}`。
  - 组件内实现正确：`piece_view.gd:124-127/154-156`、`fx_player.gd:83-90`、`board_view.gd:154-159` 都会应用 speed_scale。
  - 但 `HUD.speed_toggled`（`hud.gd:13/29`）**无订阅者**，未连到 `GameStateMachine.set_speed_mode` / `BoardView.set_speed_mode`；运行时点击加速按钮不会生效。
- 问题：加速链路在组件内闭合，但 HUD→状态机→视图的连线缺失。

### E4 加速按钮头像跟随当前皮肤
- 状态：❌ 不通过
- 依据：`scripts/ui/hud.gd:66-70` `_apply_speed_button_texture` 按 `_theme.speed_button_fast/idle` 切换贴图，逻辑正确；cats 皮肤 `speed_button_idle.png`/`fast.png`（256×256）存在。但：
  - `HUD` **未在 `main.tscn` 实例化**（UI CanvasLayer 为空）。
  - `HUD.set_theme`（`hud.gd:51`）从未被调用；`ThemeManager.theme_changed` 未连到 HUD。
- 问题：运行时 HUD 不存在，头像无法跟随皮肤。

### E5 击杀 kill_fx + kill_sfx + killing 动画
- 状态：❌ 不通过
- 依据：`scripts/view/fx_player.gd:51-53` `play_kill_fx` 实现齐全（kill_sfx + kill_fx 场景）。但 `play_kill_fx` 从未被调用；`PieceView.play_state(KILLING)` 从未被调用；`kill_fx.tscn` 为占位 Polygon2D（PLACEHOLDER）。
- 问题：编排缺失，运行时击杀无 fx/sfx/killing 动画。占位特效待正式美术替换。

### E6 被击杀 killed_fx + killed_sfx + killed 动画
- 状态：❌ 不通过
- 依据：`scripts/view/fx_player.gd:56-58` `play_killed_fx` 实现齐全；`piece_view.gd:82-96` killed 态有 `animation_finished` + 兜底定时器。但 `play_killed_fx` 与 `play_state(KILLED)` 均从未被调用。
- 问题：编排缺失，运行时被击杀无 fx/sfx/killed 动画。

### E7 胜利/战败全队动画 + 音效
- 状态：❌ 不通过
- 依据：
  - `fx_player.gd:73-80` `play_victory/play_defeat` 实现齐全（sfx + 全屏 team anim）；`gameover_panel.gd:67-79` `_play_result_anim` 也播 victory/defeat_anim。
  - 但两者**均从未被调用**；`GameoverPanel` 未在 `main.tscn` 实例化。
  - 另存在**双重播放风险**：`FxPlayer._play_team_anim` 与 `GameoverPanel._anim_sprite` 是两个独立 AnimatedSprite2D，若同时触发会叠放，需运行时确认是否只取其一。
- 问题：编排缺失，运行时无胜负动画/音效。

### E8 双人对战换边触发 formation_sfx
- 状态：❌ 不通过
- 依据：`board_view.gd:127-128` `flip_view` 内调 `fx_player.play_formation_sfx`；`playing_state.gd:331` PVP 换边 emit `request_flip_view`。但 `request_flip_view` 无订阅者、`BoardView.fx_player` 未注入、`flip_view` 从未被调用。另：`assets/themes/cats/sfx.tres` 中 `formation_sfx = null`（PLACEHOLDER 皮肤，`is_placeholder=true`，按 `theme_resource.gd:115-120` 允许跳过）。
- 问题：编排缺失 + 占位音效为空，运行时换边无声。占位音效待正式资源替换后再次复核。

### F4 选中棋子显示可走位置提示（短暂反馈，非常驻几何圈）
- 状态：❌ 不通过
- 依据：
  - `scripts/view/move_hint_layer.gd:41-56` `show_hints` 用半透明圆形 + 脉动 Tween（`:100-103`）；`clear_hints`（`:59-65`）在取消选中/走子后清除——属"短暂反馈"，符合 AGENTS.md（非常驻几何圈），组件本身合规。
  - 但 `PlayingState.request_show_hints`/`request_clear_hints`（`playing_state.gd:40/43/257/266/303`）**无订阅者**，`show_hints` 从未被调用。
- 问题：编排缺失，运行时选中棋子无提示。组件实现合规，待 wiring 补齐后即可通过。

### F5 将死进入 Gameover + 胜负动画
- 状态：❌ 不通过
- 依据：`playing_state.gd:314-321` `_check_turn_end` 将死时 emit `game_over`；`game_state_machine.gd:144/304-316` 连接并 `change_state("Gameover")`——状态机层链路通。但 `GameoverPanel.show_result`（`gameover_panel.gd:45`）从未被调用、面板未实例化，胜负动画不会播。
- 问题：状态机→GameoverPanel 的最后一跳缺失。

### I3 正常运行不显示调试辅助层
- 状态：⚠️ 部分通过
- 依据：`scripts/debug/debug_layer.gd:21-26` `_ready` 默认 `visible=false`、`mouse_filter=IGNORE`，仅 `--debug-overlay` 或 `set_enabled(true)` 开启。但 `DebugLayer` **从未被实例化进场景树**（`main.tscn` 无该节点，无 `.add_child`）。
- 问题：运行时确实不会显示调试辅助层（I3 红线平凡满足），但 I2"调试辅助层默认关闭，显式参数开启"与 I5"`scripts/debug/` 三个入口"中的调试层观测能力实际不可用——需将 `DebugLayer` 挂到主场景并按 cmdline 开启。

### I4 带调试辅助层的截图必须在文件名或报告里明确标注
- 状态：N/A（流程规范）
- 依据：此条为交付/截图标注流程要求，非代码可验证项；本次无截图产出。
- 问题：无。建议后续带调试层的截图统一在文件名加 `_debug` 后缀并在报告中声明。

---

## 不通过项修复建议（供 builder 参考，visual-reviewer 不写代码）

> 根因统一为"缺视图/UI 编排层"。建议新增一个挂在 `Main` 节点的编排脚本（如 `scripts/main.gd`，并在 `main.tscn` 挂载），或由 `GameStateMachine` 在进入 Playing 时持有 view/UI 引用并完成全部连线：

1. **实例化缺失节点**：在 `main.tscn` 的 `UI` CanvasLayer 下加入 `HUD`（`scenes/ui/hud.tscn`）、`GameoverPanel`、`MainMenu`、`PausePanel`、`SelectThemePanel`、`SelectModePanel`、`SettingsPanel`、`ReplayPanel`、`CodexPanel`；将 `DebugLayer` 加入 `Main`。
2. **棋盘初始化**：进入 Playing 时调用 `BoardView.setup(playing_state.get_state())`。
3. **注入依赖**：`BoardView.fx_player = FxPlayer`。
4. **连信号 → 视图**：
   - `PlayingState.request_show_hints` → `MoveHintLayer.show_hints`
   - `PlayingState.request_clear_hints` → `MoveHintLayer.clear_hints`
   - `PlayingState.request_flip_view` → `BoardView.flip_view`，并连 `BoardView.flip_finished` → `PlayingState.on_flip_done`
   - `PlayingState.piece_selected` → 对应 `PieceView.play_state(SELECTED)` + `FxPlayer.play_select_sfx`
   - `PlayingState.move_started` → 编排方法：`PieceView.move_to` + `play_state(MOVING)` + `FxPlayer.play_move_sfx`；若 `move.captured != null` → 对被吃方 `play_state(KILLED)` + `FxPlayer.play_killed_fx`，对吃子方 `play_state(KILLING)` + `FxPlayer.play_kill_fx`；动画完成 → `PlayingState.on_move_anim_done`
   - `PlayingState.game_over` → `GameoverPanel.show_result` + `FxPlayer.play_victory/play_defeat`（注意与 GameoverPanel 内置 anim 二选一，避免 E7 双重播放）
   - `BoardView.piece_clicked`/`cell_clicked` → `PlayingState.on_piece_clicked`/`on_cell_clicked`
   - `HUD.speed_toggled` → 切 `SpeedMode` 后回灌 `BoardView.set_speed_mode` / `FxPlayer.set_speed_mode` / `HUD.set_speed_mode`
   - `HUD.pause_pressed` → `GameStateMachine.pause_game`
   - `ThemeManager.theme_changed` → `HUD.set_theme` + `BoardView._on_theme_changed`（已有）
5. **E1 MOVING**：在 `PieceView.move_to` 内或编排层调用 `play_state(MOVING)`，使 moving 帧动画随 Tween 同步播放。
6. **DebugLayer**：挂载后保留 `--debug-overlay` 开关；确保正式截图不带该层（I3）或明确标注（I4）。

补齐上述编排后，D4/E1/E3/E4/E5/E6/E7/E8/F4/F5 应即可通过；随后需在 Godot 运行时做截图回归（见下）。

---

## 运行时验证待办（需 Godot 环境）

> 以下项代码层已通过或待 wiring 补齐后验证，必须在 Godot 运行时截图对比画面基准：

1. **D1** 透视观感：截图对比近大远小梯形效果（占位图 + 兜底梯形两路径）。
2. **D2** 棋子缩放/Y 偏移：截 row0 与 row9 棋子尺寸比，确认 1.0 : 0.75。
3. **D4** PVP 换边翻转 Tween 0.4s 过渡截图序列 + formation_sfx 听感。
4. **D6/D7** 点击命中：对四角与翻转态做点击回归，验证 `screen_to_board` 精度。
5. **E1** 五态动画触发：选中/移动/击杀/被击杀/待机各截一帧。
6. **E2** 移动时长实测（应 2.5s，加速 1.25s）。
7. **E3** 加速按钮 1x⇄2x 全链路（HUD→状态机→视图）。
8. **E4** 切皮肤后加速按钮头像刷新截图。
9. **E5/E6** 击杀/被击杀 fx+sfx+动画同步截图 + 听感。
10. **E7** 胜利/战败全队动画 + 音效截图 + 听感；确认 E7 双重播放风险已消除。
11. **E8** PVP 换边 formation_sfx 听感（待正式音效替换后复核）。
12. **F4** 选中提示脉动 + 取消选中后清除截图。
13. **F5** 将死→Gameover 面板 + 胜负动画截图。
14. **I3** 正常运行截图确认无调试辅助层；`--debug-overlay` 开启后截图确认出现，并验证 I4 标注流程。
15. **占位美术/音效**：board_*.png、kill_fx/killed_fx.tscn、cats/sfx.tres（全 null）待正式美术/音效替换后再次复核。

---

## 备注

- 本报告为**只读**复核产物，未修改任何代码/UI/资源文件。
- 占位美术（PLACEHOLDER）按 AGENTS.md 规则不判为不通过，均已在"待运行时验证"中标注"待正式美术替换后再次复核"。
- `assets/themes/cats/theme.tres` `is_placeholder=true`；`assets/themes/cats/sfx.tres` 七音效全为 null（符合 placeholder 跳过规则）。
- `assets/themes/cats/pieces/red_king/red_king.tres` 经核查含完整 5 动画 × 12 帧（共 60 帧引用齐全），早期 glob 因 200 条限制截断属误象。
- 棋盘占位图 `board_player.png`/`board_opponent.png` 实测 1080×1280，与 `BoardPerspective.BG_W/BG_H` 常量一致。
- 按 AGENTS.md"新增文档须更新 docs/index.md"，本报告为新增文档；visual-reviewer 受"只读"约束未自行改动 `docs/index.md`，请主 Agent 酌情登记。
