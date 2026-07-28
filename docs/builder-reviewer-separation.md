# 写代码 AI 与挑毛病 AI 分离规则

> AGENTS.md 引用文档。防止"自己写自己审"导致验收失真。

## 1. 核心原则

**写实现的 Agent 不得担任复核角色**。同一轮任务里：

- `builder`（写实现）不能担任 `visual-reviewer`
- `builder`（写实现）不能担任 `reviewer`
- `builder` 不能为了让测试通过而降低验收标准或测试要求
- `test-author` 写的测试不能由 `test-author` 自己核对覆盖（`acceptance-checker` 必须独立）

## 2. 上下文隔离

- 复核 Agent 与写实现 Agent 必须是**不同上下文**（不同子 Agent 调用）
- 复核 Agent 默认只读，不修代码
- 复核 Agent 只看：spec、验收标准、实现代码、测试代码、运行结果

## 3. 复核流程（AGENTS.md step 7-10）

1. **测试通过** → 进入视觉复核（如涉及 HUD/VFX/画面基准）
2. **visual-reviewer** 只读复核：对照画面基准 + 真实运行截图
   - 通过 → 进入综合复核
   - 不通过 → 汇报失败 → 修复 → 回 step 6（重测）
3. **reviewer** 综合只读复核：先核对验收标准，再看代码质量
   - 通过 → 主 Agent 统一复核
   - 不通过 → 汇报失败 → 修复 → 回 step 6（重测）

## 4. 主 Agent 责任

- 主 Agent 不能只照搬子 Agent 结论
- 必须统一复核所有改动
- 必须运行必要验证（不依赖子 Agent 自报）
- 最终结论由主 Agent 负责

## 5. 视觉复核触发条件

以下改动**必须**触发 `visual-reviewer`：

- HUD
- 升级弹窗
- 结算面板
- VFX（特效）
- 场景观感
- 画面基准

测试通过后必须先 `visual-reviewer`，再 `reviewer`。

---

_本规则随 AGENTS.md 演进。变更须经立立确认。_
