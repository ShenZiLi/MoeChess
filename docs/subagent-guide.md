# 子 Agent 协作规则

> AGENTS.md 引用文档。规定主 Agent 派发子 Agent 时的协作规范。

## 1. 角色定义（来自 AGENTS.md）

| 角色 | 职责 | 可读写范围 | 限制 |
|------|------|-----------|------|
| `builder` | 写游戏实现 | 代码、场景、必要资源 | 不改验收标准，不做复核 |
| `test-author` | 写/维护测试 | 测试脚本、测试文档 | 不写实现代码 |
| `acceptance-checker` | 核对验收标准覆盖 | 只读 | 不写代码、不写测试 |
| `visual-reviewer` | 视觉只读复核 | 只读 | 不写代码、不修 UI |
| `reviewer` | 综合只读复核 | 只读 | 不写代码 |

## 2. 派发要求（AGENTS.md step 派发前）

主 Agent 派发子 Agent 前必须给出：

1. **spec**：相关规格文档路径
2. **验收标准**：相关条目（A1-A10 / B1-B8 / ... ）
3. **测试入口**：如何运行验证（命令、脚本路径）
4. **允许读写范围**：明确文件/目录白名单
5. **返回要求**：期望产出（文件路径、报告格式）

## 3. 上下文隔离

- 每个子 Agent 独立上下文，不继承主 Agent 历史
- 派发时主 Agent 必须提供完整背景（不能假设子 Agent 知道前置决策）
- 同一轮任务里，写实现的 Agent 不能担任 `visual-reviewer` 或 `reviewer`

## 4. 失败处理

- 子 Agent 失败时汇报具体失败项，不掩盖
- 失败经验更新到 `docs/experience-library/`
- 主 Agent 不能只照搬子 Agent 结论，必须统一复核

## 5. 产出规范

- 测试用例文档输出到 `docs/development/`
- 测试脚本输出到 `scripts/tests/`
- 经验记录输出到 `docs/experience-library/`
- 任何新增文档必须同步更新 `docs/index.md`

---

_本规则随 AGENTS.md 演进。变更须经立立确认。_
