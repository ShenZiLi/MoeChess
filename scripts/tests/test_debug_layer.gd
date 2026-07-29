## 调试辅助层单元测试 — 验收 I2（默认关闭）/ I3（显式开启）
## 关联：docs/development/test-cases.md TC-I2-001 ~ TC-I2-002、acceptance-standard.md I2/I3
## 关联实现：scripts/debug/debug_layer.gd
##
## 注意：I3（截图无调试层）和 I4（截图文件名标注）属于视觉/平台验收范围，不在此 GUT 测试
extends GutTest

# -------------------- TC-I2-001：默认关闭 --------------------

## DebugLayer 默认 is_enabled() 返回 false（new 出来的实例默认关闭）
func test_debug_layer_default_disabled() -> void:
	# arrange：new 一个 DebugLayer（不进入场景树，避免 _ready 中检查命令行参数）
	var layer: DebugLayer = DebugLayer.new()
	# act
	var enabled: bool = layer.is_enabled()
	# assert：默认关闭
	assert_false(enabled, "DebugLayer 默认应关闭（is_enabled=false）")
	# visible 也应为 false
	assert_false(layer.visible, "DebugLayer 默认 visible 应为 false")
	# 清理
	layer.queue_free()

# -------------------- TC-I2-002：显式开启 --------------------

## set_enabled(true) 后 is_enabled() 返回 true
func test_debug_layer_explicit_enable() -> void:
	# arrange
	var layer: DebugLayer = DebugLayer.new()
	# act
	layer.set_enabled(true)
	# assert
	assert_true(layer.is_enabled(), "set_enabled(true) 后 is_enabled 应为 true")
	assert_true(layer.visible, "set_enabled(true) 后 visible 应为 true")
	# 关闭后再次检查
	layer.set_enabled(false)
	assert_false(layer.is_enabled(), "set_enabled(false) 后 is_enabled 应为 false")
	assert_false(layer.visible, "set_enabled(false) 后 visible 应为 false")
	# 清理
	layer.queue_free()

# -------------------- 额外：update_info 不抛异常 --------------------

## update_info 接受字典并刷新显示
func test_debug_layer_update_info() -> void:
	# arrange
	var layer: DebugLayer = DebugLayer.new()
	layer.set_enabled(true)
	# act
	layer.update_info({"fps": 60, "turn": 5, "ai_score": 100, "ai_think_ms": 200})
	# assert：不抛异常
	assert_true(layer.is_enabled(), "update_info 后 DebugLayer 仍应启用")
	# 清理
	layer.queue_free()
