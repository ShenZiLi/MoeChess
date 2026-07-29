## 皮肤管理单例（autoload，已在 project.godot 注册为 ThemeManager）
## 关联：scripts/theme/theme_resource.gd、scripts/theme/theme_sfx_resource.gd、
##       docs/plans/2026-07-28-moechess-design.md §4.8、assets/README.md
##
## 职责：
## - 启动时扫描 res://assets/themes/*/theme.tres，登记所有皮肤
## - 提供 get_current() / switch_to(theme_id) / list_themes()
## - 切换时发 theme_changed(theme) 信号，视觉层订阅后重载棋子贴图
##
## 数据驱动：新增皮肤只加目录 + theme.tres，本单例无任何硬编码皮肤 id，零代码改动。
extends Node

## 皮肤切换信号（视觉层订阅此信号重载棋子贴图/音效/UI 头像）
signal theme_changed(theme: ThemeResource)

## 皮肤登记失败信号（启动时若某皮肤 theme.tres 损坏，发此信号让上层记录日志）
signal theme_load_failed(theme_id: String, reason: String)

## 皮肤根目录（res:// 相对路径）
const THEMES_ROOT: String = "res://assets/themes"

## theme.tres 文件名（与 assets/README.md 约定一致）
const THEME_FILE_NAME: String = "theme.tres"

## 启动时默认加载的皮肤 id；空字符串 = 加载扫描到的第一个
const DEFAULT_THEME_ID: String = "cats"

## 已登记皮肤：theme_id → ThemeResource
var _themes: Dictionary = {}

## 当前皮肤
var _current: ThemeResource = null

func _ready() -> void:
	_scan_and_register_themes()
	_select_default_theme()

## 扫描 res://assets/themes/*/theme.tres 登记所有皮肤
## 静默跳过无法解析的皮肤并发 theme_load_failed 信号（不中断启动）
func _scan_and_register_themes() -> void:
	var dir: DirAccess = DirAccess.open(THEMES_ROOT)
	if dir == null:
		push_warning("[ThemeManager] themes root not found: %s" % THEMES_ROOT)
		return
	dir.list_dir_begin()
	var subdir: String = dir.get_next()
	while subdir != "":
		if dir.dir_exists(subdir) and not subdir.begins_with(".") and not subdir.begins_with("_"):
			_try_register_theme(subdir)
		subdir = dir.get_next()
	dir.list_dir_end()

## 尝试登记单个皮肤目录
func _try_register_theme(theme_id: String) -> void:
	var tres_path: String = "%s/%s/%s" % [THEMES_ROOT, theme_id, THEME_FILE_NAME]
	if not ResourceLoader.exists(tres_path, "ThemeResource"):
		theme_load_failed.emit(theme_id, "theme.tres missing or not a ThemeResource: %s" % tres_path)
		return
	var theme: ThemeResource = load(tres_path) as ThemeResource
	if theme == null:
		theme_load_failed.emit(theme_id, "theme.tres failed to cast to ThemeResource: %s" % tres_path)
		return
	# 若资源里 theme_id 字段为空，用目录名兜底
	if theme.theme_id == "":
		theme.theme_id = theme_id
	# 以 theme.tres 内 theme_id 为主键（与目录名解耦，方便改名）
	_themes[theme.theme_id] = theme

## 启动时选择默认皮肤：优先 DEFAULT_THEME_ID；否则取扫描到的第一个；都没有则保持 null
func _select_default_theme() -> void:
	if _themes.is_empty():
		push_warning("[ThemeManager] no themes registered")
		return
	if DEFAULT_THEME_ID != "" and _themes.has(DEFAULT_THEME_ID):
		_current = _themes[DEFAULT_THEME_ID]
		return
	# 取字典序第一个，保证可复现
	var ids: Array = _themes.keys()
	ids.sort()
	_current = _themes[ids[0]]

## 获取当前皮肤（启动时已默认加载；若调用前未 switch_to，返回第一个皮肤）
func get_current() -> ThemeResource:
	return _current

## 切换皮肤；不存在则 push_warning 并保持原皮肤
## 切换成功后发 theme_changed 信号
func switch_to(theme_id: String) -> void:
	if not _themes.has(theme_id):
		push_warning("[ThemeManager] theme_id not registered: %s" % theme_id)
		return
	if _current != null and _current.theme_id == theme_id:
		return
	_current = _themes[theme_id]
	theme_changed.emit(_current)

## 列出所有已登记皮肤（按 theme_id 字典序）
func list_themes() -> Array[ThemeResource]:
	var out: Array[ThemeResource] = []
	var ids: Array = _themes.keys()
	ids.sort()
	for id in ids:
		out.append(_themes[id])
	return out

## 列出所有已登记皮肤的 theme_id（按字典序）
func list_theme_ids() -> Array[String]:
	var ids: Array = _themes.keys()
	ids.sort()
	var out: Array[String] = []
	for id in ids:
		out.append(id)
	return out

## 按 theme_id 查询皮肤（不存在返回 null）
func get_theme(theme_id: String) -> ThemeResource:
	return _themes.get(theme_id, null)

## 已登记皮肤数量
func theme_count() -> int:
	return _themes.size()

## 是否已登记某 theme_id
func has_theme(theme_id: String) -> bool:
	return _themes.has(theme_id)
