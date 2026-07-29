## 平台配置（RefCounted，集中处理平台分支）
## 关联：docs/plans/2026-07-28-moechess-design.md §9.3/§9.5、docs/development/acceptance-standard.md H8
##
## 红线（H8）：平台分支用 OS.has_feature() 集中处理，不散落到其他层。
## 其他层应通过 PlatformConfig 查询平台能力，不直接调用 OS.has_feature。
##
## 使用方式：
##   var pc := PlatformConfig.new()
##   if pc.is_mobile(): ...
##   if pc.should_use_threads(): ...
class_name PlatformConfig
extends RefCounted

## 是否移动平台（Android / iOS）
## H5：移动端竖屏锁定 + 安全区适配 + 切后台暂停
func is_mobile() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")

## 是否 Web 平台
## H6：Web 端资源分批加载，无多线程，浏览器暂停处理
func is_web() -> bool:
	return OS.has_feature("web")

## 是否桌面平台（Windows / macOS / Linux）
## H4：桌面横屏布局 + 可调窗口 + ESC 暂停 + 鼠标悬停高亮
func is_desktop() -> bool:
	return OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linux")

## 返回竖屏锁定的 DisplayServer.SCREEN_ORIENTATION 值
## 移动端锁定竖屏（H5）；桌面/Web 不锁定（返回 LANDSCAPE 由用户/系统决定）
## 返回值用于 DisplayServer.screen_set_orientation()
func orientation_lock() -> int:
	if is_mobile():
		return DisplayServer.SCREEN_ORIENTATION_PORTRAIT
	return DisplayServer.SCREEN_ORIENTATION_LANDSCAPE

## 是否应使用多线程
## Web 平台禁用 Thread（H6：Web 限制）；其他平台启用
func should_use_threads() -> bool:
	return not is_web()

## 当前平台标识字符串（调试/日志用）
func platform_id() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("ios"):
		return "ios"
	if is_web():
		return "web"
	if OS.has_feature("windows"):
		return "windows"
	if OS.has_feature("macos"):
		return "macos"
	if OS.has_feature("linux"):
		return "linux"
	return "unknown"
