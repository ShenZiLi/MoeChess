# 萌象棋（MoeChess）项目记忆

> 项目长期约定与关键事实。日常记录见按日期的工作日志。

## 项目概况

- **类型**：Godot 4.x + GDScript 的跨平台萌系中国象棋游戏
- **平台**：Windows / macOS / Linux / Android / iOS / Web(HTML5)
- **版本**：v1.0 全功能首版（设计于 2026-07-28 确认）

## 开发流程铁律（AGENTS.md）

1. **设计阶段不写代码，进入实现前必须向立立确认**
2. 严格遵循 AGENTS.md 的 11 步开发流程
3. 验收标准（`docs/development/acceptance-standard.md`）已于 2026-07-28 经立立确认冻结为外部合格线，AI 不得自行新增/改写/降低
4. 子 Agent 分工：builder（实现）/ test-author（测试）/ acceptance-checker（核对覆盖）/ visual-reviewer（视觉复核）/ reviewer（综合复核）
5. 写实现的 Agent 不能担任 visual-reviewer 或 reviewer
6. `docs/index.md` 新增文档必须同步更新
7. 正常运行/正式视觉验收截图不得出现调试辅助层；带调试层的截图须在文件名或报告标注

## 核心设计决策（v1.0）

- **架构**：7 层单向依赖（核心逻辑/AI/视觉/资源/输入/UI/状态机），`scripts/core/` 零渲染依赖可单测
- **数据模型**：`apply_move` 不可变更新（返回新 BoardState），便于 AI 搜索/悔棋/复盘
- **皮肤系统**：数据驱动 ThemeResource，新增皮肤只加 `assets/themes/{name}/` 目录，零代码改动
- **6 类萌物皮肤**：猫、狗、仓鼠、鱼、鸟、熊猫
- **棋子识别**：不用传统棋子字，用**职务道具**（皇冠=将、盾牌=士、象鼻帽=象、木马=马、战车=车、炮筒=炮、兵帽=兵），跨皮肤统一
- **棋子视觉构成**：底座（红/黑圆盘）+ 萌物主体 + 职务道具
- **AI**：minimax + alpha-beta，3 难度 = 深度(2/4/6) + 评估精度 + 随机扰动；WorkerThread 防卡顿
- **2.5D 视角**：程序化透视，棋盘预渲染 + 棋子按行缩放；双人对战翻转布局但棋子贴图不旋转
- **动效**：偏慢可爱（2-3秒/动作），2 倍速按钮用萌物表情头像（悠闲/着急）
- **棋局**：自动记录 + 复盘（前进/后退/自动播放）
- **适配**：基准 1080×1920 竖屏 + canvas_items + expand + 容器响应式；InputProvider 抽象鼠标/触屏

## 目录规范（AGENTS.md）

顶层目录：`spec/` `assets/` `docs/` `scenes/` `scripts/` + `AGENTS.md` `README.md`
- `scripts/core/` 纯逻辑层（零渲染依赖）
- `assets/themes/{name}/theme.tres` 每皮肤入口
- `scripts/debug/` 调试入口（validate_theme / run_ai_benchmark / play_replay）

## 关键文档

- 设计文档：`docs/plans/2026-07-28-moechess-design.md`
- 产品规格：`spec/v1.0-spec.md`
- 验收标准：`docs/development/acceptance-standard.md`（已确认冻结为外部合格线，2026-07-28 立立确认）
- 资源说明：`assets/README.md`
- 文档索引：`docs/index.md`

## 实施里程碑（M1-M10）

M1 核心逻辑层 → M2 AI 引擎 → M3 视觉骨架（占位美术）→ M4 状态机+输入 → M5 皮肤系统（1套猫）→ M6 动效音效 → M7 视角翻转 → M8 棋局记录复盘 → M9 全部6类皮肤 → M10 平台适配导出

## 待确认的开放项

- 6 类皮肤的具体品种→棋子完整映射
- AI 高难度实测耗时（实现后 benchmark 调参）
- Web 平台资源分批加载策略细节
- BGM 音乐风格与来源
