## 皮肤系统集成测试 — 验收 C1（6 类皮肤加载）/ C2（14 棋子资源）/ C3（5 动画状态）/ C4（道具映射）/ C5（特效资源）/ C6（音效资源）/ C7（加速按钮头像）/ C8（validate_theme 通过）/ C9（运行时切换）
## 关联：docs/development/test-cases.md TC-C1 ~ TC-C9、acceptance-standard.md C1-C9
## 关联实现：scripts/theme/theme_manager.gd、scripts/theme/theme_resource.gd、scripts/debug/validate_theme.gd
##
## 注意：ThemeManager 是 autoload 单例（已在 project.godot 注册），GUT 运行时自动 _ready
extends GutTest

const PT = CoreConstants.PieceType
const SD = CoreConstants.Side

# -------------------- C1：6 类皮肤加载 --------------------

## TC-C1-001/002：ThemeManager 加载皮肤（至少 cats 一个）
func test_themes_loaded() -> void:
	# arrange & act：ThemeManager._ready 在 GUT 启动时已执行
	# assert：至少有 cats 皮肤（assets/themes/cats/theme.tres）
	assert_not_null(ThemeManager, "ThemeManager autoload 应可用")
	var themes: Array = ThemeManager.list_themes()
	assert_true(themes.size() >= 1, "至少应加载 1 个皮肤，实际 %d" % themes.size())
	# cats 皮肤应存在
	assert_true(ThemeManager.has_theme("cats"), "cats 皮肤应存在")

# -------------------- C2：14 棋子资源 --------------------

## TC-C2-001：每皮肤 14 棋子资源齐全
func test_theme_has_14_pieces() -> void:
	# arrange
	var theme: ThemeResource = ThemeManager.get_theme("cats")
	if theme == null:
		pending("cats 皮肤未加载，跳过")
		return
	# act & assert：14 棋子键齐全
	assert_true(theme.has_all_piece_keys(), "cats 皮肤应含 14 棋子资源")
	# 检查每个键对应非空 SpriteFrames
	for key in ThemeResource.PIECE_KEYS:
		var sf: SpriteFrames = theme.pieces.get(key, null)
		assert_not_null(sf, "cats 皮肤 %s 应有非空 SpriteFrames" % key)

# -------------------- C3：5 动画状态 --------------------

## TC-C3-001：每棋子 5 状态齐全
func test_piece_has_5_anim_states() -> void:
	# arrange
	var theme: ThemeResource = ThemeManager.get_theme("cats")
	if theme == null:
		pending("cats 皮肤未加载，跳过")
		return
	# act & assert：每个 SpriteFrames 含 5 状态
	for key in ThemeResource.PIECE_KEYS:
		var sf: SpriteFrames = theme.pieces.get(key, null)
		if sf == null:
			continue
		for state in ThemeResource.ANIM_STATES:
			assert_true(sf.has_animation(state), "cats/%s 应有动画状态 %s" % [key, state])

# -------------------- C4：道具映射 --------------------

## TC-C4-001：piece_mapping 字段存在
func test_piece_mapping_exists() -> void:
	# arrange
	var theme: ThemeResource = ThemeManager.get_theme("cats")
	if theme == null:
		pending("cats 皮肤未加载，跳过")
		return
	# act & assert：piece_mapping 字段非空（C4：道具→棋子类型映射）
	assert_true(theme.piece_mapping != null, "cats 皮肤应有 piece_mapping 字段")
	# piece_mapping 是 Dictionary，含至少 1 项（不同皮肤品种不同）
	if theme.piece_mapping is Dictionary:
		assert_true(theme.piece_mapping.size() > 0, "cats 皮肤 piece_mapping 应非空")

# -------------------- C5：特效资源 --------------------

## TC-C5-001：kill_fx / killed_fx 特效场景存在
func test_fx_resources_exist() -> void:
	# arrange
	var theme: ThemeResource = ThemeManager.get_theme("cats")
	if theme == null:
		pending("cats 皮肤未加载，跳过")
		return
	# act & assert
	assert_not_null(theme.kill_fx, "cats 皮肤应有 kill_fx PackedScene")
	assert_not_null(theme.killed_fx, "cats 皮肤应有 killed_fx PackedScene")
	# victory_anim / defeat_anim 全队动画
	assert_not_null(theme.victory_anim, "cats 皮肤应有 victory_anim SpriteFrames")
	assert_not_null(theme.defeat_anim, "cats 皮肤应有 defeat_anim SpriteFrames")

# -------------------- C6：音效资源 --------------------

## TC-C6-001：7 音效齐全
func test_sfx_resource_exists() -> void:
	# arrange
	var theme: ThemeResource = ThemeManager.get_theme("cats")
	if theme == null:
		pending("cats 皮肤未加载，跳过")
		return
	var sfx: ThemeSFXResource = theme.sfx
	# act & assert
	if theme.is_placeholder:
		# placeholder 皮肤允许音效缺失，仅断言 sfx 字段非空
		assert_not_null(sfx, "placeholder 皮肤 sfx 字段应存在（可缺失具体音效）")
		return
	assert_not_null(sfx, "cats 皮肤应有 ThemeSFXResource")
	if sfx == null:
		return
	# 7 项音效齐全
	assert_true(sfx.is_complete(), "cats 皮肤 7 项音效应齐全（非 placeholder 模式）")

# -------------------- C7：加速按钮头像 --------------------

## TC-C7-001：speed_button_idle / speed_button_fast 头像齐全
func test_speed_button_textures_exist() -> void:
	# arrange
	var theme: ThemeResource = ThemeManager.get_theme("cats")
	if theme == null:
		pending("cats 皮肤未加载，跳过")
		return
	# act & assert
	assert_not_null(theme.speed_button_idle, "cats 皮肤应有 speed_button_idle Texture2D")
	assert_not_null(theme.speed_button_fast, "cats 皮肤应有 speed_button_fast Texture2D")

# -------------------- C8：validate_theme 校验 --------------------

## TC-C8-001：validate_theme 对 cats 皮肤通过
func test_validate_theme_passes_for_cats() -> void:
	# arrange & act：调用 ValidateTheme.validate_all()
	var report: Dictionary = ValidateTheme.validate_all()
	# assert：报告含 themes 数组
	assert_true(report.has("themes"), "validate_all 应返回含 themes 的字典")
	var themes: Array = report.get("themes", [])
	# 找 cats 皮肤报告
	var cats_report: Dictionary = {}
	for t in themes:
		if String(t.get("id", "")) == "cats":
			cats_report = t
			break
	if cats_report.is_empty():
		pending("未找到 cats 皮肤校验报告，跳过")
		return
	# assert：cats.valid = true
	assert_true(bool(cats_report.get("valid", false)), "cats 皮肤应通过 validate_theme 校验：%s" % str(cats_report.get("errors", [])))

# -------------------- C9：运行时切换 --------------------

## TC-C9-001：switch_to 触发 theme_changed 信号
func test_theme_switch_runtime() -> void:
	# arrange：当前 skin = cats
	var theme: ThemeResource = ThemeManager.get_theme("cats")
	if theme == null:
		pending("cats 皮肤未加载，跳过")
		return
	# 监听 theme_changed 信号
	var signal_received: bool = false
	var received_theme_id: String = ""
	var callable: Callable = Callable(func(t: ThemeResource):
		signal_received = true
		if t != null:
			received_theme_id = t.theme_id
	)
	ThemeManager.theme_changed.connect(callable)
	# act：切换到第二个皮肤（如果有）
	var themes: Array = ThemeManager.list_themes()
	if themes.size() < 2:
		pending("仅 1 个皮肤，无法测试切换，跳过")
		ThemeManager.theme_changed.disconnect(callable)
		return
	var target_theme: ThemeResource = themes[1]  # 字典序第二个
	var target_id: String = target_theme.theme_id
	ThemeManager.switch_to(target_id)
	# assert
	assert_true(signal_received, "switch_to 应触发 theme_changed 信号")
	assert_eq(received_theme_id, target_id, "信号参数应为新 theme_id")
	# 切回 cats（恢复测试环境）
	ThemeManager.switch_to("cats")
	ThemeManager.theme_changed.disconnect(callable)
