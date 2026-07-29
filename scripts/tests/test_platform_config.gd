## 平台配置单元测试 — 验收 H8（平台分支用 OS.has_feature() 集中处理）
## 关联：docs/development/test-cases.md TC-H8-001 / TC-H8-002、acceptance-standard.md H8
## 关联实现：scripts/input/platform_config.gd
##
## PlatformConfig 是 RefCounted，无节点依赖
extends GutTest

# -------------------- TC-H8-001：PlatformConfig 返回 bool --------------------

## is_mobile / is_web / is_desktop / should_use_threads 均返回 bool
func test_platform_config_returns_bool() -> void:
	# arrange
	var pc: PlatformConfig = PlatformConfig.new()
	# act
	var mobile: bool = pc.is_mobile()
	var web: bool = pc.is_web()
	var desktop: bool = pc.is_desktop()
	var threads: bool = pc.should_use_threads()
	# assert：所有方法返回 bool 类型
	assert_true(typeof(mobile) == TYPE_BOOL, "is_mobile 应返回 bool")
	assert_true(typeof(web) == TYPE_BOOL, "is_web 应返回 bool")
	assert_true(typeof(desktop) == TYPE_BOOL, "is_desktop 应返回 bool")
	assert_true(typeof(threads) == TYPE_BOOL, "should_use_threads 应返回 bool")
	# 应满足：threads == not web（Web 平台禁用线程）
	assert_eq(threads, not web, "should_use_threads 应等于 not is_web")

# -------------------- TC-H8-002：platform_id 返回字符串 --------------------

## platform_id 返回非空字符串
func test_platform_config_platform_id() -> void:
	# arrange
	var pc: PlatformConfig = PlatformConfig.new()
	# act
	var pid: String = pc.platform_id()
	# assert：非空字符串
	assert_false(pid == "", "platform_id 应返回非空字符串")
	# 应是 6 个已知平台之一或 "unknown"
	var known: Array = ["android", "ios", "web", "windows", "macos", "linux", "unknown"]
	assert_true(known.has(pid), "platform_id 应是已知平台之一：%s" % pid)

# -------------------- TC-H8-003：orientation_lock 返回 int --------------------

## orientation_lock 返回 DisplayServer 枚举值
func test_platform_config_orientation_lock() -> void:
	# arrange
	var pc: PlatformConfig = PlatformConfig.new()
	# act
	var orient: int = pc.orientation_lock()
	# assert：返回 int 类型
	assert_true(typeof(orient) == TYPE_INT, "orientation_lock 应返回 int")
	# 移动端应为 PORTRAIT；其他为 LANDSCAPE
	if pc.is_mobile():
		assert_eq(orient, DisplayServer.SCREEN_ORIENTATION_PORTRAIT, "移动端应锁定竖屏")
	else:
		assert_eq(orient, DisplayServer.SCREEN_ORIENTATION_LANDSCAPE, "非移动端应返回 LANDSCAPE")
