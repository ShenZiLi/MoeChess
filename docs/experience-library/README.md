# 开发经验库

> AGENTS.md 要求：失败经验、已解决问题、复发规则记录于此。

## 已解决问题

### EX-001 坐标系"前进方向"根因 bug（2026-07-29）

**现象**：constants.gd 早期版本写 `forward(RED) = -1`（红方前进 = row 减小），但 `board_state.gd` 初始局面把红方放在 row 0-4、黑方放在 row 5-9，双方相向推进。这导致 `pawn_crossed_river(row, RED) = (row < 4)`（红兵过河 = 进入 row 0-3），与"红方过河 = 进入黑方半场 row 5-9"矛盾。AI builder 的位置表 PST_PAWN 也基于错误约定设计。

**根因**：设计文档早期版本"红方前进 = row 减小"的描述与"row 0 = 红方底线 + 红方在 row 0-4"的初始局面布局不自洽。中国象棋标准是双方相向推进，红方在下方必须向上（row 增大）走。

**修复**：
- `constants.gd`：`forward(RED) = +1`、`forward(BLACK) = -1`；`pawn_crossed_river(row, RED) = (row > RED_RIVER_ROW)` 即 `row >= 5`；`pawn_crossed_river(row, BLACK) = (row < BLACK_RIVER_ROW)` 即 `row <= 4`
- `test-cases.md`：在"棋盘坐标与约定"段加修正说明，正文部分用例的"红兵 row 减小"描述以本节统一约定为准
- `evaluator.gd` 位置表已在 AI builder 实现时按"红方过河 = row 5-9"常识设计，无需改动

**复发规则**：任何涉及坐标系的方向性函数（forward / pawn_crossed_river / 位置表 PST / 视角翻转）改动前，必须先核对 `board_state.gd:initial()` 的初始布局——红方在 row 0-4、黑方在 row 5-9、双方相向推进。`forward(side)` 必须使 side 的棋子向对方半场推进。

### EX-002 视图编排层缺失（2026-007-29）

**现象**：visual-reviewer 与 reviewer 共同指出 9 项视觉验收不通过（D4/E1/E4/E5/E6/E7/E8/F4/F5），根因统一：`scenes/main.tscn` 的 Main 节点无脚本，UI CanvasLayer 为空，HUD/GameoverPanel/MainMenu/PausePanel/DebugLayer 均未实例化，PlayingState 的 5 个视觉信号（request_show_hints / request_clear_hints / request_flip_view / move_started / piece_selected）全部悬空无订阅者，BoardView.piece_clicked/cell_clicked 也无订阅者，BoardView.fx_player 从未注入。

**根因**：分模块 builder 只实现"组件内部逻辑"，没有 builder 负责"组件间连线"。AGENTS.md 角色分工中 builder 任务范围未明确包含"编排层"职责。

**修复**：
- 新增 `scripts/main_scene_controller.gd`（class_name MainSceneController，extends Node2D）
- 挂到 `scenes/main.tscn` 的 Main 节点
- 职责：实例化 UI 面板到 UI CanvasLayer、注入 BoardView.fx_player、订阅 PlayingState 视觉信号 → 调用 BoardView/FxPlayer/MoveHintLayer、订阅 BoardView 点击信号 → 转发到 PlayingState、订阅 GameStateMachine.state_changed → 切换 UI 面板、订阅 ThemeManager.theme_changed → 刷新 HUD 头像（E4）

**复发规则**：任何新增视觉组件（HUD/面板/特效/动画）后，必须同步在 main_scene_controller.gd 中添加：
1. 实例化节点到 UI CanvasLayer（或场景树合适位置）
2. 订阅组件的输出信号
3. 调用组件的输入方法
4. 验证连线完整（grep 信号名应同时出现在 emit 方与 connect 方）

### EX-003 PlatformConfig autoload 未注册（2026-07-29）

**现象**：static-check 发现 `web_loader.gd` 通过 `get_node_or_null("/root/PlatformConfig")` 期望其为 autoload 单例，但 project.godot 未注册。回退到散落的 `OS.has_feature` 判定违反 H8 红线。

**根因**：input builder 创建了 PlatformConfig 类但未要求注册 autoload；platform builder 引用时假设已注册。

**修复**：在 project.godot `[autoload]` 段补 `PlatformConfig="*res://scripts/input/platform_config.gd"`。

**复发规则**：新增 autoload 单例时，必须同步在 project.godot `[autoload]` 段注册，并在 docs/index.md 或经验库记录。

### EX-004 SaveManager.has_save 字段缺失（2026-07-29）

**现象**：`game_state_machine.gd:resume_from_auto_save()` 检查 `data.get("has_save", false)`，但 `save_manager.gd:auto_save()` 写入的字典只含 `state`/`settings`/`timestamp` 三个字段，导致 G5 续局功能完全失效——即便存在自动存档，`resume_from_auto_save()` 永远返回 false。

**根因**：读写两端的字典契约不一致。builder 实现 save_manager 时未与 states 层的读取逻辑对齐。

**修复**：在 `save_manager.gd:auto_save()` 的字典中补 `"has_save": true`。

**复发规则**：跨层字典/JSON 契约（如存档格式、棋谱格式、设置格式）必须在 docs 中明确定义字段清单，且读写双方都按契约实现。建议在 test-cases.md 中为每个契约字段设计至少一个 round-trip 测试。

### EX-005 theme.tres 入口资源缺失（2026-07-29）

**现象**：ThemeManager 启动时扫描 `res://assets/themes/*/theme.tres`，但 cats 皮肤目录下虽有全部 14 棋子 .tres、anim/*.tres、fx/*.tscn、ui/*.png、sfx.tres，唯独缺 `theme.tres`。导致 `_themes` 字典为空、`get_current()` 返回 null、所有视觉/音效调用传入 null theme → 运行时必崩。reviewer/visual-reviewer 报告均未发现此根因（误报"cats 有完整资源"）。

**根因**：`_generate_placeholders.gd`（EditorScript）只生成 pieces/anim/ui 三类资源，未生成 theme.tres 本身。builder 实现组件后未补全入口资源。

**修复**：手动创建 `assets/themes/cats/theme.tres`，引用 14 piece SpriteFrames + kill_fx/killed_fx PackedScene + victory/defeat SpriteFrames + sfx ThemeSFXResource + speed_button 2 Texture2D，设 `is_placeholder=true`。

**复发规则**：任何新增皮肤目录后，必须验证 `theme.tres` 存在且 ResourceLoader 能加载。ThemeManager 启动日志应打印已登记皮肤数量，0 时视为致命错误。校验：`grep -r "theme.tres" assets/themes/*/` 应每目录命中 1 个。

### EX-006 validate_theme.gd 与 ThemeResource.validate_sfx 的 is_placeholder 逻辑不一致（2026-07-29）

**现象**：`ThemeResource.validate_sfx(allow_placeholder=true)` 在 `is_placeholder=true` 时跳过音效 null 检查；但 `validate_theme.gd` 的 SFX 校验段无条件检查 7 项音效非空，不读 `is_placeholder`。导致 placeholder 皮肤（SFX 全 null）必然被 validate_theme 报为 invalid → C8 红线无法通过。

**根因**：两处校验逻辑独立实现，未对齐。validate_theme.gd 是验收 C8 的权威脚本，应与 ThemeResource 的校验语义一致。

**修复**：在 `validate_theme.gd` SFX 校验段加 `var is_placeholder = bool(res.get("is_placeholder", false))`，`if not is_placeholder:` 时才检查 7 项音效非空。

**复发规则**：存在两套校验逻辑（ThemeResource.validate_all 和 validate_theme.gd）时，必须保持语义一致。任何校验规则变更必须同步两处，并在 test-cases.md 中设计交叉验证用例。

### EX-007 5 套皮肤资源批量生成（Python 外部脚本，2026-07-29）

**现象**：C8 红线要求 6 类皮肤校验全通过，但仅 cats 有资源，birds/dogs/fish/hamsters/pandas 5 目录为空。无 Godot 编辑器可用（环境无 godot 二进制），无法运行 `_generate_placeholders.gd`（EditorScript）。

**根因**：占位资源生成器是 EditorScript，依赖 Godot 编辑器运行。CI/无 Godot 环境下无法生成资源。

**修复**：新增 `assets/themes/_gen_placeholder_themes.py`（Python + PIL），以 cats 为模板批量生成 5 套皮肤：
- 复制全部 PNG 并叠加主题色调（birds=蓝/dogs=棕/fish=青/hamsters=黄/pandas=灰）以区分
- 改写 .tres 内 `res://assets/themes/cats/` → `res://assets/themes/{id}/` 路径
- 复制 .tscn（无主题特定路径）
- 生成 sfx.tres（7 音效 null，is_placeholder=true 允许）
- 生成 theme.tres（引用本主题资源，is_placeholder=true）

**复发规则**：AGENTS.md 允许"外部脚本用于资源处理"。当 Godot EditorScript 不可用时，Python+PIL 是生成占位资源的可行替代。新皮肤只需在 THEMES 字典加一项配置后重跑脚本。正式美术替换时只需覆盖 PNG 并将 is_placeholder 改为 false。

---

## 复发规则汇总

1. **坐标系约定**：红方前进 = row 增大（forward(RED)=+1）；红方在 row 0-4，黑方在 row 5-9；红兵过河 = row >= 5；row 0 = 红方底线（玩家方/下方）。改动方向性函数前必须核对初始布局。
2. **编排层职责**：任何视觉组件新增后，必须在 main_scene_controller.gd 同步添加实例化 + 信号连线 + 验证。
3. **autoload 注册**：新增 autoload 单例必须同步注册到 project.godot。
4. **跨层字典契约**：存档/棋谱/设置等跨层 JSON 字典必须在 docs 中定义字段清单，读写双方对齐，并设计 round-trip 测试。
5. **子 Agent 委托风险**：核心规则层（A1-A10 红线）多次委托子 Agent 失败，最终由主 Agent 直写完成。红线代码不应过度委托，主 Agent 应保留直接实现能力。
6. **子 Agent 返回校验**：子 Agent 报告"已完成"不等于文件已落盘。主 Agent 必须用 Glob 核对实际文件存在性，不能只看返回文本。
7. **theme.tres 入口资源**：新增皮肤目录后必须验证 theme.tres 存在且可加载；ThemeManager 启动日志应打印已登记数量。
8. **校验逻辑一致性**：ThemeResource.validate_all 与 validate_theme.gd 必须保持 is_placeholder 语义一致。
9. **Python 资源生成**：Godot EditorScript 不可用时，Python+PIL 可替代生成占位资源（AGENTS.md 允许外部脚本用于资源处理）。

---

_最后更新：2026-07-29_
