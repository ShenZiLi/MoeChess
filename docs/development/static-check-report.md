# 静态检查报告

- 检查日期：2026-07-29
- 检查角色：静态检查 Agent（search 子 Agent，只读）
- 检查范围：scripts/ + scenes/ + project.godot + export_presets.cfg + assets/themes/**/*.tres
- 落盘：主 Agent 代为落盘（子 Agent 仅有只读工具）

## 汇总

- 检查文件数：75（42 个 .gd + 13 个 .tscn + 1 个 project.godot + 1 个 export_presets.cfg + 18 个 .tres）
- 错误：2（已由主 Agent 修复）
- 警告：9
- 提示：4

## 错误清单（已修复）

- ~~[scripts/states/game_state_machine.gd:199] `resume_from_auto_save()` 检查 `data.get("has_save", false)`，但 `SaveManager.auto_save()` 未写入 `has_save` 字段~~ → **已修复**：在 `save_manager.gd:117` 的 auto_save 字典中补 `"has_save": true`
- ~~[project.godot:14-19] `PlatformConfig` 未注册为 autoload，导致 web_loader.gd 回退到散落的 `OS.has_feature` 判定，违反 H8 红线~~ → **已修复**：在 project.godot `[autoload]` 段补 `PlatformConfig="*res://scripts/input/platform_config.gd"`

## 警告清单（建议修复）

- [scripts/debug/run_ai_benchmark.gd:86] API 名称不一致 → **已修复**：`get_last_nodes_count` → `get_last_search_nodes`
- [scripts/states/game_state_machine.gd:234] `or true` 死代码 → **已修复**：去掉冗余条件
- [scripts/states/game_state_machine.gd:244] `int != null` 冗余判断 → **已修复**：直接使用 `_speed_mode`
- [scripts/states/game_state_machine.gd:247,272] 成员变量声明位置分散 → 已知，可读性问题，不阻塞交付
- [scripts/theme/theme_manager.gd:11] 缺 `class_name`（autoload 故意省略，与 Godot 4.x autoload 命名冲突规避策略一致）→ 已知
- [scripts/core/save_manager.gd:32] `extends Node` 触及 "core 不依赖 Node" 边界 → autoload 单例必需，主 Agent 决定扩列为例外
- [scripts/core/replay_controller.gd:156-163] 使用 SceneTree/SceneTreeTimer → 主 Agent 决定扩列为例外（自动播放调度需要 timer）
- [assets/themes/cats/fx/killed_fx.tscn:3] 根节点名 `KillFX` 与 kill_fx.tscn 重名 → 仅靠路径区分，建议改名（不阻塞）
- [scripts/debug/run_ai_benchmark.gd:26-29,50-54] 静态入口 preload 被注释（TODO）→ 设计为注入式调用，静态入口需注入 SearchEngine 才可用

## 提示清单（可选改进）

- [scripts/core/constants.gd:99] `in_home_half` 用 `_ = col` 抑制警告 → 可改为 `_col` 参数名
- [scripts/core/board_state.gd:152] `Array(d.get("check_history", []), TYPE_INT, "null", null)` 四参构造 → 建议加注释说明
- [assets/themes/cats/fx/kill_fx.tscn / killed_fx.tscn] 占位场景节点名未带 PLACEHOLDER 后缀 → 父 theme.tres 已 `is_placeholder=true`
- [scenes/main.tscn:19] UI CanvasLayer 曾为空 → **已修复**：通过 main_scene_controller.gd 运行时动态实例化 HUD/MainMenu/PausePanel/GameoverPanel/DebugLayer

## 各层依赖检查

- **core 层零渲染依赖**：✅ 通过（7 个例外文件均 extends RefCounted，无 Node2D/Sprite2D/Texture2D/Control 引用）
  - 例外扩列：SaveManager（autoload 必需 extends Node）、ReplayController（自动播放需 SceneTree timer）— 主 Agent 决定保留在 core/ 但标记为例外
- **ai 依赖 core**：✅ 一致
- **view 依赖 core+theme+states 信号**：✅ 一致
- **跨层 class_name 引用一致**：✅ 一致（41/42 文件有 class_name，theme_manager.gd 故意省略）
- **autoload 名称与 project.godot 注册一致**：✅ 一致（Logger / ThemeManager / GameStateMachine / SaveManager / PlatformConfig 五个）
- **preload/load 路径存在性**：✅ 一致
- **资源引用**：✅ 一致（13 个 .tscn + theme.tres 引用路径全部命中）

## 坐标约定一致性

- ✅ 所有 .gd 文件一致使用 "红方前进 = row 增大（forward(RED)=+1）"
- ✅ constants.gd:104-109 `forward(side)` 实现已修正
- ✅ move_generator.gd `_gen_pawn` 使用 `nr = piece.row + fwd`，红方 fwd=+1
- ✅ evaluator.gd 位置表 PST_PAWN 第 5-9 行（红方过河区）高分，与"红方过河 = row >= 5"一致
- ✅ board_perspective.gd `t_at_row(row, flipped)` 玩家视角 row 0 → 近边 scale=1.0
- 未发现遗留的 "红方前进 = row 减小" 反向约定

## AGENTS.md 约束检查

- **core 层零渲染依赖**：✅ 通过
- **调试辅助层默认关闭**：✅ 通过（debug_layer.gd:23 `visible = false`，仅 `--debug-overlay` 或 `set_enabled(true)` 开启）
- **占位资源标注 PLACEHOLDER**：部分通过（theme.tres `is_placeholder=true`，FX 场景节点名未带后缀，建议后续改进）

## GDScript 语法检查

- **class_name + extends**：41/42 文件同时具备（theme_manager.gd autoload 故意省略）
- **缩进**：均使用 Tab
- **未闭合括号 / 错误关键字**：未发现
- **类型注解一致性**：普遍带类型注解

## API 契约一致性

- ✅ 测试脚本调用的 API 在实现文件中存在（已修复 run_ai_benchmark 的 `get_last_nodes_count` 错误）
- ✅ 跨层调用按契约
- ✅ GUT 测试覆盖 14 个文件 81 个测试方法

---

_本报告由静态检查 Agent 输出，主 Agent 代为落盘。_
