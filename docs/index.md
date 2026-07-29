# 萌象棋 文档索引

> AGENTS.md 强制要求：新增文档时必须同步更新本索引。

---

## 设计与规格

| 文档 | 说明 | 状态 |
|------|------|------|
| [docs/plans/2026-07-28-moechess-design.md](plans/2026-07-28-moechess-design.md) | v1.0 完整设计文档（架构/数据模型/皮肤/AI/视角/状态机/资源管线/适配/测试） | 已确认 |
| [spec/v1.0-spec.md](../spec/v1.0-spec.md) | v1.0 全功能首版产品规格（范围/交付物/里程碑） | 已确认 |
| [spec/milestones/](../spec/milestones/) | 里程碑拆分（M1-M10） | 待建 |

## 验收与流程

| 文档 | 说明 | 状态 |
|------|------|------|
| [docs/development/acceptance-standard.md](development/acceptance-standard.md) | v1.0 验收标准（已冻结为外部合格线） | 已冻结 |
| [docs/development/test-cases.md](development/test-cases.md) | v1.0 测试用例（A1-J4 共 73 条验收 / 174 个用例） | 已确认 |
| [docs/development/acceptance-coverage.md](development/acceptance-coverage.md) | 验收标准覆盖核对报告（acceptance-checker，73/73 完全覆盖） | 已完成 |
| [docs/development/static-check-report.md](development/static-check-report.md) | 静态检查报告（错误 2 已修复，警告 9，提示 4） | 已完成 |
| [docs/development/visual-review-report.md](development/visual-review-report.md) | 视觉复核报告（visual-reviewer，7 通过 / 9 不通过 / 2 警告，根因：编排层缺失） | 已完成 |
| [docs/development/reviewer-report.md](development/reviewer-report.md) | 综合复核报告（reviewer，结论：有条件通过） | 已完成 |
| [docs/subagent-guide.md](subagent-guide.md) | 子 Agent 协作规则 | 待建 |
| [docs/builder-reviewer-separation.md](builder-reviewer-separation.md) | 写代码 AI 与挑毛病 AI 分离规则 | 待建 |

## 资源

| 文档 | 说明 | 状态 |
|------|------|------|
| [assets/README.md](../assets/README.md) | 资源结构说明（皮肤目录约定/命名规范/ThemeResource/校验脚本） | 已确认 |

## 经验库

| 文档 | 说明 | 状态 |
|------|------|------|
| [docs/experience-library/README.md](experience-library/README.md) | 开发经验（EX-001~EX-007 已解决 7 项 + 9 条复发规则） | 持续积累 |

## 交付回执

| 文档 | 说明 | 状态 |
|------|------|------|
| [docs/development/final-delivery-note.md](development/final-delivery-note.md) | 主 Agent 最终交付总结（step11，含红线达标核对与运行时待验证清单） | 已完成 |

---

## 文档维护规则（AGENTS.md）

1. 新增任何文档必须在本索引登记
2. 文档状态变更（草案→确认）同步更新
3. 验收标准是外部合格线，AI 不得自行改写
4. 设计文档变更须经立立确认

---

_最后更新：2026-07-29（新增 final-delivery-note.md；经验库更新至 EX-007）_
