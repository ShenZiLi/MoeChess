## 皮肤校验脚本单元测试 — 验收 I5（validate_theme 入口）+ C8（6 皮肤校验通过）
## 关联：docs/development/test-cases.md TC-I5-001 / TC-C8-001、acceptance-standard.md I5/C8
## 关联实现：scripts/debug/validate_theme.gd
extends GutTest

# -------------------- TC-I5-001：validate_all 返回 Dictionary --------------------

## validate_all() 返回 Dictionary 含 themes / all_valid 字段
func test_validate_all_returns_dict() -> void:
	# arrange & act
	var report: Variant = ValidateTheme.validate_all()
	# assert：返回 Dictionary
	assert_true(report is Dictionary, "validate_all 应返回 Dictionary")
	if not (report is Dictionary):
		return
	var d: Dictionary = report
	# 含 themes 数组字段
	assert_true(d.has("themes"), "报告应含 themes 字段")
	assert_true(d["themes"] is Array, "themes 字段应为 Array")
	# 含 all_valid 布尔字段
	assert_true(d.has("all_valid"), "报告应含 all_valid 字段")

# -------------------- TC-C8-001：cats 皮肤校验通过 --------------------

## validate_theme 对 cats 皮肤应通过（valid=true）
func test_validate_theme_for_cats() -> void:
	# arrange
	var theme_path: String = "res://assets/themes/cats/theme.tres"
	if not ResourceLoader.exists(theme_path):
		pending("cats/theme.tres 不存在，跳过")
		return
	# act
	var report: Dictionary = ValidateTheme.validate_theme(theme_path)
	# assert：返回非空 Dictionary
	assert_false(report.is_empty(), "validate_theme 应返回非空 Dictionary")
	# valid 字段为 true（cats 皮肤应通过校验）
	assert_true(bool(report.get("valid", false)), "cats 皮肤应通过校验：%s" % str(report.get("errors", [])))
	# id 字段为 "cats"
	assert_eq(String(report.get("id", "")), "cats", "校验报告 id 应为 cats")
