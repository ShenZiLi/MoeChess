# assets/ 资源结构说明

萌象棋的所有游戏资源存放目录。资源采用数据驱动，皮肤以目录为单位组织。

---

## 目录结构

```
assets/
├── README.md                 # 本文件
├── themes/                   # 皮肤资源（每皮肤一目录）
│   ├── cats/                 # 猫咪乐园
│   ├── dogs/                 # 汪汪战队
│   ├── hamsters/             # 仓鼠团子
│   ├── fish/                 # 深海游园
│   ├── birds/                # 飞羽小队
│   └── pandas/               # 熊猫竹园
├── board/                    # 棋盘透视背景
├── ui/                       # UI 素材（图标/按钮/面板底纹）
└── audio/                    # 通用音效 / BGM
```

---

## 皮肤目录约定（`themes/{theme_id}/`）

每个皮肤是一个独立目录，内含一个 `theme.tres`（`ThemeResource`）定义 + 各类资源文件。

```
assets/themes/cats/
├── theme.tres                  # ThemeResource 定义（皮肤入口）
├── pieces/                     # 14 棋子 × 5 状态的帧序列
│   ├── red_king/               # 红方将
│   │   ├── idle_001.png
│   │   ├── idle_002.png
│   │   ├── ...
│   │   ├── selected_001.png
│   │   ├── moving_001.png
│   │   ├── killing_001.png
│   │   └── killed_001.png
│   ├── red_advisor/            # 红方士
│   ├── red_elephant/           # 红方象
│   ├── red_horse/              # 红方马
│   ├── red_chariot/            # 红方车
│   ├── red_cannon/             # 红方炮
│   ├── red_pawn/               # 红方兵
│   ├── black_king/             # 黑方将
│   ├── ... (black_advisor ~ black_pawn)
│   └── black_pawn/
├── fx/                         # 特效场景
│   ├── kill_fx.tscn            # 主动击杀特效
│   └── killed_fx.tscn          # 被击杀特效
├── audio/                      # 皮肤专属音效
│   ├── formation.wav           # 列阵/视角切换
│   ├── select.wav              # 选中
│   ├── move.wav                # 移动/落子
│   ├── kill.wav                # 击杀
│   ├── killed.wav              # 被击杀
│   ├── victory.wav             # 胜利
│   └── defeat.wav              # 战败
├── ui/                         # 皮肤专属 UI 资源
│   ├── speed_button_idle.png   # 加速按钮：悠闲表情头像（1x）
│   └── speed_button_fast.png   # 加速按钮：着急表情头像（2x）
└── anim/                       # 全队动画
    ├── victory.tres            # 胜利动画 SpriteFrames
    └── defeat.tres             # 战败动画 SpriteFrames
```

---

## 命名规范

### 棋子目录名（14 项，固定）

格式：`{side}_{type}`

| side | type | 示例 |
|------|------|------|
| `red` / `black` | `king` / `advisor` / `elephant` / `horse` / `chariot` / `cannon` / `pawn` | `red_king`、`black_cannon` |

### 帧序列文件名

格式：`{state}_{frame:03}.png`

- state：`idle` / `selected` / `moving` / `killing` / `killed`
- frame：三位数字，从 `001` 起

示例：`idle_001.png`、`killing_012.png`

### 音效文件名（固定）

`formation.wav` / `select.wav` / `move.wav` / `kill.wav` / `killed.wav` / `victory.wav` / `defeat.wav`

---

## 棋子图规格

- **尺寸**：512×512 px（导出时压缩到 256）
- **格式**：透明背景 PNG
- **视角**：统一俯视斜角（与棋盘透视一致，约 15-20°）
- **构图**：圆盘底座居中 + 萌物主体 + 职务道具，三者融合于一张图
- **阵营底座**：红方红边圆盘 / 黑方黑边圆盘
- **风格约束**：所有 6 类皮肤统一线条/上色风格（提供 1 张风格参考图作为锚点）

### 职务道具映射（跨皮肤统一）

| 棋子 | 职务道具 |
|------|---------|
| 将/帅 | 皇冠 + 令旗 |
| 士 | 小盾牌 |
| 象 | 象鼻帽 / 最胖体态 |
| 馬 | 小木马 / 马蹄项圈 |
| 車 | 小战车 / 方框道具 |
| 炮 | 炮筒 / 炮手帽 |
| 兵/卒 | 小兵帽 / 小旗 |

---

## SpriteFrames 动画规格

- **帧率**：24 fps
- **每状态帧数**：12-24 帧（视动作复杂度）
- **时长参考**（正常速度，偏慢可爱）：
  - `idle`：2-3s 循环
  - `selected`：2s
  - `moving`：2s 循环
  - `killing`：2.5s
  - `killed`：2s
- **加速**：1x / 2x，通过 `AnimatedSprite2D.speed_scale` 应用

---

## ThemeResource 字段

```gdscript
class ThemeResource extends Resource:
  @export var theme_name: String            # 显示名 "猫咪乐园"
  @export var theme_id: String              # 标识 "cats"
  @export var pieces: Dictionary            # 14 项 SpriteFrames，键 "red_king".."black_pawn"
  @export var kill_fx: PackedScene          # 主动击杀特效
  @export var killed_fx: PackedScene        # 被击杀特效
  @export var victory_anim: SpriteFrames    # 胜利全队动画
  @export var defeat_anim: SpriteFrames     # 战败全队动画
  @export var sfx: ThemeSFXResource         # 七音效集
  @export var piece_mapping: Dictionary     # 品种→棋子类型映射说明
  @export var speed_button_idle: Texture2D  # 加速按钮悠闲头像
  @export var speed_button_fast: Texture2D  # 加速按钮着急头像
```

---

## 资源校验

运行校验脚本检查皮肤完整性：

```bash
# 在 Godot 编辑器内运行，或通过命令行
godot --script scripts/debug/validate_theme.gd
```

校验项：
- 14 棋子目录齐全
- 每棋子 5 状态齐全
- 每状态帧数达标（≥12）
- 帧序列命名规范
- `theme.tres` 资源引用有效（无空引用/断链）
- 音效 7 项齐全
- 加速按钮头像 2 项齐全

校验失败会列出具体缺项，修复后重跑。

---

## 新增皮肤流程

1. 复制 `assets/themes/cats/` 为 `assets/themes/{new_id}/`
2. 用 AI（ComfyUI）按规格生成新萌物的棋子帧序列，覆盖 `pieces/`
3. 生成新音效到 `audio/`，新特效到 `fx/`，新头像到 `ui/`，新全队动画到 `anim/`
4. 修改 `theme.tres` 的 `theme_name` / `theme_id` / `piece_mapping`
5. 运行 `validate_theme.gd` 校验通过
6. `ThemeManager` 自动扫描登记，无需改代码

---

## 通用资源（`assets/board/`、`assets/ui/`、`assets/audio/`）

- `assets/board/`：棋盘透视背景（玩家方透视 + 对手方透视两套）
- `assets/ui/`：通用 UI 图标/按钮/面板底纹（非皮肤专属）
- `assets/audio/`：通用音效 / BGM（非皮肤专属）

---

_资源规格与设计文档 `docs/plans/2026-07-28-moechess-design.md` 第 8 节一致。变更须同步更新本文件。_
