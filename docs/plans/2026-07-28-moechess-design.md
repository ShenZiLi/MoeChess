# 萌象棋（MoeChess）v1.0 设计文档

- **状态**：已与立立确认（2026-07-28）
- **技术栈**：Godot 4.x + GDScript
- **目标平台**：Windows / macOS / Linux / Android / iOS / Web(HTML5)
- **关联文档**：`spec/v1.0-spec.md`、`docs/development/acceptance-standard.md`、`assets/README.md`

---

## 0. 已确认决策汇总

| # | 决策点 | 结论 |
|---|--------|------|
| 1 | 版本范围 | 全功能首版（玩法 + 多皮肤 + 特效 + 6平台） |
| 2 | 美术资源 | AI 生成（ComfyUI），配合资源规格 + 导入校验管线 |
| 3 | AI 引擎 | 自写 minimax + alpha-beta，3 难度由搜索深度(2/4/6)+评估精度+随机扰动控制 |
| 4 | 双人对战 | 本地同屏，行动方切换时视角翻转 + 列阵音效 |
| 5 | 视角方案 | 2D + 程序化透视（棋盘预渲染 + 棋子按行缩放） |
| 6 | 萌物皮肤 | 第一版至少 6 类：猫、狗、仓鼠、鱼、鸟、熊猫 |
| 7 | 棋子识别 | 不用传统棋子字，改用**职务道具**（跨皮肤统一规则）识别棋子种类 |
| 8 | 动效节奏 | 正常速度偏慢（2-3秒/动作），体现萌物缓慢可爱；支持 2 倍速按钮（萌物表情头像） |
| 9 | 棋局功能 | 支持棋局记录 + 复盘（前进/后退/自动播放） |
| 10 | 适配 | 基准 1080×1920 竖屏 + expand 缩放 + 容器响应式布局 |

---

## 1. 整体架构

技术栈锁定 **Godot 4.x + GDScript**，单一代码库覆盖 6 平台，通过抽象层处理平台差异。

采用分层架构，各层单向依赖、可独立测试：

| 层 | 目录 | 职责 | 依赖 |
|----|------|------|------|
| 核心逻辑层 | `scripts/core/` | 棋盘状态、走法生成、合法判定、将军/将死判定。纯 GDScript，零渲染依赖，可单元测试 | 无 |
| AI 层 | `scripts/ai/` | minimax + alpha-beta + 评估函数 + 置换表 | 核心逻辑层 |
| 视觉表现层 | `scripts/view/` + `scenes/` | 2D 节点 + 程序化透视，棋盘 Container 管理行缩放/Y偏移，视角翻转 | 核心逻辑层、资源层 |
| 资源管理层 | `scripts/theme/` + `assets/themes/` | 皮肤系统数据驱动，`ThemeResource` 含 14 棋子 SpriteFrames + 音效 + 特效 | 无 |
| 输入控制层 | `scripts/input/` | 抽象 `InputProvider`，桌面=鼠标，移动=触屏，Web=鼠标，统一输出"选中棋子/目标格"语义 | 无 |
| UI 层 | `scripts/ui/` + `scenes/ui/` | 菜单/选皮肤/选模式/HUD/结算面板，Control 节点 | 资源层 |
| 状态机 | `scripts/states/` | `GameStateMachine` 管理全局流程 | 各层 |

**设计原则**：
- `scripts/core/` 严格零渲染依赖，象棋规则可脱离 Godot 场景独立单测
- `apply_move` 返回**新 BoardState**（不可变更新），便于 AI 搜索分支与悔棋/复盘，不污染主状态
- 皮肤系统数据驱动，新增皮肤只加 `assets/themes/{name}/` 目录 + 一个 `theme.tres`，零代码改动

---

## 2. 目录结构（遵循 AGENTS.md 规范）

```
MoeChess/
├── AGENTS.md / README.md
├── spec/                      # 版本目标、产品范围、交付规格
│   ├── v1.0-spec.md           # 全功能首版规格
│   └── milestones/            # 里程碑拆分
├── assets/                    # 游戏资源（assets/README.md 说明结构）
│   ├── themes/                # 皮肤资源，每皮肤一目录
│   │   └── cats/              # pieces/ fx/ audio/ ui/ theme.tres
│   ├── board/                 # 棋盘透视背景
│   ├── ui/  audio/            # UI 素材 / 通用音效 BGM
├── docs/                      # 文档（必须维护 docs/index.md）
│   ├── index.md               # 文档索引
│   ├── development/acceptance-standard.md  # 验收标准（AGENTS step1）
│   ├── plans/                 # 设计文档
│   ├── experience-library/    # 开发经验
│   ├── subagent-guide.md      # 子 Agent 规则
│   └── builder-reviewer-separation.md
├── scenes/                    # Godot 场景
│   ├── main.tscn              # 启动入口
│   ├── board/ pieces/ ui/ fx/ # 棋盘/棋子/UI/特效场景
└── scripts/                   # GDScript 逻辑、调试、测试
    ├── core/                  # 核心逻辑层（纯逻辑，无渲染，可单测）
    ├── ai/                    # AI 层（minimax + alpha-beta）
    ├── view/                  # 视觉层（程序化透视/视角翻转）
    ├── theme/                 # 皮肤资源加载
    ├── input/                 # 输入抽象（鼠标/触屏）
    ├── ui/                    # UI 逻辑
    ├── states/                # 游戏状态机
    ├── debug/                 # 调试入口（默认关闭的辅助层）
    └── tests/                 # 测试脚本
```

**强制约束**（AGENTS.md）：
- `docs/index.md` 每次新增文档必须同步更新
- 正式视觉验收截图和交付说明默认不显示调试辅助层；带调试辅助层的截图必须在文件名或报告里明确标注

---

## 3. 核心数据模型（`scripts/core/`）

象棋规则的纯逻辑层，零 Godot 节点依赖，可脱离场景独立单测。

### 3.1 棋盘表示

9 路 × 10 行，`Vector2i(col, row)`，col 0-8，row 0-9。
- 红方占 row 0-4（下方/玩家方）
- 黑方占 row 5-9（上方/电脑方）

### 3.2 枚举（遵循"状态机用枚举"规范）

```gdscript
enum PieceType { KING, ADVISOR, ELEPHANT, HORSE, CHARIOT, CANNON, PAWN }
enum Side { RED, BLACK }
```

### 3.3 核心类（均 `RefCounted`，无节点）

- `Piece`：`type` + `side` + `pos`，不可变值对象
- `Move`：`from` + `to` + `captured`（可空）
- `BoardState`：`grid[10][9]`（存 Piece/null）+ `side_to_move` + `move_history` + 双方被吃子列表
- `MoveGenerator`：策略模式，每种棋子一个生成器函数，`generate_pseudo_moves(state, piece) -> Array[Move]`
- `RuleValidator`：`is_legal(state, move)`（过滤送将）+ `is_in_check(state, side)` + `is_checkmate(state, side)`
- `GameController`：`apply_move(state, move)` 生成新状态（不可变更新，便于悔棋/AI 搜索/复盘）

### 3.4 关键取舍

`apply_move` 返回**新 BoardState** 而非原地修改。AI 搜索时可随意分支不污染主状态，悔棋/复盘只需回退指针。代价是对象分配开销，但中国象棋搜索深度 6 层以内可接受。

---

## 4. 皮肤系统（`scripts/theme/` + `assets/themes/`）

游戏特色的核心，数据驱动。新增皮肤只需加一个 `assets/themes/{name}/` 目录 + 一个 `theme.tres`，零代码改动。

### 4.1 六类萌物皮肤（第一版）

| # | 萌物类 | 皮肤名（暂定） | 品种→棋子映射示例 | 区分方式 |
|---|--------|----------------|-------------------|---------|
| 1 | 猫 | 猫咪乐园 | 布偶=将、英短=车、橘猫=炮… | 按品种 |
| 2 | 狗 | 汪汪战队 | 金毛=将、柯基=车、二哈=炮… | 按品种 |
| 3 | 仓鼠 | 仓鼠团子 | 银狐=将、布丁=车、三线=炮… | 按品种 |
| 4 | 鱼 | 深海游园 | 锦鲤=将、斗鱼=车、小丑鱼=炮… | 按品种 |
| 5 | 鸟 | 飞羽小队 | 鹦鹉=将、麻雀=车、孔雀=炮… | 按品种 |
| 6 | 熊猫 | 熊猫竹园 | — | 按姿态/配饰（品种差异小） |

### 4.2 棋子识别：职务道具（无文字）

不用传统棋子字，改用**职务道具**让玩家识别棋子种类。道具规则**跨所有皮肤统一**，学一次通吃 6 类。

| 棋子 | 职务道具 | 视觉记忆点 |
|------|---------|-----------|
| 将/帅 | 皇冠 + 令旗 | 统帅，体态最大 |
| 士 | 小盾牌 | 护卫 |
| 象 | 象鼻帽 / 最胖体态 | 厚重 |
| 馬 | 小木马 / 马蹄项圈 | 骑乘 |
| 車 | 小战车 / 方框道具 | 直线感 |
| 炮 | 炮筒 / 炮手帽 | 发射 |
| 兵/卒 | 小兵帽 / 小旗 | 朴素，最小 |

**棋子视觉构成 = 底座 + 萌物 + 职务道具**：
- **阵营识别**：红/黑圆盘底座（保留传统棋子轮廓和阵营色）
- **种类识别**：职务道具（皇冠永远是将，炮筒永远是炮）
- **萌物特色**：萌物主体居中，品种对应棋子类型（趣味性来源）

游戏内配**图鉴页**展示道具→棋子对照，首次进入引导一次。

### 4.3 ThemeResource 结构

```gdscript
class ThemeResource extends Resource:
  @export var theme_name: String            # "猫咪乐园"
  @export var theme_id: String              # "cats"
  @export var pieces: Dictionary            # 14 项 SpriteFrames
                                            # 键: "red_king".."black_pawn"
  @export var kill_fx: PackedScene          # 主动击杀特效场景
  @export var killed_fx: PackedScene        # 被击杀特效场景
  @export var victory_anim: SpriteFrames    # 胜利动画（全队场景）
  @export var defeat_anim: SpriteFrames     # 战败动画（全队场景）
  @export var sfx: ThemeSFXResource         # 列阵/移动/击杀/胜利音效
  @export var piece_mapping: Dictionary     # 品种→棋子类型映射说明
  @export var speed_button_idle: Texture2D  # 加速按钮：悠闲表情头像
  @export var speed_button_fast: Texture2D  # 加速按钮：着急表情头像
```

14 项棋子资源 = 7 类型 × 2 阵营（将/士/象/马/车/炮/兵卒）。`pieces` 键名固定为 `{side}_{type}`（如 `red_king`、`black_cannon`），保证皮肤间可互换。

### 4.4 棋子动画状态（每个 SpriteFrames 含 5 状态）

| 状态 | 触发 | 动画示例 | 音效 |
|------|------|---------|------|
| `idle` | 待机 | 轻微呼吸/晃动 | — |
| `selected` | 被选中 | 兴奋反应（跳/竖耳） | select_sfx |
| `moving` | 移动中 | 行走/奔跑 | move_sfx |
| `killing` | 主动击杀 | 攻击动作 | kill_sfx |
| `killed` | 被击杀 | 倒下/消散 | killed_sfx |

### 4.5 皮肤级动画/特效/音效

- `victory_anim` + `victory_sfx`：胜利庆祝（全队场景）
- `defeat_anim` + `defeat_sfx`：战败沮丧（全队场景）
- `kill_fx` / `killed_fx`：击杀/被击杀粒子特效场景
- `formation_sfx`：视角切换列阵音效（双人对战换边时）

### 4.6 ThemeSFXResource（皮肤级统一，动作级差异化）

```gdscript
class ThemeSFXResource extends Resource:
  @export var formation_sfx: AudioStream   # 列阵/视角切换
  @export var select_sfx: AudioStream      # 选中
  @export var move_sfx: AudioStream        # 移动/落子
  @export var kill_sfx: AudioStream        # 击杀
  @export var killed_sfx: AudioStream      # 被击杀
  @export var victory_sfx: AudioStream     # 胜利
  @export var defeat_sfx: AudioStream      # 战败
```

音效分级：皮肤级统一（每皮肤一套，符合"不同皮肤音效不同"），动作级差异化（各动作音效不同）。

### 4.7 动效节奏与加速

- **正常速度偏慢**（2-3 秒/动作参考值，非硬性），体现萌物缓慢可爱
- **加速按钮**（1x ⇄ 2x），影响所有动效播放速度
- **加速按钮萌物表情**：跟随当前皮肤切换头像
  - 正常速度：悠闲表情（闭眼打盹的猫头 / 吐舌头的狗头）
  - 加速 2x：着急表情（瞪眼张嘴的猫头 / 狂奔的狗头）
- **实现**：全局动画速度倍率，视觉层通过 `AnimatedSprite2D.speed_scale` 应用

### 4.8 ThemeManager（单例）

扫描 `assets/themes/*/theme.tres`，登记所有皮肤；提供 `get_current()` / `switch_to(theme_id)`；切换时通过信号通知视觉层重载棋子贴图。

### 4.9 资源量预估

6 类 × 14 棋子 × 5 动画状态 = 420 个动画序列 + 皮肤级动画/特效/音效 + 加速按钮头像。AI 生成工作量大但规格清晰可批量生产。

---

## 5. AI 引擎（`scripts/ai/`）

纯 GDScript，依赖核心逻辑层，无渲染依赖。结构分三层。

### 5.1 搜索层 SearchEngine

负责 `choose_move(state, difficulty) -> Move`：
- 算法：minimax + alpha-beta 剪枝 + 走法排序（吃子优先，提升剪枝效率）
- 难度梯度：**深度 + 评估精度 + 随机性**三轴组合（不是简单改深度）

| 难度 | 搜索深度 | 评估函数 | 随机扰动 |
|------|---------|---------|---------|
| 低 | 2 层 | 仅子力价值 | 同分走法随机选（模拟新手失误） |
| 中 | 4 层 | 子力 + 位置表 | 极小扰动 |
| 高 | 6 层 | 子力 + 位置表 + 机动性 + 威胁评估 | 无扰动，严格最优 |

### 5.2 评估层 Evaluator

`evaluate(state, side) -> int`：
- **子力价值**：将∞ / 车9 / 炮4.5 / 马4 / 士2 / 象2 / 兵1（经典中国象棋估值）
- **位置表 PieceSquareTable**：每种棋子在不同格子的加分（如马跳卧槽位加分、兵过河加分），红黑镜像
- **高难度额外项**：机动性（合法走法数）、威胁（攻击对方高价值子）、防御（保护己方子）

### 5.3 性能保障

- 走法生成先用数组跑通，后续可用位运算优化格子判断
- **置换表 TranspositionTable**（Zobrist hashing）缓存已搜局面，6 层深度必备
- AI 计算放 `WorkerThread`，避免卡主线程；计算中显示"思考中"动画
- **迭代加深 + 时间限制**（备用）：若高难度单步超 2 秒，加 1.5 秒时间限制返回当前最优

### 5.4 关键取舍

低难度靠随机扰动模拟新手，比单纯降深度更自然，新手感更强。高难度 6 层 + 评估，纯 GDScript 下单步约 0.5-2 秒（实测后调），可接受。

---

## 6. 2.5D 视角实现（`scripts/view/`）

核心视觉特色。2D 节点 + 程序化透视，不依赖 3D。

### 6.1 棋盘透视背景（`assets/board/`）

预渲染的透视棋盘图——近大远小的格子，轻度倾斜（俯视角约 15-20°）。准备两套：玩家方在下的透视 + 对手方在下的透视（双人对战翻转用）。倾向两套图保稳（一套图 + `scale.y = -1` 镜像可能因棋盘纹路不对称有瑕疵）。

### 6.2 棋子程序化透视（PieceView）

每个棋子 `AnimatedSprite2D`，按所在 `row` 计算缩放和位置偏移，模拟"近大远小"：

```gdscript
# row 0(最近/玩家方)→1.0 缩放, row 9(最远)→0.75 缩放
var scale_factor = lerp(1.0, 0.75, float(row) / 9.0)
var y_offset = base_y + row * row_height  # 行高随透视递减
```

棋子美术按"斜视角度"生成（统一俯视角，与棋盘透视一致），程序不旋转棋子贴图，只做缩放和定位。

### 6.3 视角翻转（双人对战换边）

行动方切换时，执行翻转序列：
1. 播放 `formation_sfx`（列阵音效，皮肤专属）
2. 棋盘背景切换到对手方透视图
3. 全部棋子重新计算缩放/位置（从下大上小 → 上大下小）
4. 棋子贴图无翻转（始终斜视面对当前行动方视角），用 Tween 做翻转过渡动画（约 0.4 秒）

### 6.4 坐标转换

`board_to_screen(pos) -> Vector2` 和 `screen_to_board(point) -> Vector2i`，封装透视映射，输入层和视觉层共用。双人对战翻转后，映射函数根据当前视角重算。

### 6.5 关键取舍

棋子贴图不随翻转旋转，因为"斜视面对当前行动方"意味着翻转后棋子还是正面朝向新的下方玩家——所以翻转的是**棋盘透视 + 棋子位置布局**，不是棋子贴图朝向。一套棋子美术通吃两个视角。

---

## 7. 游戏流程状态机（`scripts/states/`）

`GameStateMachine` 管理全局流程，状态间单向切换，每个状态对应一个场景/控制器。

### 7.1 全局状态机

```
Boot → MainMenu → SelectTheme → SelectMode → Playing → Gameover
                                    ↑            ↓
                                  (重开)      Paused ↔ (Esc)
                                                ↓
                                            Replay(复盘)
```

| 状态 | 职责 | 退出条件 |
|------|------|---------|
| `Boot` | 加载配置、初始化 ThemeManager、读取存档 | 资源就绪 → MainMenu |
| `MainMenu` | 主菜单：开始/图鉴/设置/退出 | 选"开始" → SelectTheme |
| `SelectTheme` | 选 6 类萌物皮肤（预览轮播） | 确认 → SelectMode |
| `SelectMode` | 选人机(低/中/高) / 双人 | 确认 → Playing |
| `Playing` | 对局主循环 | 将死/认输 → Gameover |
| `Paused` | 暂停（继续/重开/返回菜单） | 继续回 Playing |
| `Gameover` | 播胜利/战败动画+音效，重开/回菜单/复盘 | → SelectMode / MainMenu / Replay |
| `Replay` | 复盘模式：前进/后退/自动播放重放每步 | 退出 → MainMenu/Gameover |

### 7.2 Playing 内部子状态机

```
WaitingInput → PieceSelected → AnimatingMove → (CheckTurnEnd) → TurnSwitching
     ↑                                                              ↓
     └──────────────────────────────────────────────────────────────┘
```

- `WaitingInput`：等待当前行动方选棋子
- `PieceSelected`：已选中，等待目标格（显示可走位置提示）
- `AnimatingMove`：播放移动动画（受加速倍率影响），AI 回合自动触发
- `TurnSwitching`：双人对战时执行视角翻转 + 列阵音效；人机模式无翻转
- 将死判定在 `CheckTurnEnd`，满足则跳 `Gameover`

### 7.3 棋局记录与复盘

- **棋谱记录**：`BoardState.move_history` 每步自动落账
- **复盘模式**（`Replay` 状态）：从 Gameover 或主菜单进入，支持前进/后退/自动播放，重放每步动画+音效
- **棋谱存档**：`user://records/{timestamp}.json`，含完整走法 + 元信息（皮肤/难度/胜负）
- **记谱格式**：自定义 JSON（内部用），后续可扩展导入导出标准记谱法

### 7.4 存档点

`Playing` 状态自动保存棋谱 + 设置（皮肤/难度/加速偏好）到 `user://save.json`，重开可续局。

---

## 8. 资源管线（AI 生成规格 + 导入流程）

让"AI 生成美术"真正可落地的关键。规格统一，才能批量生产 + 自动校验。

### 8.1 棋子图规格（每张）

- 尺寸：512×512 px（导出时压缩到 256）
- 透明背景 PNG
- 视角：统一俯视斜角（与棋盘透视一致，约 15-20°）
- 构图：圆盘底座居中 + 萌物主体 + 职务道具，三者融合
- 风格约束：所有 6 类皮肤统一线条/上色风格（提供 1 张风格参考图作为锚点）

### 8.2 SpriteFrames 动画规格（每棋子 5 状态）

- 每状态 12-24 帧（视动作复杂度），24 fps
- 时长参考：idle 2-3s 循环、selected 2s、moving 2s 循环、killing 2.5s、killed 2s
- 帧序列命名：`{side}_{type}_{state}_{frame:03}.png`

### 8.3 皮肤目录约定

```
assets/themes/cats/
├── theme.tres              # ThemeResource 定义
├── pieces/                 # 14 棋子 × 5 状态的帧序列
│   ├── red_king/
│   │   ├── idle_001.png ...
│   │   └── killed_012.png
│   └── black_pawn/...
├── fx/                     # kill_fx.tscn / killed_fx.tscn
├── audio/                  # sfx 资源
├── ui/                     # speed_button_idle.png / speed_button_fast.png
└── victory.tres / defeat.tres  # 全队动画
```

### 8.4 导入校验脚本（`scripts/debug/validate_theme.gd`）

扫描 `assets/themes/*/theme.tres`，校验：14 棋子齐全、每棋子 5 状态齐全、帧数达标、命名规范、资源引用有效。校验失败列出缺项。这是 AGENTS.md 要求的"观测手段"之一。

### 8.5 AI 生成工作流

出详细 prompt 模板（含风格锚点 + 构图约束 + 帧数要求）→ 用 ComfyUI 批量生成 → 按命名规范入库 → 跑校验脚本 → 修缺项。

---

## 9. 平台与分辨率适配（`scripts/input/` + 布局策略）

6 平台 + 多分辨率，用 Godot 内置机制 + 抽象层处理。

### 9.1 分辨率适配

- 基准设计分辨率：1080×1920（竖屏，契合纵向棋盘）
- `display/window/stretch/mode = "canvas_items"`，`aspect = "expand"`：内容按基准设计，运行时自动缩放适配
- 响应式布局用 `Container` 节点：

| 设备形态 | 布局 |
|---------|------|
| 手机竖屏 | 棋盘占主体，HUD 上下分布（信息条+操作条） |
| 桌面横屏 | 棋盘居中，左右侧栏放棋谱/被吃子/操作 |
| 平板/Web 宽屏 | 同桌面；窄屏回退到上下布局 |

### 9.2 输入抽象层 InputProvider

统一输出语义事件（`piece_clicked(pos)` / `cell_clicked(pos)` / `ui_action(name)`），屏蔽底层差异：
- 桌面/Web：鼠标 `_input(event)` 处理 `InputEventMouseButton`
- 移动：触屏 `_input(event)` 处理 `InputEventScreenTouch`
- 统一转 `screen_to_board()` 命中棋子/格子

### 9.3 平台特性处理

| 平台 | 关键处理 |
|------|---------|
| 移动 | 竖屏锁定（portrait）、安全区 `DisplayServer.get_window_safe_area()`、切后台自动暂停、触屏点击区域放大 |
| Web(HTML5) | 资源分批加载（避免首屏卡）、禁用多线程 `Thread`（Web 限制）、用 `JavaScriptBridge` 处理浏览器暂停、导出压缩 `.pck` |
| 桌面 | 可调窗口（设最小尺寸）、ESC 暂停、鼠标悬停高亮 |

### 9.4 导出配置

`export_presets.cfg` 每平台一个 preset，差异项：图标、方向锁定、权限、资源过滤（Web 不打包未用资源）。CI 可批量导出。

### 9.5 平台宏

用 `OS.has_feature("web")` / `"android"` 等做运行时分支，避免平台耦合散落各处。

---

## 10. 测试与验收策略（遵循 AGENTS.md 流程）

严格按 AGENTS.md 的 11 步流程执行，子 Agent 分工：`test-author` 写测试、`acceptance-checker` 核对覆盖、`builder` 实现、`visual-reviewer` 视觉复核、`reviewer` 综合复核。

### 10.1 测试分层

| 层级 | 范围 | 工具 |
|------|------|------|
| 单元测试 | 核心逻辑层：走法生成、合法性、将军/将死、AI 评估函数 | GUT（Godot Unit Test） |
| 集成测试 | AI 搜索端到端、皮肤加载切换、状态机流转、复盘回放 | GUT + 测试场景 |
| 视觉验收 | 动效播放、视角翻转、UI 布局、加速按钮 | 截图对比 + 画面基准 |
| 平台验收 | 6 平台导出 + 运行 + 分辨率适配 | 各平台实机/模拟器 |

### 10.2 观测手段（AGENTS step4 要求）

- 统一日志 `Logger`（分级 DEBUG/INFO/WARN/ERROR，可写文件）
- 调试辅助层（默认关闭，显式参数开启）：显示坐标、可走位置、AI 评估分、FPS——AGENTS 要求正常运行不显示
- 测试入口 `scripts/debug/`：
  - `validate_theme.gd`（资源校验）
  - `run_ai_benchmark.gd`（AI 强度/耗时）
  - `play_replay.gd`（回放棋谱）

### 10.3 验收标准

见 `docs/development/acceptance-standard.md`（草案经立立确认后作为外部合格线，AI 不得自行改写）。覆盖维度：核心规则正确性、AI 三难度梯度、6 类皮肤完整性、视角翻转+列阵音效、动效加速、棋局记录复盘、6 平台适配。

### 10.4 关键验收红线

- 规则零错误（送将判定、将死判定必须 100% 准确）
- AI 高难度不得送子、不得违反规则
- 6 类皮肤校验脚本全通过
- 双人对战翻转动画 + 列阵音效必须触发
- 正常运行截图不得出现调试辅助层

---

## 11. 里程碑建议（实施顺序）

虽为全功能首版，实施仍按依赖顺序推进（详见 `spec/milestones/`）：

1. **M1 核心逻辑层**：棋盘状态 + 走法生成 + 合法判定 + 将军/将死（纯逻辑 + 单测）
2. **M2 AI 引擎**：minimax + 评估 + 三难度（依赖 M1）
3. **M3 视觉骨架**：棋盘 + 棋子渲染 + 程序化透视 + 坐标转换（占位美术）
4. **M4 状态机 + 输入**：全局流程 + Playing 子状态机 + InputProvider
5. **M5 皮肤系统**：ThemeResource + ThemeManager + 1 套皮肤（猫）接入
6. **M6 动效与音效**：5 动画状态 + 加速按钮 + 音效触发
7. **M7 视角翻转**：双人对战翻转 + 列阵音效
8. **M8 棋局记录复盘**：棋谱存档 + Replay 状态
9. **M9 全部 6 类皮肤**：AI 生成 + 入库 + 校验
10. **M10 平台适配与导出**：6 平台 preset + 适配验证

---

## 12. 开放项（待后续确认）

- 6 类皮肤的具体品种清单（猫狗仓鼠鱼鸟的品种→棋子完整映射）
- AI 高难度的实测耗时（实现后 benchmark 调参）
- Web 平台的资源分批加载策略细节
- BGM 音乐风格与来源
- 是否需要成就系统/排行榜（当前规格未含）

---

_本设计文档经立立逐段确认（2026-07-28），作为萌象棋 v1.0 的设计源头。后续变更须经立立确认并更新本文档。_
