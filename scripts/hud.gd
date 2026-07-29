extends CanvasLayer
## Match HUD, styled after the dark-fantasy reference: resource panels,
## knight stats card, inventory slots, command buttons, shop / castle popups
## and a minimap. Everything reads synced state; buttons only send intents
## (affordability graying is display-only — the server re-validates).

const EntityView := preload("res://scripts/entity_view.gd")

const PANEL_BG := Color("1a1712")
const PANEL_BG_LIGHT := Color("262019")
const PANEL_BORDER := Color("8a7340")
const GOLD_TEXT := Color("e8c95a")
const GREEN := Color("4caf50")
const RED := Color("c62828")
const RED_TEXT := Color("e05f4e")
const TEXT_COLOR := Color("e8e2d0")
const DIM_TEXT := Color("9a917d")

const ITEM_ORDER := ["sword", "hammer", "boots", "armor"]
const ITEM_INFO := {
	"sword": {"name": "SWORD", "lines": ["Damage: 10", "Attack speed: 1.5/s", "Fast strikes"]},
	"hammer": {"name": "HAMMER", "lines": ["Damage: 35", "Attack speed: 0.5/s", "Slow but heavy"]},
	"boots": {"name": "BOOTS", "lines": ["+20% move speed"]},
	"armor": {"name": "ARMOR", "lines": ["+50% max health"]},
}
const ITEM_ICONS := {
	"sword": "res://assets/ui/items/sword.png",
	"hammer": "res://assets/ui/items/hammer.png",
	"boots": "res://assets/ui/items/boots.png",
	"armor": "res://assets/ui/items/armor.png",
}
const COIN_ICON := "res://assets/ui/items/coin.png"
const GOLD_BARS_ICON := "res://assets/ui/items/gold_bars.png"

const UNIT_ORDER := ["peasant", "zombie", "ghost", "ninja", "pirate",
		"shaman", "priest", "viking", "executioner", "achilles"]
const COMMANDS := ["attack", "hold", "defend"]

var _root: Control

var _gold_label: Label
var _income_label: Label
var _own_castle_label: Label
var _own_castle_bar: ProgressBar

var _banner_label: Label
var _banner_bar: ProgressBar

var _enemy_castle_label: Label
var _enemy_castle_bar: ProgressBar
var _enemy_income_label: Label

var _knight_values: Dictionary = {}  # stat key -> value Label
var _slot_icons: Array = []  # 4 item TextureRects

var _command_buttons: Dictionary = {}  # command -> Button
var _cmd_style_normal: StyleBoxFlat
var _cmd_style_active: StyleBoxFlat

var _shop_popup: Control
var _item_price_labels: Dictionary = {}  # item id -> Label
var _item_buy_buttons: Dictionary = {}  # item id -> Button

var _castle_popup: Control
var _mine_button: Button
var _mine_count_label: Label
var _unit_buttons: Dictionary = {}  # unit type -> Button


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_left_column()
	_build_top_center()
	_build_top_right()
	_build_inventory()
	_build_commands()
	_build_minimap()
	_shop_popup = _build_shop_popup()
	_castle_popup = _build_castle_popup()

	Network.state_updated.connect(_refresh)
	_refresh()


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

func _panel_style(bg: Color = PANEL_BG, margin: float = 10.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(2)
	style.border_color = PANEL_BORDER
	style.set_corner_radius_all(6)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.7
	style.content_margin_bottom = margin * 0.7
	return style


func _make_panel(margin: float = 10.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL_BG, margin))
	return panel


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_bar(fill_color: Color, min_size: Vector2 = Vector2(160, 12)) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = min_size
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.06, 0.05)
	bg.set_border_width_all(1)
	bg.border_color = Color(0, 0, 0, 0.85)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _style_button(button: Button, active: bool = false) -> void:
	var normal := _panel_style(PANEL_BG_LIGHT if not active else Color("3a2f1c"), 6.0)
	var hover := _panel_style(Color("342b1e"), 6.0)
	hover.border_color = GOLD_TEXT
	var pressed := _panel_style(Color("141109"), 6.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", _panel_style(Color("15120d"), 6.0))
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", GOLD_TEXT)
	button.add_theme_color_override("font_disabled_color", DIM_TEXT)


func _make_icon(path: String, side: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(side, side)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = load(path)
	return icon


## Safe field read from synced state (works on both the plain Dictionaries
## returned by get_state() and Schema wrapper objects). Dot access on a
## Dictionary hard-fails (aborting the caller) when the key is missing,
## e.g. on a partial patch or a client/server schema mismatch.
static func _field(data: Variant, key: String) -> Variant:
	return data.get(key) if data != null else null


static func _num(data: Variant, key: String, default: float = 0.0) -> float:
	var value: Variant = _field(data, key)
	return float(value) if value != null else default


func _stat_row(parent: Control, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := _make_label(title + ":", 11, DIM_TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value := _make_label("-", 11, GREEN)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_knight_values[key] = value
	parent.add_child(row)


# ---------------------------------------------------------------------------
# Layout blocks
# ---------------------------------------------------------------------------

## Top-left resources panel + knight stats card stacked in one column.
func _build_left_column() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_root.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 12)

	# Resources panel.
	var panel := _make_panel()
	panel.custom_minimum_size = Vector2(200, 0)
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 8)
	box.add_child(gold_row)
	gold_row.add_child(_make_icon(COIN_ICON, 28.0))
	_gold_label = _make_label("0", 26, GOLD_TEXT)
	_gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(_gold_label)
	_income_label = _make_label("INCOME: 0/5s", 11, GREEN)
	box.add_child(_income_label)
	_own_castle_label = _make_label("CASTLE: -", 11, TEXT_COLOR)
	box.add_child(_own_castle_label)
	_own_castle_bar = _make_bar(GREEN, Vector2(176, 12))
	box.add_child(_own_castle_bar)

	# Knight stats card.
	var card := _make_panel()
	card.custom_minimum_size = Vector2(200, 0)
	column.add_child(card)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 4)
	card.add_child(card_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	card_box.add_child(header)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(48, 48)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = load(EntityView.KNIGHT_TEXTURES.get(
			Network.my_team(), EntityView.KNIGHT_TEXTURES["blue"]))
	header.add_child(portrait)

	var title := _make_label("KNIGHT", 15, TEXT_COLOR)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)

	_stat_row(card_box, "HEALTH", "health")
	_stat_row(card_box, "DAMAGE", "damage")
	_stat_row(card_box, "ATTACK SPEED", "attack_speed")
	_stat_row(card_box, "MOVE SPEED", "move_speed")
	_stat_row(card_box, "ARMOR", "armor")
	_stat_row(card_box, "REGEN", "regen")


func _build_top_center() -> void:
	var panel := _make_panel(14.0)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	_banner_label = _make_label("CASTLE", 15, TEXT_COLOR)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner_label)
	_banner_bar = _make_bar(GREEN, Vector2(190, 14))
	box.add_child(_banner_bar)

	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)


func _build_top_right() -> void:
	var panel := _make_panel()
	panel.custom_minimum_size = Vector2(200, 0)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	box.add_child(_make_label("ENEMY", 17, RED_TEXT))
	_enemy_castle_label = _make_label("CASTLE: -", 11, TEXT_COLOR)
	box.add_child(_enemy_castle_label)
	_enemy_castle_bar = _make_bar(RED, Vector2(176, 12))
	box.add_child(_enemy_castle_bar)
	_enemy_income_label = _make_label("INCOME: 0/5s", 11, GOLD_TEXT)
	box.add_child(_enemy_income_label)

	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)


func _build_inventory() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_root.add_child(row)

	for i in range(4):
		var slot := _make_panel(6.0)
		slot.custom_minimum_size = Vector2(62, 62)
		row.add_child(slot)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		slot.add_child(box)
		var number := _make_label(str(i + 1), 10, DIM_TEXT)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(number)
		var item := TextureRect.new()
		item.custom_minimum_size = Vector2(36, 36)
		item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		item.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(item)
		_slot_icons.append(item)

	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)


func _build_commands() -> void:
	_cmd_style_normal = _panel_style(PANEL_BG_LIGHT, 6.0)
	_cmd_style_active = _panel_style(Color("3d331c"), 6.0)
	_cmd_style_active.border_color = GOLD_TEXT

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_root.add_child(row)

	for command in COMMANDS:
		var button := Button.new()
		button.text = command.to_upper()
		button.custom_minimum_size = Vector2(66, 56)
		button.add_theme_font_size_override("font_size", 11)
		_style_button(button)
		button.pressed.connect(Network.send_set_command.bind(command))
		row.add_child(button)
		_command_buttons[command] = button

	var shop := Button.new()
	shop.text = "SHOP"
	shop.custom_minimum_size = Vector2(86, 64)
	shop.add_theme_font_size_override("font_size", 15)
	_style_button(shop)
	shop.add_theme_color_override("font_color", GOLD_TEXT)
	shop.pressed.connect(_on_shop_pressed)
	row.add_child(shop)

	var castle := Button.new()
	castle.text = "CASTLE"
	castle.custom_minimum_size = Vector2(86, 64)
	castle.add_theme_font_size_override("font_size", 15)
	_style_button(castle)
	castle.add_theme_color_override("font_color", GOLD_TEXT)
	castle.pressed.connect(_on_castle_pressed)
	row.add_child(castle)

	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)


func _build_minimap() -> void:
	const MINIMAP_SIZE := Vector2(132, 196)
	const MARGIN := 12.0
	var minimap := Minimap.new()
	minimap.custom_minimum_size = MINIMAP_SIZE
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(minimap)
	# Anchor every edge to the viewport's bottom-left corner and size the rect
	# upward from there, so the whole minimap always sits on screen.
	minimap.anchor_left = 0.0
	minimap.anchor_right = 0.0
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = MARGIN
	minimap.offset_right = MARGIN + MINIMAP_SIZE.x
	minimap.offset_top = -MARGIN - MINIMAP_SIZE.y
	minimap.offset_bottom = -MARGIN
	minimap.grow_horizontal = Control.GROW_DIRECTION_END
	minimap.grow_vertical = Control.GROW_DIRECTION_BEGIN


# ---------------------------------------------------------------------------
# Popups
# ---------------------------------------------------------------------------

func _make_popup_shell(title_text: String) -> Array:
	## Returns [overlay Control, content VBoxContainer].
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := _make_panel(16.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := _make_label(title_text, 20, GOLD_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	return [overlay, box]


func _add_close_button(box: VBoxContainer, overlay: Control) -> void:
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 36)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(close)
	close.pressed.connect(func() -> void: overlay.visible = false)
	box.add_child(close)


func _build_shop_popup() -> Control:
	var shell := _make_popup_shell("SHOP")
	var overlay: Control = shell[0]
	var box: VBoxContainer = shell[1]

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	box.add_child(cards)

	for item_id in ITEM_ORDER:
		var info: Dictionary = ITEM_INFO[item_id]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _panel_style(PANEL_BG_LIGHT, 8.0))
		card.custom_minimum_size = Vector2(150, 0)
		cards.add_child(card)

		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 4)
		card.add_child(card_box)

		var icon := _make_icon(ITEM_ICONS[item_id], 48.0)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card_box.add_child(icon)

		var name_label := _make_label(str(info["name"]), 14, GOLD_TEXT)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_box.add_child(name_label)

		for line in info["lines"]:
			var stat := _make_label(str(line), 11, TEXT_COLOR)
			stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card_box.add_child(stat)

		var price := _make_label("- g", 13, GOLD_TEXT)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_box.add_child(price)
		_item_price_labels[item_id] = price

		var buy := Button.new()
		buy.text = "Buy"
		buy.custom_minimum_size = Vector2(0, 32)
		_style_button(buy)
		buy.pressed.connect(Network.send_buy_item.bind(item_id))
		card_box.add_child(buy)
		_item_buy_buttons[item_id] = buy

	_add_close_button(box, overlay)
	return overlay


func _build_castle_popup() -> Control:
	var shell := _make_popup_shell("CASTLE")
	var overlay: Control = shell[0]
	var box: VBoxContainer = shell[1]

	var mine_row := HBoxContainer.new()
	mine_row.add_theme_constant_override("separation", 12)
	mine_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(mine_row)

	_mine_button = Button.new()
	_mine_button.text = "Build Gold Mine"
	_mine_button.custom_minimum_size = Vector2(220, 40)
	_style_button(_mine_button)
	_mine_button.add_theme_color_override("font_color", GOLD_TEXT)
	_mine_button.icon = load(GOLD_BARS_ICON)
	_mine_button.add_theme_constant_override("icon_max_width", 26)
	_mine_button.expand_icon = false
	_mine_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mine_button.pressed.connect(Network.send_build_mine)
	mine_row.add_child(_mine_button)

	_mine_count_label = _make_label("Mines: 0", 13, TEXT_COLOR)
	_mine_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mine_row.add_child(_mine_count_label)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	for unit_type in UNIT_ORDER:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _panel_style(PANEL_BG_LIGHT, 6.0))
		card.custom_minimum_size = Vector2(96, 0)
		grid.add_child(card)

		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 3)
		card.add_child(card_box)

		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(44, 44)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = load(EntityView.UNIT_TEXTURES[unit_type])
		card_box.add_child(portrait)

		var name_label := _make_label(unit_type.capitalize(), 11, TEXT_COLOR)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_box.add_child(name_label)

		var button := Button.new()
		button.text = "- g"
		button.custom_minimum_size = Vector2(0, 28)
		button.add_theme_font_size_override("font_size", 11)
		_style_button(button)
		button.add_theme_color_override("font_color", GOLD_TEXT)
		button.pressed.connect(Network.send_spawn_unit.bind(unit_type))
		card_box.add_child(button)
		_unit_buttons[unit_type] = button

	_add_close_button(box, overlay)
	return overlay


func _on_shop_pressed() -> void:
	_castle_popup.visible = false
	_shop_popup.visible = not _shop_popup.visible


func _on_castle_pressed() -> void:
	_shop_popup.visible = false
	_castle_popup.visible = not _castle_popup.visible


# ---------------------------------------------------------------------------
# State refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var state: Variant = Network.get_state()
	if state == null:
		return
	# The native SDK decodes schema objects/maps into plain Dictionaries.
	var teams: Variant = state.get("teams")
	var castles: Variant = state.get("castles")
	var knights: Variant = state.get("knights")
	if teams == null or castles == null or knights == null:
		return

	var me := Network.my_team()
	var foe := Network.enemy_team()
	var team: Variant = teams.get(me)
	var enemy: Variant = teams.get(foe)
	var my_castle: Variant = castles.get(me)
	var enemy_castle: Variant = castles.get(foe)
	var knight: Variant = knights.get(me)
	var config: Variant = state.get("config")
	var phase := str(state.get("phase"))

	var gold := 0
	if team != null:
		gold = int(_num(team, "gold"))
		_gold_label.text = str(gold)
		_income_label.text = "INCOME: %d/5s" % int(round(_num(team, "income") * 5.0))

	# Top-center banner: the PLAYER'S castle name + HP bar.
	if my_castle != null:
		var my_ratio := clampf(_num(my_castle, "hp") / maxf(_num(my_castle, "maxHp"), 1.0), 0.0, 1.0)
		_own_castle_label.text = "CASTLE: %d/%d" % [int(_num(my_castle, "hp")), int(_num(my_castle, "maxHp"))]
		_own_castle_bar.value = my_ratio
		_banner_bar.value = my_ratio

	if phase == "waiting":
		_banner_label.text = "WAITING FOR OPPONENT"
	else:
		_banner_label.text = "CASTLE"
	if enemy_castle != null:
		var enemy_ratio := clampf(_num(enemy_castle, "hp") / maxf(_num(enemy_castle, "maxHp"), 1.0), 0.0, 1.0)
		_enemy_castle_bar.value = enemy_ratio
		_enemy_castle_label.text = "CASTLE: %d/%d" % [int(_num(enemy_castle, "hp")), int(_num(enemy_castle, "maxHp"))]
	if enemy != null:
		_enemy_income_label.text = "INCOME: %d/5s" % int(round(_num(enemy, "income") * 5.0))

	var owned_items := 0
	if knight != null:
		var alive: Variant = _field(knight, "alive")
		if (bool(alive) if alive != null else true):
			_knight_values["health"].text = "%d/%d" % [int(_num(knight, "hp")), int(_num(knight, "maxHp"))]
		else:
			_knight_values["health"].text = "DEAD (%ds)" % int(ceil(_num(knight, "respawnIn")))
		_knight_values["damage"].text = str(int(_num(knight, "damage")))
		_knight_values["attack_speed"].text = "%.1f" % _num(knight, "attackSpeed")
		_knight_values["move_speed"].text = str(int(_num(knight, "moveSpeed")))
		_knight_values["armor"].text = str(int(_num(knight, "armor")))
		_knight_values["regen"].text = "%.1f/s" % _num(knight, "regen")

		var items: Variant = _field(knight, "items")
		if items != null:
			owned_items = items.size()
		for i in range(_slot_icons.size()):
			if items != null and i < items.size():
				_slot_icons[i].texture = load(ITEM_ICONS.get(str(items[i]), ITEM_ICONS["sword"]))
			else:
				_slot_icons[i].texture = null

	# Command buttons: highlight the active command from synced state.
	var command_value: Variant = _field(team, "command")
	var active_command := str(command_value) if command_value != null else ""
	for command in _command_buttons:
		var button: Button = _command_buttons[command]
		button.add_theme_stylebox_override("normal",
				_cmd_style_active if command == active_command else _cmd_style_normal)

	# Shop popup values.
	var item_prices: Variant = config.get("itemPrices") if config != null else null
	var unit_costs: Variant = config.get("unitCosts") if config != null else null
	var max_items := 4
	if config != null:
		max_items = int(config.get("maxItems", 4))
	for item_id in ITEM_ORDER:
		var price := 0
		if item_prices != null and item_prices.has(item_id):
			price = int(item_prices.get(item_id))
		_item_price_labels[item_id].text = "%d g" % price
		_item_buy_buttons[item_id].disabled = gold < price or owned_items >= max_items

	# Castle popup values.
	if team != null:
		var mine_cost := int(_num(team, "nextMineCost"))
		_mine_button.text = "Build Gold Mine — %dg" % mine_cost
		_mine_button.disabled = gold < mine_cost
		_mine_count_label.text = "Mines: %d" % int(_num(team, "mines"))
	for unit_type in UNIT_ORDER:
		var cost := 0
		if unit_costs != null and unit_costs.has(unit_type):
			cost = int(unit_costs.get(unit_type))
		var button: Button = _unit_buttons[unit_type]
		button.text = "%d g" % cost
		button.disabled = gold < cost


# ---------------------------------------------------------------------------
# Minimap
# ---------------------------------------------------------------------------

class Minimap extends Control:
	const MAP_HALF := Vector2(760.0, 1980.0)
	const LANE_HALF_WIDTH := 180.0
	const CASTLE_POINTS := {
		"blue": Vector2(5, -1863),
		"red": Vector2(8, 1832),
	}

	func _process(_delta: float) -> void:
		queue_redraw()

	func _map_to_local(point: Vector2) -> Vector2:
		return Vector2(
			(point.x / MAP_HALF.x * 0.5 + 0.5) * size.x,
			(point.y / MAP_HALF.y * 0.5 + 0.5) * size.y)

	func _draw() -> void:
		# Grass background + lane strip down the middle.
		draw_rect(Rect2(Vector2.ZERO, size), Color("1c2414"))
		var lane_left := (-LANE_HALF_WIDTH / MAP_HALF.x * 0.5 + 0.5) * size.x
		var lane_right := (LANE_HALF_WIDTH / MAP_HALF.x * 0.5 + 0.5) * size.x
		draw_rect(Rect2(Vector2(lane_left, 0), Vector2(lane_right - lane_left, size.y)),
				Color("6b5a3a"))

		# Castle markers.
		draw_rect(Rect2(_map_to_local(CASTLE_POINTS["blue"]) - Vector2(5, 5), Vector2(10, 10)),
				Color("3f6fb5"))
		draw_rect(Rect2(_map_to_local(CASTLE_POINTS["red"]) - Vector2(5, 5), Vector2(10, 10)),
				Color("b53f3f"))

		# Entity dots from synced state (plain Dictionaries from the SDK).
		var state: Variant = Network.get_state()
		var units: Variant = state.get("units") if state != null else null
		var knights: Variant = state.get("knights") if state != null else null
		if units != null and knights != null:
			for id in units.keys():
				var unit: Variant = units.get(id)
				if unit == null:
					continue
				var color := Color("6fa8ff") if str(unit.get("team", "")) == "blue" else Color("ff7a6f")
				draw_circle(_map_to_local(Vector2(
						float(unit.get("x", 0.0)), float(unit.get("y", 0.0)))), 2.0, color)
			for team in ["blue", "red"]:
				var knight: Variant = knights.get(team)
				if knight == null or not bool(knight.get("alive", true)):
					continue
				var color := Color("9fc4ff") if team == "blue" else Color("ffb3a8")
				draw_circle(_map_to_local(Vector2(
						float(knight.get("x", 0.0)), float(knight.get("y", 0.0)))), 3.5, color)

		# Border on top.
		draw_rect(Rect2(Vector2.ZERO, size), Color("8a7340"), false, 2.0)
