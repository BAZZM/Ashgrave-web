class_name WorldHud
extends Control

const GOLD := Color(1.0, 0.84, 0.55)
const SLOT_NAMES := {"weapon": "WEAPONS", "helm": "HELMS", "armour": "ARMOUR", "shield": "SHIELDS", "ring": "RINGS", "ranged": "RANGED", "spell": "SPELLS", "supplies": "SUPPLIES"}

var world: Node3D
var screen := ""
var craft_skill := "smithing"
var page := 0
var tab := "weapon"

var _font: Font
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _look_touch := -1
var _caption := ""
var _caption_age := 0.0
var _clock := 0.0
var _vignette: GradientTexture2D
var _note := ""
var _note_age := 9.0
var _pops: Array = []
var _talk := {}
## Cached layout (rebuilt when the state it comes from changes, never per frame).
var _talk_rows: Array = []
var _talk_rows_i := -1
var _jr: Array = []
var _jr_pages: Array = []
var _jr_page := 0
var _jr_rev := -1
var _jr_size := Vector2.ZERO
var _trk: Array = []
var _trk_rev := -1
var _mk := {}
var _mk_rev := -1
var _talk_size := Vector2.ZERO
var sell_mode := false
var _banner := ""
var _banner_age := 9.0
## Tower only: seconds until the Unstuck entry may be used again (the land keeps its own in the mover).
var _unstuck_wait := 0.0
const UNSTUCK_WAIT := 10.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://fonts/cinzel-700.woff2"):
		_font = load("res://fonts/cinzel-700.woff2")
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.6))
	g.set_offset(0, 0.5)
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.0, 1.0)
	_vignette.width = 128
	_vignette.height = 128


func open_craft(skill: String) -> void:
	open("craft")
	craft_skill = skill


func talk(d: Dictionary) -> void:
	if d.lines.is_empty() or world.duel != null:
		return
	_talk = d
	_talk.i = 0
	_talk_rows_i = -1
	open("talk")


func announce(text: String) -> void:
	_banner = text
	_banner_age = 0.0


func open(which: String) -> void:
	screen = which
	page = 0
	_jr_page = 0
	tab = "weapon"
	world.stick = Vector2.ZERO
	_stick_touch = -1


func _buttons() -> Dictionary:
	var s := size
	return {
		"act": Rect2(s.x - 230, s.y - 220, 170, 170),
		"dash": Rect2(s.x - 380, s.y - 180, 130, 130),
		"bag": Rect2(s.x - 150, 26, 100, 60),
		"map": Rect2(s.x - 262, 26, 100, 60),
		"skills": Rect2(s.x - 394, 26, 120, 60),
		"quests": Rect2(s.x - 536, 26, 130, 60),
		"online": Rect2(s.x - 716, 26, 168, 60),
	}


## The Unstuck entry: top right of the map screen, so it is two taps (MAP, then UNSTUCK) and never
## on the main HUD.
func _unstuck_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 190, p.position.y + 4, 170, 84)


## The Quality entry: left of Unstuck on the map screen (two taps: MAP, then QUALITY). One tap switches
## between Full and Safe: safe applies its cheap levers at once (resolution at the next launch), Full waits for the next launch. The button names the level chosen.
func _quality_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 450, p.position.y + 4, 230, 84)


func _toggle_quality() -> void:
	var next := "full" if Run.quality_choice() == "safe" else "safe"
	Run.set_quality(next)
	Run.quality_apply(get_viewport())
	# In the tower there is no terrain to follow the change: free the ground and water textures here (chunks keep their own references).
	if not Run.quality_allows("textures"):
		preload("res://scripts/tex_kit.gd").clear()
	# Safe applies its cheap levers at once and the lower resolution at the next launch; Full waits for the next launch.
	_say("Safe quality on. Lower resolution from next launch." if next == "safe" else "Full quality from next launch.")


func _do_unstuck() -> void:
	var msg := ""
	if world.is_land:
		var r: Dictionary = world.mover.manual_unstuck()
		msg = String(r.msg)
	elif world.has_method("unstuck"):
		if _unstuck_wait > 0.0:
			msg = "Unstuck again in %d seconds." % ceili(_unstuck_wait)
		else:
			_unstuck_wait = UNSTUCK_WAIT
			Callable(world, &"unstuck").call()
			msg = "You free yourself."
	_close()
	if msg != "":
		Run.captions.append(msg)


func _panel() -> Rect2:
	if screen in ["map", "skills", "craft", "store", "quests", "perks", "players"]:
		return Rect2(50, 30, size.x - 100, size.y - 60)

	return Rect2(size.x * 0.36, 24, size.x * 0.64 - 40, size.y - 48)


func _tabs() -> Array:
	var out: Array = Items.SLOTS.duplicate()
	if screen == "shop":
		out.append("supplies")
	return out


func _tab_rect(i: int) -> Rect2:
	var p := _panel()
	return Rect2(p.position.x + 16, p.position.y + 88 + i * 54.0, 150, 46)


func _items() -> Array:
	if tab == "supplies":
		return ["flask"]
	var out: Array = []
	for id in Items.for_slot(tab):
		if screen == "shop" or Run.data.inventory.has(id):
			out.append(id)
	return out


func _card_rect(i: int) -> Rect2:
	var p := _panel()
	var avail := p.size.x - 200.0
	var cols := 2 if avail >= 540.0 else 1
	var w := (avail - 14.0 * (cols - 1)) / cols
	return Rect2(p.position.x + 182 + (i % cols) * (w + 14.0), p.position.y + 88 + (i / cols) * 104.0, w, 96)


func _sell_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 470, p.position.y + 14, 170, 56)


func _close_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 76, p.position.y + 12, 60, 60)


func _input(event: InputEvent) -> void:
	# The duel has its own buttons, some where ours are: while it runs, or while this HUD is hidden, ignore taps.
	if not is_visible_in_tree() or world.duel != null:
		if event is InputEventScreenTouch and not event.pressed:
			if event.index == _stick_touch:
				_stick_touch = -1
				world.stick = Vector2.ZERO
			if event.index == _look_touch:
				_look_touch = -1
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			if event.index == _stick_touch:
				_stick_touch = -1
				world.stick = Vector2.ZERO
			if event.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_touch:
			world.stick = ((event.position - _stick_origin) / 80.0).limit_length(1.0)
		elif event.index == _look_touch:
			world.cam_yaw -= event.relative.x * 0.006
			world.look_cool = 2.5
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_SPACE, KEY_ENTER:
				if not world.started:
					world.begin()
				elif screen == "":
					world.interact()
			KEY_SHIFT:
				if world.is_land and screen == "" and world.started:
					world.mover.try_dash()
			KEY_I: open("bag") if screen == "" else _close()
			KEY_M: open("map") if screen == "" else _close()
			KEY_K: open("skills") if screen == "" else _close()
			KEY_J: open("quests") if screen == "" else _close()
			KEY_ESCAPE: _close()


func _close() -> void:
	screen = ""


func _press(index: int, pos: Vector2) -> void:
	if not world.started:
		world.begin()
		return
	if screen == "talk":
		_press_talk(pos)
		return
	if screen == "skills" and _perk_button().has_point(pos):
		open("perks")
		return
	if screen == "perks":
		_press_perks(pos)
		return
	if screen == "players":
		_press_players(pos)
		return
	if screen == "map" and _quality_rect().has_point(pos):
		_toggle_quality()
		return
	if screen == "map" and not _unstuck_rect().has_point(pos) and Rect2(_quality_rect().position, Vector2(_unstuck_rect().end.x - _quality_rect().position.x, _quality_rect().size.y)).has_point(pos):
		return  # the gap between the two buttons does nothing (a miss closes the map)
	if screen == "map" and _unstuck_rect().has_point(pos):
		_do_unstuck()
		return
	if screen == "map" and world.is_land and _press_map(pos):
		return
	if screen == "quests":
		_press_quests(pos)
		return
	if screen in ["map", "skills"]:
		_close()
		return
	if screen in ["craft", "store"]:
		_press_list(pos)
		return
	if screen != "":
		_press_screen(pos)
		return
	if world.is_land and _buttons().dash.has_point(pos):
		world.mover.try_dash()
		return
	if _caption != "" and pos.y > size.y * 0.72 and absf(pos.x - size.x * 0.5) < size.x * 0.3:
		_caption_age = 99.0
		return
	var b := _buttons()
	if b.skills.has_point(pos):
		open("skills")
	elif world.is_land and b.quests.has_point(pos):
		open("quests")
	elif world.is_land and b.online.has_point(pos):
		open("players")
	elif b.bag.has_point(pos):
		open("bag")
	elif b.map.has_point(pos):
		open("map")
	elif world.prompt() != "" and b.act.has_point(pos):
		world.interact()
	elif pos.x < size.x * 0.45 and _stick_touch == -1:
		_stick_touch = index
		_stick_origin = pos
	elif _look_touch == -1:
		_look_touch = index


func _talk_panel() -> Rect2:
	return Rect2(110, size.y - 346, size.x - 220, 320)


func _choice_rect(i: int) -> Rect2:
	var p := _talk_panel()
	return Rect2(p.end.x - 470, p.position.y + 62 + i * 84.0, 450, 76)


func _press_talk(pos: Vector2) -> void:
	var last: bool = int(_talk.i) >= (_talk.lines as Array).size() - 1
	if not last:
		_talk.i = int(_talk.i) + 1
		return
	var choices: Array = _talk.choices
	if choices.is_empty():
		_close()
		return
	for i in choices.size():
		if _choice_rect(i).has_point(pos):
			var action: String = choices[i][1]
			if action.begins_with("pvp:"):
				_close()
				world.pvp_answer(action)
			elif action == "shop":
				open("shop")
			elif action == "bye":
				_close()
			else:
				var more := Quests.act(action)
				if more.is_empty():
					_close()
				else:
					_talk = {"name": _talk.name, "lines": more, "choices": [], "i": 0}
					_talk_rows_i = -1
				world.refresh_hero()
			return


func _rename_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 430, p.position.y + 16, 180, 56)


func _toggle_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 236, p.position.y + 16, 150, 56)


func _press_players(pos: Vector2) -> void:
	if _toggle_rect().has_point(pos):
		Online.set_enabled(not Online.enabled)
	elif _rename_rect().has_point(pos):
		if OS.has_feature("web"):
			var typed: Variant = JavaScriptBridge.eval("prompt('Your name in the world (up to 16 letters):', %s) || ''" % JSON.stringify(Online.my_name), true)
			if typed is String:
				Online.rename(typed)
		else:
			Online.rename("Wanderer-%d" % (randi() % 900 + 100))
	else:
		_close()


func _perk_button() -> Rect2:
	var p := _panel()
	return Rect2(p.position.x + 190, p.position.y + 18, 230, 56)


func _perk_rect(i: int) -> Rect2:
	var p := _panel()
	var w := (p.size.x - 60.0) / 3.0 - 12.0
	return Rect2(p.position.x + 24 + (i / 3) * (w + 18.0), p.position.y + 150 + (i % 3) * 150.0, w, 132)


func _press_perks(pos: Vector2) -> void:
	var ids: Array = Craft.PERKS.keys()
	for i in ids.size():
		if _perk_rect(i).has_point(pos):
			_say(Run.buy_perk(ids[i]))
			return
	_close()


func _list_rows() -> Array:
	if screen == "craft":
		return Craft.recipes_for(craft_skill)
	var out: Array = []
	for m in Craft.MATS:
		if Run.mat(m) > 0:
			out.append(m)
	return out


func _row_rect(i: int) -> Rect2:
	var p := _panel()
	var w := (p.size.x - 60.0) / 3.0 - 10.0
	return Rect2(p.position.x + 24 + (i % 3) * (w + 15.0), p.position.y + 96 + (i / 3) * 100.0, w, 90)


func _page_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 250, p.position.y + 14, 150, 60)


func _press_list(pos: Vector2) -> void:
	if _close_rect().has_point(pos):
		_close()
		return
	var rows := _list_rows()
	if rows.size() > 15 and _page_rect().has_point(pos):
		page = (page + 1) % int(ceil(rows.size() / 15.0))
		return
	for i in mini(15, rows.size() - page * 15):
		if not _row_rect(i).has_point(pos):
			continue
		var row: Variant = rows[page * 15 + i]
		if screen == "craft":
			var why := Craft.blocker(row)
			if why != "":
				_say(why + ".")
			elif Craft.make(row):
				_say("Made: %s." % row.name)
				if row.out.has("item"):
					Run.equip(row.out.item)
					world.refresh_hero()
		else:
			var n := mini(Run.mat(row), 5)
			var gold := n * int(Craft.MATS[row].price)
			Run.add_mat(row, -n)
			Run.data.gold += gold
			Run.save()
			_say("Sold %d for %d gold." % [n, gold])
		return


func _press_screen(pos: Vector2) -> void:
	if _close_rect().has_point(pos):
		_close()
		return
	if screen == "shop" and _sell_rect().has_point(pos):
		sell_mode = not sell_mode
		_say("Tap gear you own to sell it." if sell_mode else "Buying and equipping.")
		return
	var tabs := _tabs()
	for i in tabs.size():
		if _tab_rect(i).has_point(pos):
			tab = tabs[i]
			return
	var items := _items()
	for i in items.size():
		if _card_rect(i).has_point(pos):
			_use(items[i])
			return


func _use(id: String) -> void:
	if id == "flask":
		if int(Run.data.potions) >= Items.MAX_FLASKS:
			_say("You can carry no more flasks.")
		elif int(Run.data.gold) < Items.FLASK_PRICE:
			_say("Not enough gold.")
		else:
			Run.data.gold -= Items.FLASK_PRICE
			Run.data.potions += 1
			Run.save()
		return
	if not Run.data.inventory.has(id):
		var price := int(Items.info(id).price)
		if int(Run.data.gold) < price:
			_say("Not enough gold.")
			return
		Run.data.gold -= price
		Run.add_item(id)
		Run.equip(id)
		_say("Bought and equipped.")
		world.refresh_hero()
		return
	if Run.data.equipped.get(tab, "") != id:
		if sell_mode and screen == "shop":
			if Items.STARTING.values().has(id):
				_say("Nobody wants that old thing.")
				return
			var price := int(int(Items.info(id).price) * 0.4)
			Run.data.inventory.erase(id)
			Run.data.gold += price
			Run.save()
			_say("Sold for %d gold." % price)
			return
		Run.equip(id)
		_say("Equipped.")
		world.refresh_hero()
		return

	if tab == "weapon" and screen == "shop":
		var lvl := Run.upgrade_level(id)
		if lvl >= Items.UPGRADE_MAX:
			_say("This blade can be honed no further.")
			return
		var cost := Items.upgrade_price(id, lvl)
		if int(Run.data.gold) < cost:
			_say("Not enough gold to hone it.")
			return
		Run.data.gold -= cost
		Run.data.upgrades[id] = lvl + 1
		Run.save()
		_say("Honed. The runes burn brighter.")
		world.refresh_hero()
	elif Items.STARTING[tab] == "":
		Run.data.equipped[tab] = ""
		Run.save()
		_say("Removed.")
		world.refresh_hero()


func _compare(id: String) -> Array:
	var out: Array = []
	if Items.slot_of(id) in ["ranged", "spell"]:
		return out
	var now := Run.stats()
	var then := Run.stats_with(id)
	for row in [["damage", "DMG", 1.0], ["max_hp", "HEALTH", 1.0], ["shield_max", "SHIELD", 1.0], ["dodge_max", "DODGE", 1.0],
			["slash_lock", "SPEED", -100.0], ["parry_window", "PARRY", 100.0], ["perfect_block", "BLOCK", 100.0]]:
		var diff: float = (float(then[row[0]]) - float(now[row[0]])) * float(row[2])
		if absf(diff) >= 0.5:
			out.append(["%s%d %s" % ["+" if diff > 0.0 else "", int(round(diff)), row[1]], diff > 0.0])
	return out


func _say(text: String) -> void:
	_note = text
	_note_age = 0.0


func _process(delta: float) -> void:
	_clock += delta
	_unstuck_wait = maxf(_unstuck_wait - delta, 0.0)
	_note_age += delta
	_banner_age += delta
	while not Run.xp_log.is_empty():
		_pops.append({"text": Run.xp_log.pop_front(), "age": -0.25 * _pops.size()})
	for p in _pops:
		p.age += delta
	_pops = _pops.filter(func(p): return p.age < 1.6)
	if _caption == "" and not Run.captions.is_empty() and world.started and screen == "":
		_caption = Run.captions.pop_front()
		_caption_age = 0.0
	if _caption != "":
		_caption_age += delta
		if _caption_age > 3.0 + _caption.length() * 0.05:
			_caption = ""
	queue_redraw()


func _text(text: String, pos: Vector2, font_size: int, color: Color, centered := true, max_w := -1.0) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

	var zoom := 1.0
	if max_w > 0.0 and w > max_w:
		zoom = max_w / w
	var p := Vector2(-w * 0.5, 0) if centered else Vector2.ZERO
	draw_set_transform(pos, 0.0, Vector2(zoom, zoom))
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, color.a * 0.8))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO)


func _wrapped(text: String, center: Vector2, font_size: int, color: Color, width: float) -> void:
	var lines: Array = []
	var cur := ""
	for word in text.split(" "):
		var trial := word if cur == "" else cur + " " + word
		if _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = trial
	lines.append(cur)
	var lh := font_size * 1.35
	var top := center.y - (lines.size() - 1) * lh * 0.5
	draw_rect(Rect2(center.x - width * 0.5 - 24, top - lh, width + 48, lines.size() * lh + lh * 0.7), Color(0, 0, 0, 0.62 * color.a))
	for i in lines.size():
		_text(lines[i], Vector2(center.x, top + i * lh), font_size, color)


func _box(r: Rect2, lit := false) -> void:
	draw_rect(r, Color(0.16, 0.13, 0.09, 0.96) if lit else Color(0.09, 0.08, 0.08, 0.94))
	draw_rect(r, Color(GOLD.r, GOLD.g, GOLD.b, 0.95 if lit else 0.45), false, 2.0)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _draw() -> void:
	var s := size
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, s), false)
	if not world.started:
		_draw_title(s)
		return
	match screen:
		"": _draw_explore(s)
		"map": _draw_map(s)
		"skills": _draw_skills(s)
		"quests": _draw_quests(s)
		"perks": _draw_perks(s)
		"players": _draw_players(s)
		"talk": _draw_talk(s)
		"craft", "store": _draw_list(s)
		_: _draw_gear(s)


func _draw_title(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.3))
	_text("ASHGRAVE", Vector2(s.x * 0.5, s.y * 0.36), 120, GOLD)
	draw_line(Vector2(s.x * 0.5 - 260, s.y * 0.4), Vector2(s.x * 0.5 + 260, s.y * 0.4), Color(GOLD.r, GOLD.g, GOLD.b, 0.6), 2.0)
	_diamond(Vector2(s.x * 0.5, s.y * 0.4), 8.0, GOLD)
	var d: Dictionary = Run.data
	var line := "Bloodline %d     Combat %d     Total level %d" % [d.bloodline, Run.combat_level(), Run.total_level()]
	if int(d.loop) > 0:
		line += "     Ascension %d" % d.loop
	_text(line, Vector2(s.x * 0.5, s.y * 0.48), 24, Color(1, 1, 1, 0.8))
	_text("TAP TO BEGIN", Vector2(s.x * 0.5, s.y * 0.74), 36, Color(1, 1, 1, 0.55 + 0.45 * sin(_clock * 3.0)))
	_text("Build %d" % Run.BUILD, Vector2(s.x - 110, s.y - 30), 18, Color(1, 1, 1, 0.6))


func _draw_explore(s: Vector2) -> void:
	for e in world.ents:
		var wp: Vector3 = e.pos + Vector3(0, float(e.get("height", 2.0)), 0)
		var d: float = (e.pos as Vector3).distance_to(world.hero_pos)
		if d > (22.0 if world.is_land else 11.0) or world.cam.is_position_behind(wp):
			continue
		var col := Color(1, 1, 1, 0.8)
		if e.type == "player":
			col = Color(0.55, 0.9, 1.0)
		if e.type == "foe":
			col = {"guardian": Color(1.0, 0.35, 0.25), "elite": Color(1.0, 0.65, 0.25), "lesser": Color(0.95, 0.9, 0.8)}.get(e.kind, Color(0.95, 0.9, 0.8))
			if e.kind == "wild":
				var gap: int = int(Land.FOES[e.wild].level) - Run.combat_level()
				col = Color(1.0, 0.35, 0.3) if gap > 8 else (Color(1.0, 0.85, 0.4) if gap > -4 else Color(0.5, 1.0, 0.55))
		col.a = clampf(((22.0 if world.is_land else 11.0) - d) / 4.0, 0.0, 1.0)
		_text(e.label, world.cam.unproject_position(wp), 20, col)
		if e.type in ["npc", "smith"] and _marked(e.id):
			_text("!", world.cam.unproject_position(wp) + Vector2(0, -26), 38, Color(1.0, 0.85, 0.3, col.a))

	_text(world.place_name(), Vector2(56, 52), 30, GOLD, false)
	var sub := "Combat %d     Total level %d" % [Run.combat_level(), Run.total_level()]
	if not world.is_land:
		sub = "Tier %d of %d     Combat %d" % [world.tier, Run.FLOORS, Run.combat_level()]
	_text(sub, Vector2(58, 80), 18, Color(1, 1, 1, 0.75), false)
	_diamond(Vector2(68, 106), 9.0, Color(1.0, 0.8, 0.3))
	_text("%d gold     %d flasks" % [Run.data.gold, Run.data.potions], Vector2(86, 113), 20, Color(1, 1, 1, 0.9), false)

	var b := _buttons()
	for key in (["bag", "map", "skills", "quests"] if world.is_land else ["bag", "map", "skills"]):
		_box(b[key])
		_text(key.to_upper(), (b[key] as Rect2).get_center() + Vector2(0, 8), 22, Color.WHITE)
	if world.is_land:
		_box(b.online, Online.connected and Online.count() > 0)
		var net := "OFFLINE"
		if Online.enabled:
			net = "ONLINE %d" % (Online.count() + 1) if Online.connected else "JOINING"
		_text(net, (b.online as Rect2).get_center() + Vector2(0, 8), 20, Color(0.6, 0.95, 1.0) if Online.connected else Color(1, 1, 1, 0.6))

	var base := _stick_origin if _stick_touch != -1 else Vector2(170, s.y - 170)
	var alpha := 0.75 if _stick_touch != -1 else 0.3
	draw_arc(base, 80.0, 0, TAU, 48, Color(1, 1, 1, alpha), 3.0, true)
	draw_circle(base + world.stick * 80.0, 34.0, Color(1, 1, 1, alpha * 0.6))

	var prompt: String = world.prompt()
	if prompt != "":
		var c: Vector2 = (b.act as Rect2).get_center()
		var sealed: bool = prompt == "SEALED"
		var tint := Color(1.0, 0.3, 0.25) if sealed else GOLD
		draw_circle(c, 85.0, Color(0, 0, 0, 0.4))
		draw_circle(c, 85.0, Color(tint.r, tint.g, tint.b, 0.2 + 0.1 * sin(_clock * 5.0)))
		draw_arc(c, 85.0, 0, TAU, 48, tint, 4.0, true)
		_text(prompt, c + Vector2(0, 10), 28, Color.WHITE)

	if world.gather_progress >= 0.0:
		var gc: Vector2 = (b.act as Rect2).get_center()
		draw_circle(gc, 85.0, Color(0, 0, 0, 0.4))
		draw_arc(gc, 85.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(world.gather_progress, 0.0, 1.0), 48, GOLD, 8.0, true)
		_text(world.gather_label, gc + Vector2(0, 10), 26, Color.WHITE)
	for i in _pops.size():
		var pp: Dictionary = _pops[i]
		if pp.age < 0.0:
			continue
		_text(pp.text, Vector2(s.x * 0.5, s.y * 0.4 - pp.age * 70.0), 26, Color(0.6, 1.0, 0.65, clampf(1.6 - pp.age, 0.0, 1.0)))
	if _banner_age < 3.0 and _banner != "":
		var ba := clampf(minf(_banner_age * 2.0, 3.0 - _banner_age), 0.0, 1.0)
		_text(_banner, Vector2(s.x * 0.5, s.y * 0.24), 60, Color(GOLD.r, GOLD.g, GOLD.b, ba))
	if _trk_rev != Quests.rev:
		_trk_rev = Quests.rev
		_trk = tracker_lines()
	var qy := 166.0 if world.is_land and not Run.data.task.is_empty() else 140.0
	for line in _trk:
		_text(line, Vector2(58, qy), 15, Color(1.0, 0.9, 0.6, 0.85), false, 520.0)
		qy += 22.0
	if world.is_land and not Run.data.task.is_empty():
		var tk: Dictionary = Run.data.task
		_text("Hunt: %s %d of %d" % [Land.FOES[tk.foe].name, tk.have, tk.need], Vector2(58, 140), 17, Color(1, 1, 1, 0.75), false)

	if _caption != "":
		var a := clampf(_caption_age * 3.0, 0.0, 1.0)
		var cap := _caption_place(s, b)
		_wrapped(_caption, cap.pos, 22, Color(1, 0.95, 0.85, a), cap.width)
	if world.is_land:
		_draw_dash(b.dash)


## Whether an NPC carries the "!" (cached; rebuilt when quest state changes).
func _marked(npc: String) -> bool:
	if _mk_rev != Quests.rev:
		_mk_rev = Quests.rev
		_mk.clear()
	if not _mk.has(npc):
		_mk[npc] = Quests.marker(npc) != ""
	return _mk[npc]


## Tracker: up to three open quests, each as "name: step" (see Quests.tracker_ids).
func tracker_lines() -> Array:
	var out: Array = []
	for qid in Quests.tracker_ids():
		out.append(Quests.track_text(qid))
	return out


## Where the caption goes: the bottom centre, but never over the DASH button (land). It takes the
## space between the stick and DASH if that is wide enough, else it sits above DASH and its pips.
func _caption_place(s: Vector2, b: Dictionary) -> Dictionary:
	var width := minf(s.x * 0.56, 760.0)
	var pos := Vector2(s.x * 0.5, s.y * 0.84)
	if not world.is_land:
		return {"pos": pos, "width": width}
	var dash: Rect2 = b.dash
	var left := 270.0
	var right := dash.position.x - 16.0
	if absf(pos.x - dash.get_center().x) - width * 0.5 - 24.0 >= dash.size.x * 0.5:
		return {"pos": pos, "width": width}
	if right - left >= 360.0:
		return {"pos": Vector2((left + right) * 0.5 + 12.0, pos.y), "width": minf(width, right - left - 48.0)}
	return {"pos": Vector2(pos.x, dash.position.y - 70.0), "width": width}


## The dash button and its pips (one diamond per pip, the next one filling as it recharges).
func _draw_dash(r: Rect2) -> void:
	var can: bool = world.mover.dash_ready()
	_box(r, world.mover.dashing())
	if not can and not world.mover.dashing():
		draw_rect(r, Color(0, 0, 0, 0.45))
	_text("DASH", r.get_center() + Vector2(0, 8), 22, Color(1, 1, 1, 1.0 if can else 0.5))
	var pips: float = world.mover.dash_pips()
	var pmax: int = int(world.mover.dash_pip_max())
	for i in pmax:
		var c := Vector2(r.get_center().x + (i - (pmax - 1) * 0.5) * 22.0, r.position.y - 16.0)
		_diamond(c, 7.0, Color(0.25, 0.22, 0.2, 0.8))
		var fill := clampf(pips - i, 0.0, 1.0)
		if fill > 0.0:
			_diamond(c, 7.0 * (0.4 + 0.6 * fill), Color(GOLD.r, GOLD.g, GOLD.b, 0.35 + 0.65 * fill))


func _draw_gear(s: Vector2) -> void:
	var p := _panel()
	_box(p)
	_text("THE SMITH" if screen == "shop" else "YOUR GEAR", p.position + Vector2(20, 56), 36, GOLD, false)
	_diamond(Vector2(p.end.x - 270, p.position.y + 44), 9.0, Color(1.0, 0.8, 0.3))
	_text("%d gold" % Run.data.gold, Vector2(p.end.x - 250, p.position.y + 52), 24, Color(1.0, 0.85, 0.4), false, 160.0)
	var cr := _close_rect()
	_box(cr)
	draw_line(cr.position + Vector2(18, 18), cr.end - Vector2(18, 18), Color.WHITE, 4.0)
	draw_line(cr.position + Vector2(42, 18), cr.position + Vector2(18, 42), Color.WHITE, 4.0)
	if screen == "shop":
		_box(_sell_rect(), sell_mode)
		_text("SELLING" if sell_mode else "SELL GEAR", _sell_rect().get_center() + Vector2(0, 7), 17, Color.WHITE)
	var tabs := _tabs()
	for i in tabs.size():
		var tr := _tab_rect(i)
		_box(tr, tabs[i] == tab)
		_text(SLOT_NAMES[tabs[i]], tr.get_center() + Vector2(0, 7), 18, Color.WHITE)
		if tabs[i] != "supplies" and Run.data.equipped.get(tabs[i], "") != "":
			_diamond(Vector2(tr.end.x - 12, tr.position.y + 12), 5.0, GOLD)
	var items := _items()
	if items.is_empty():
		_text("Nothing here yet. The Smith sells these.", Vector2(p.position.x + 182 + (p.size.x - 200) * 0.5, p.position.y + 150), 20, Color(1, 1, 1, 0.6))
	for i in items.size():
		var r := _card_rect(i)
		var id: String = items[i]
		if id == "flask":
			_box(r)
			_text("Flask", r.position + Vector2(16, 34), 22, GOLD, false)
			_text("Heals 45%% in a fight. Held %d of %d" % [Run.data.potions, Items.MAX_FLASKS], r.position + Vector2(16, 60), 15, Color(1, 1, 1, 0.8), false, r.size.x - 130)
			_text("%d G" % Items.FLASK_PRICE, Vector2(r.end.x - 60, r.position.y + 54), 20, Color(1.0, 0.85, 0.4))
			continue
		var info := Items.info(id)
		var owned: bool = Run.data.inventory.has(id)
		var equipped: bool = Run.data.equipped.get(tab, "") == id
		var lvl := Run.upgrade_level(id)
		_box(r, equipped)
		_text(info.name + (" +%d" % lvl if lvl > 0 else ""), r.position + Vector2(16, 32), 21, GOLD if owned else Color(1, 1, 1, 0.9), false, r.size.x - 150)
		_text(Items.describe(id), r.position + Vector2(16, 56), 14, Color(1, 1, 1, 0.75), false, r.size.x - 140)
		if not equipped:
			var x := r.position.x + 16
			for tok in _compare(id):
				var tw := _font.get_string_size(tok[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
				if x + tw > r.end.x - 12:
					break
				_text(tok[0], Vector2(x, r.position.y + 82), 15, Color(0.45, 1.0, 0.5) if tok[1] else Color(1.0, 0.45, 0.4), false)
				x += tw + 14.0
		if tab == "weapon" and owned and Run.mastery_level(id) > 0:
			_text("Mastery %d" % Run.mastery_level(id), Vector2(r.end.x - 64, r.position.y + 60), 13, Color(0.6, 0.9, 1.0))
		var status := "EQUIPPED" if equipped else ("EQUIP" if owned else "%d G" % info.price)
		if sell_mode and screen == "shop" and owned and not equipped:
			status = "SELL %d" % int(int(info.price) * 0.4)
		var sc := GOLD if equipped else (Color.WHITE if owned else (Color(1.0, 0.85, 0.4) if int(Run.data.gold) >= int(info.price) else Color(0.9, 0.35, 0.3)))
		_text(status, Vector2(r.end.x - 64, r.position.y + 36), 17, sc)
		if equipped and tab == "weapon" and screen == "shop" and lvl < Items.UPGRADE_MAX:
			var cost := Items.upgrade_price(id, lvl)
			_text("HONE %d G" % cost, Vector2(r.end.x - 74, r.position.y + 82), 15, Color(1.0, 0.85, 0.4) if int(Run.data.gold) >= cost else Color(0.9, 0.35, 0.3))

	var foot := ""
	var counts := Run.set_counts()
	for set_id in counts:
		foot += "%s set %d of 3: %s.   " % [Items.SETS[set_id].name, counts[set_id], Items.SETS[set_id].desc]
	if _note_age < 2.5:
		foot = _note
	if foot != "":
		_text(foot, Vector2(p.position.x + 182 + (p.size.x - 200) * 0.5, p.end.y - 20), 17, Color(1, 1, 1, 0.9), true, p.size.x - 220)

	var st := Run.stats()
	var lx := 44.0
	var ly := s.y - 190.0
	draw_rect(Rect2(lx - 14, ly - 34, 290, 196), Color(0, 0, 0, 0.5))
	_text("COMBAT %d" % Run.combat_level(), Vector2(lx, ly), 24, GOLD, false)
	var rows := [["Health", "%d" % st.max_hp], ["Cut damage", "%.1f" % st.damage], ["Cuts a second", "%.1f" % (1.0 / float(st.slash_lock))],
		["Shield", "%d" % st.shield_max], ["Dodge charges", "%d" % st.dodge_max]]
	for i in rows.size():
		_text(rows[i][0], Vector2(lx, ly + 32 + i * 26.0), 17, Color(1, 1, 1, 0.75), false)
		_text(rows[i][1], Vector2(lx + 210, ly + 32 + i * 26.0), 17, Color.WHITE, false)


func _draw_skills(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.78))
	var p := _panel()
	_box(p)
	_text("SKILLS", p.position + Vector2(28, 60), 38, GOLD, false)
	_box(_perk_button(), Run.perk_points() > 0)
	_text("PERKS (%d to spend)" % Run.perk_points(), _perk_button().get_center() + Vector2(0, 7), 18, Color.WHITE)
	_text("Combat %d     Total level %d     Tap to close" % [Run.combat_level(), Run.total_level()], Vector2(p.end.x - 300, p.position.y + 54), 20, Color(1, 1, 1, 0.75))
	var ids: Array = Craft.SKILLS.keys()
	var w := (p.size.x - 60.0) / 5.0 - 10.0
	for i in ids.size():
		var id: String = ids[i]
		var r := Rect2(p.position.x + 24 + (i % 5) * (w + 12.0), p.position.y + 96 + (i / 5) * 178.0, w, 164)
		var lvl := Run.skill(id)
		_box(r, lvl > 1)
		_text(Craft.SKILLS[id].name, Vector2(r.get_center().x, r.position.y + 34), 22, GOLD, true, r.size.x - 16)
		_text(Craft.SKILLS[id].group, Vector2(r.get_center().x, r.position.y + 56), 13, Color(1, 1, 1, 0.5))
		_text(str(lvl), Vector2(r.get_center().x, r.position.y + 112), 52, Color.WHITE)
		var lo := Craft.xp_for(lvl)
		var hi := Craft.xp_for(lvl + 1)
		var frac := clampf(float(Run.skill_xp(id) - lo) / float(hi - lo), 0.0, 1.0)
		var bar := Rect2(r.position.x + 14, r.end.y - 30, r.size.x - 28, 8)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(0.5, 0.9, 0.5))
		_text("%d XP to next" % (hi - Run.skill_xp(id)), Vector2(r.get_center().x, r.end.y - 6), 12, Color(1, 1, 1, 0.6))


func _draw_talk(s: Vector2) -> void:
	_draw_explore_world_only(s)
	var p := _talk_panel()
	_box(p)
	_text(_talk.name, p.position + Vector2(24, 40), 26, GOLD, false)
	var lines: Array = _talk.lines
	var last: bool = int(_talk.i) >= lines.size() - 1
	var choices: Array = _talk.choices if last else []
	if _talk_rows_i != int(_talk.i) or _talk_size != size:
		_talk_size = size
		_talk_rows_i = int(_talk.i)
		_talk_rows = _wrap(lines[_talk_rows_i], 22, talk_width(not choices.is_empty()))
	var y := p.position.y + 82.0
	for row in _talk_rows:
		_text(row, Vector2(p.position.x + 24, y), 22, Color(1, 0.96, 0.9), false)
		y += 30.0
	for i in choices.size():
		var cr := _choice_rect(i)
		_box(cr, true)
		_text(choices[i][0], cr.get_center() + Vector2(0, 7), 19, Color.WHITE, true, cr.size.x - 24)
	if choices.is_empty():
		_text("Tap to continue" if not last else "Tap to close", Vector2(p.end.x - 110, p.end.y - 16), 15, Color(1, 1, 1, 0.5 + 0.3 * sin(_clock * 4.0)))


## Width of the dialogue text: the whole box, or the left part when choices stand on the right.
func talk_width(with_choices: bool) -> float:
	return _talk_panel().size.x - 60.0 - (480.0 if with_choices else 0.0)


## Rows a text takes when wrapped as the HUD wraps it (the quest bot checks lines against its boxes).
func rows_for(text: String, font_size: int, width: float) -> int:
	return _wrap(text, font_size, width).size()


func text_width(text: String, font_size: int) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func choice_center(i: int) -> Vector2:
	return _choice_rect(i).get_center()


func _draw_explore_world_only(_s: Vector2) -> void:
	for e in world.ents:
		if e.type in ["npc", "smith"] and (e.pos as Vector3).distance_to(world.hero_pos) < 6.0:
			var wp: Vector3 = e.pos + Vector3(0, float(e.get("height", 2.0)), 0)
			if not world.cam.is_position_behind(wp):
				_text(e.label, world.cam.unproject_position(wp), 20, Color(1, 1, 1, 0.8))


func _wrap(text: String, font_size: int, width: float) -> Array:
	var lines: Array = []
	var cur := ""
	for word in text.split(" "):
		var trial := word if cur == "" else cur + " " + word
		if _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = trial
	lines.append(cur)
	return lines


const JR_GAP := 10.0


func _jr_close_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 170, p.position.y + 18, 146, 56)


func _jr_prev_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.position.x + 24, p.end.y - 76, 170, 56)


func _jr_next_rect() -> Rect2:
	var p := _panel()
	return Rect2(p.end.x - 194, p.end.y - 76, 170, 56)


func _press_quests(pos: Vector2) -> void:
	_jr_refresh()
	if _jr_close_rect().has_point(pos) or not _panel().has_point(pos):
		_close()
	elif _jr_prev_rect().has_point(pos):
		_jr_page = maxi(_jr_page - 1, 0)
	elif _jr_next_rect().has_point(pos):
		_jr_page = mini(_jr_page + 1, _jr_pages.size() - 1)


## The journal as a flat list of headers and cards, split into pages that fit the panel. Built when
## the quest state or the screen size changes.
func _jr_refresh() -> void:
	if _jr_rev == Quests.rev and _jr_size == size and not _jr.is_empty():
		return
	_jr_rev = Quests.rev
	_jr_size = size
	var p := _panel()
	var w := p.size.x - 48.0 - 40.0
	_jr = []
	var acts: Array = []
	for id in Quests.ids():
		var a := int(Quests.QUESTS[id].get("act", 1))
		if not acts.has(a):
			acts.append(a)
	acts.sort()
	for a in acts:
		_jr.append({"head": "ACT %d: %s" % [a, Quests.ACT_NAMES.get(a, "")], "h": 44.0})
		for rank in 3:
			for id in Quests.ids():
				var q: Dictionary = Quests.QUESTS[id]
				if int(q.get("act", 1)) != a:
					continue
				var done: bool = Quests.state(id).get("done", false)
				var open: bool = Quests.started(id) and not done
				var detail := ""
				var status := ""
				if rank == 0 and open:
					status = "In progress"
					detail = Quests.progress(id)
				elif rank == 1 and Quests.offerable(id):
					status = "Not started"
					detail = "Speak to %s." % Quests.NPCS[q.giver]
				elif rank == 2 and done:
					status = "Complete"
					detail = Quests.journal_text(id)
				else:
					continue
				_jr.append(_jr_card(q.name, status, detail, w, rank != 1, open))
	if not Run.data.lore.is_empty():
		_jr.append({"head": "FOUND", "h": 44.0})
		for lid in Run.data.lore:
			var le := Story.lore_entry(lid)
			_jr.append(_jr_card(le.name, "", le.text, w, true, false))
	_jr_pages = [[]]
	var room := p.size.y - 100.0 - 80.0
	var used := 0.0
	for i in _jr.size():
		var h: float = _jr[i].h + JR_GAP
		if used + h > room and not (_jr_pages[-1] as Array).is_empty():
			_jr_pages.append([])
			used = 0.0
		(_jr_pages[-1] as Array).append(i)
		used += h
	_jr_page = clampi(_jr_page, 0, _jr_pages.size() - 1)


func _jr_card(title: String, status: String, detail: String, w: float, lit_title: bool, lit: bool) -> Dictionary:
	var rows := _wrap(detail, 17, w)
	return {"title": title, "status": status, "rows": rows.slice(0, 3), "over": rows.size() > 3, "h": 54.0 + minf(rows.size(), 3) * 22.0, "gold": lit_title, "lit": lit}


## Journal cards whose text would not fit (the quest bot fails on any).
func journal_check() -> Array:
	_jr_refresh()
	var bad: Array = []
	for e in _jr:
		if e.get("over", false):
			bad.append(e.title)
	return bad


func journal_pages() -> int:
	_jr_refresh()
	return _jr_pages.size()


func _draw_quests(s: Vector2) -> void:
	_jr_refresh()
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.78))
	var p := _panel()
	_box(p)
	_text("QUESTS", p.position + Vector2(28, 60), 38, GOLD, false)
	_box(_jr_close_rect())
	_text("CLOSE", _jr_close_rect().get_center() + Vector2(0, 7), 19, Color.WHITE)
	var y := p.position.y + 100.0
	for i in _jr_pages[_jr_page]:
		var e: Dictionary = _jr[i]
		if e.has("head"):
			_text(e.head, Vector2(p.position.x + 28, y + 28), 21, Color(1, 1, 1, 0.55), false)
		else:
			var r := Rect2(p.position.x + 24, y, p.size.x - 48, e.h)
			_box(r, e.lit)
			_text(e.title, r.position + Vector2(18, 34), 24, GOLD if e.gold else Color(1, 1, 1, 0.6), false)
			if e.status != "":
				_text(e.status, Vector2(r.end.x - 110, r.position.y + 34), 17, Color(0.5, 1.0, 0.6) if e.status == "Complete" else Color(1, 1, 1, 0.7))
			var wy := r.position.y + 62.0
			for row in e.rows:
				_text(row, Vector2(r.position.x + 18, wy), 17, Color(1, 1, 1, 0.85), false)
				wy += 22.0
		y += e.h + JR_GAP
	if _jr_pages.size() > 1:
		_text("Page %d of %d" % [_jr_page + 1, _jr_pages.size()], Vector2(p.get_center().x, p.end.y - 40), 20, Color(1, 1, 1, 0.7))
		_box(_jr_prev_rect(), _jr_page > 0)
		_text("PREV", _jr_prev_rect().get_center() + Vector2(0, 7), 19, Color.WHITE if _jr_page > 0 else Color(1, 1, 1, 0.35))
		var more := _jr_page < _jr_pages.size() - 1
		_box(_jr_next_rect(), more)
		_text("NEXT", _jr_next_rect().get_center() + Vector2(0, 7), 19, Color.WHITE if more else Color(1, 1, 1, 0.35))


func _draw_players(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.78))
	var p := _panel()
	_box(p)
	_text("PLAYERS", p.position + Vector2(28, 60), 38, GOLD, false)
	_box(_rename_rect())
	_text("RENAME", _rename_rect().get_center() + Vector2(0, 7), 18, Color.WHITE)
	_box(_toggle_rect(), Online.enabled)
	_text("ONLINE: ON" if Online.enabled else "ONLINE: OFF", _toggle_rect().get_center() + Vector2(0, 7), 17, Color.WHITE)
	var status := "Not connected."
	if Online.connected:
		status = "You are %s.  Record %d wins, %d losses.  Walk up to a player and tap DUEL. In the Ashlands anyone may attack, and the loser pays." % [Online.my_name, Run.data.pvp_w, Run.data.pvp_l]
	elif Online.enabled:
		status = "Joining the shared world through %s ... If this never connects, your network may be blocking the relay." % Online.relay.get_slice("/", 2)
	var y := p.position.y + 104.0
	for row in _wrap(status, 18, p.size.x - 60.0):
		_text(row, Vector2(p.position.x + 28, y), 18, Color(1, 1, 1, 0.85), false)
		y += 24.0
	y += 10.0
	var ids: Array = Online.players.keys()
	if ids.is_empty() and Online.connected:
		_text("Nobody else is in the world right now.", Vector2(p.get_center().x, y + 60), 22, Color(1, 1, 1, 0.6))
	for i in mini(ids.size(), 8):
		var q: Dictionary = Online.players[ids[i]]
		var r := Rect2(p.position.x + 24, y + i * 58.0, p.size.x - 48, 50)
		_box(r)
		_text(String(q.get("n", "?")).left(16), r.position + Vector2(16, 33), 21, Color(0.55, 0.9, 1.0), false)
		_text("Combat %d" % int(q.get("cl", 1)), r.position + Vector2(300, 33), 18, Color.WHITE, false)
		_text("%d-%d" % [int(q.get("w", 0)), int(q.get("l", 0))], r.position + Vector2(470, 33), 18, Color.WHITE, false)
		var where := "In the tower"
		if not q.get("tw", false) and q.has("x"):
			where = "%s, %d m away%s" % [Land.BIOMES[Land.biome(float(q.x), float(q.z))].name, int(Vector2(float(q.x) - world.hero_pos.x, float(q.z) - world.hero_pos.z).length()),
				", fighting" if q.get("d", false) else ""]
		_text(where, r.position + Vector2(590, 33), 18, Color(1, 1, 1, 0.8), false, r.size.x - 610)
	_text("Shared through a public relay: names and positions are visible to anyone on it.  Tap outside the buttons to close.", Vector2(p.get_center().x, p.end.y - 18), 15, Color(1, 1, 1, 0.55), true, p.size.x - 60)


func _draw_perks(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.78))
	var p := _panel()
	_box(p)
	_text("PERKS", p.position + Vector2(28, 60), 38, GOLD, false)
	_text("%d to spend.  One point per four combat levels, and one per weapon mastery level." % Run.perk_points(), Vector2(p.get_center().x + 80, p.position.y + 54), 17, Color(1, 1, 1, 0.75), true, p.size.x - 320)
	var ids: Array = Craft.PERKS.keys()
	for i in ids.size():
		var info: Dictionary = Craft.PERKS[ids[i]]
		var r := _perk_rect(i)
		if i % 3 == 0:
			_text(info.tree.to_upper(), Vector2(r.get_center().x, r.position.y - 16), 20, GOLD)
		var have := Run.perk(ids[i])
		var open_now: bool = info.needs == "" or Run.perk(info.needs)
		_box(r, have)
		_text(info.name, Vector2(r.get_center().x, r.position.y + 40), 24, GOLD if have else Color(1, 1, 1, 0.9 if open_now else 0.4))
		_text(info.desc, Vector2(r.get_center().x, r.position.y + 74), 17, Color(1, 1, 1, 0.8 if open_now else 0.35), true, r.size.x - 20)
		_text("LEARNED" if have else ("TAP TO LEARN" if open_now else "LOCKED"), Vector2(r.get_center().x, r.position.y + 110), 15, Color(0.5, 1.0, 0.6) if have else Color(1, 1, 1, 0.6))
	_text(_note if _note_age < 2.5 else "Tap outside a perk to close", Vector2(p.get_center().x, p.end.y - 18), 17, Color(1, 1, 1, 0.85))


func _draw_list(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.78))
	var p := _panel()
	_box(p)
	var crafting := screen == "craft"
	var title := "%s  (level %d)" % [Craft.SKILLS[craft_skill].name.to_upper(), Run.skill(craft_skill)] if crafting else "TRADER: SELL"
	_text(title, p.position + Vector2(28, 60), 36, GOLD, false)
	var cr := _close_rect()
	_box(cr)
	draw_line(cr.position + Vector2(18, 18), cr.end - Vector2(18, 18), Color.WHITE, 4.0)
	draw_line(cr.position + Vector2(42, 18), cr.position + Vector2(18, 42), Color.WHITE, 4.0)
	var rows := _list_rows()
	if rows.size() > 15:
		_box(_page_rect())
		_text("MORE", _page_rect().get_center() + Vector2(0, 8), 22, Color.WHITE)
	if rows.is_empty():
		_text("Your pack is empty. Gather in the land, then sell here.", p.get_center(), 22, Color(1, 1, 1, 0.6))
	for i in mini(15, rows.size() - page * 15):
		var r := _row_rect(i)
		var row: Variant = rows[page * 15 + i]
		if crafting:
			var why := Craft.blocker(row)
			_box(r, why == "")
			_text(row.name, r.position + Vector2(14, 30), 20, GOLD if why == "" else Color(1, 1, 1, 0.75), false, r.size.x - 110)
			_text("Lv %d" % row.level, Vector2(r.end.x - 44, r.position.y + 30), 17, Color(0.5, 1.0, 0.6) if Run.skill(craft_skill) >= int(row.level) else Color(1.0, 0.45, 0.4))
			_text(Craft.inputs_text(row), r.position + Vector2(14, 56), 14, Color(1, 1, 1, 0.8), false, r.size.x - 28)
			_text("MAKE   +%d XP" % row.xp if why == "" else why, r.position + Vector2(14, 80), 14, Color(0.5, 1.0, 0.6) if why == "" else Color(1.0, 0.6, 0.5), false, r.size.x - 28)
		else:
			_box(r)
			var info: Dictionary = Craft.MATS[row]
			_text("%s  x%d" % [info.name, Run.mat(row)], r.position + Vector2(14, 34), 20, GOLD, false, r.size.x - 28)
			_text("Tap to sell up to 5 at %d gold each" % info.price, r.position + Vector2(14, 64), 14, Color(1, 1, 1, 0.75), false, r.size.x - 28)
	var foot := "%d gold" % Run.data.gold
	if crafting:
		foot = "Tools: %s axe, %s pick.   Arrows %d.   Flasks %d." % [Craft.TOOL_NAMES[int(Run.data.tools.axe)], Craft.TOOL_NAMES[int(Run.data.tools.pick)], Run.mat("arrow"), Run.data.potions]
	if _note_age < 2.5:
		foot = _note
	_text(foot, Vector2(p.get_center().x, p.end.y - 20), 18, Color(1, 1, 1, 0.9), true, p.size.x - 80)


func _map_xform() -> Dictionary:
	var p := _panel()
	var area := Rect2(p.position.x + 30, p.position.y + 84, p.size.x - 60, p.size.y - 110)
	var k := minf(area.size.x / (Land.X_MAX * 2.0), area.size.y / (Land.Z_MAX - Land.Z_MIN))
	var msize := Vector2(Land.X_MAX * 2.0, Land.Z_MAX - Land.Z_MIN) * k
	return {"k": k, "msize": msize, "origin": area.get_center() - msize * 0.5}


func _map_point(x: float, z: float) -> Vector2:
	var m := _map_xform()
	return m.origin + Vector2(x + Land.X_MAX, z - Land.Z_MIN) * float(m.k)


# A tap on the land map: on a discovered place it starts fast travel (or says why not).
# Returns false when the tap hit no marker, so the caller closes the map.
func _press_map(pos: Vector2) -> bool:
	var best := 34.0
	var hit := ""
	for m in world.travel.markers():
		var d := pos.distance_to(_map_point(m.pos.x, m.pos.y))
		if d < best:
			best = d
			hit = m.id
	if hit == "":
		return false
	var why: String = world.travel.request(hit)
	_close()
	if why != "":
		Run.captions.append(why)
	return true


func _draw_unstuck() -> void:
	var r := _unstuck_rect()
	_box(r)
	_text("UNSTUCK", r.get_center() + Vector2(0, 8), 22, Color.WHITE)
	var q := _quality_rect()
	_box(q)
	_text("QUALITY: %s" % Run.quality_choice().to_upper(), q.get_center() + Vector2(0, 7), 20, Color.WHITE)


func _draw_land_map(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.78))
	var p := _panel()
	_box(p)
	_text("THE LAND", p.position + Vector2(28, 60), 38, GOLD, false)
	_text("Tap a place to travel. Tap elsewhere to close.", Vector2((p.position.x + 250 + p.end.x - 470) * 0.5, p.position.y + 54), 18, Color(1, 1, 1, 0.6), true, p.end.x - 470 - p.position.x - 260)
	_draw_unstuck()
	var tex: ImageTexture = Overworld.build_map()
	var xf := _map_xform()
	var k: float = xf.k
	var msize: Vector2 = xf.msize
	var origin: Vector2 = xf.origin
	draw_texture_rect(tex, Rect2(origin, msize), false)
	draw_rect(Rect2(origin, msize), Color(GOLD.r, GOLD.g, GOLD.b, 0.6), false, 2.0)
	var at := func(x: float, z: float) -> Vector2: return origin + Vector2(x + Land.X_MAX, z - Land.Z_MIN) * k
	for label in [["Hearthvale", 0, 20], ["Greywood", -140, 0], ["Mirefen", -110, 140], ["The Scar", 150, 20], ["Lake Aren", 126, 132],
			["Old Ruins", 150, -190], ["Ashlands", -40, -170], ["Meadows", 30, 110]]:
		_text(label[0], at.call(float(label[1]), float(label[2])), 15, Color(1, 1, 1, 0.9))
	_diamond(at.call(Land.TOWER.x, Land.TOWER.y), 9.0, Color(1.0, 0.4, 0.15))
	_text("The Ashgrave", at.call(Land.TOWER.x, Land.TOWER.y - 16.0), 15, Color(1.0, 0.6, 0.3))
	for m in world.travel.markers():
		var c: Vector2 = at.call(m.pos.x, m.pos.y)
		var col := GOLD if m.ok else Color(0.7, 0.7, 0.7, 0.8)
		draw_circle(c, 11.0, Color(0, 0, 0, 0.7))
		draw_arc(c, 11.0, 0.0, TAU, 20, col, 3.0)
		draw_circle(c, 4.5, col)
		_text(m.label, c + Vector2(0, 28), 15, col)
	draw_circle(at.call(world.hero_pos.x, world.hero_pos.z), 6.0 + sin(_clock * 5.0), Color.WHITE)


func _draw_map(s: Vector2) -> void:
	if world.is_land:
		_draw_land_map(s)
		return
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.78))
	var p := _panel()
	_box(p)
	_text("THE TOWER", p.position + Vector2(28, 60), 38, GOLD, false)
	_text("Tap to close", Vector2(p.end.x - 530, p.position.y + 54), 18, Color(1, 1, 1, 0.6))
	_draw_unstuck()

	for t in range(1, Run.FLOORS + 1):
		var r := Rect2(p.position.x + 28, p.end.y - 40 - t * 92.0, 250, 80)
		var open_tier := t <= int(Run.data.unlocked)
		_box(r, t == world.tier)
		_text(Tiers.THEMES[t].name if open_tier else "Sealed", r.position + Vector2(16, 34), 20, GOLD if open_tier else Color(1, 1, 1, 0.4), false)
		var note := "Guardian slain" if Run.data.slain.has("t%d_guardian" % t) else ("You are here" if t == world.tier else "")
		if Run.data.relics.has(t) or Run.data.relics.has(float(t)):
			note += "   Relic found"
		_text(note.strip_edges(), r.position + Vector2(16, 62), 14, Color(1, 1, 1, 0.7), false)

	var area := Rect2(p.position.x + 320, p.position.y + 90, p.size.x - 360, p.size.y - 130)
	var bounds: Rect2 = world.rects[0]
	for r2 in world.rects:
		bounds = bounds.merge(r2)
	var k := minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y)
	var off := area.get_center() - bounds.get_center() * k
	for r2 in world.rects:
		draw_rect(Rect2((r2 as Rect2).position * k + off, (r2 as Rect2).size * k), Color(0.35, 0.32, 0.3))
	for e in world.ents:
		var c := Vector2(e.pos.x, e.pos.z) * k + off
		match e.type:
			"foe": _diamond(c, 9.0 if e.kind == "guardian" else 6.0, {"guardian": Color(1.0, 0.3, 0.2), "elite": Color(1.0, 0.6, 0.2), "lesser": Color(0.85, 0.8, 0.7)} [e.kind])
			"smith": draw_circle(c, 7.0, Color(1.0, 0.8, 0.3))
			"chest": draw_rect(Rect2(c - Vector2(6, 5), Vector2(12, 10)), Color(0.9, 0.7, 0.2))
			"relic": _diamond(c, 6.0, Color(0.6, 0.9, 1.0))
			"brazier": draw_circle(c, 5.0, Color(1.0, 0.5, 0.15))
			"exit", "entry": draw_rect(Rect2(c - Vector2(12, 3), Vector2(24, 6)), GOLD)
	var hp := Vector2(world.hero_pos.x, world.hero_pos.z) * k + off
	draw_circle(hp, 7.0 + sin(_clock * 5.0), Color.WHITE)
	var ly := p.end.y - 26
	_text("Red: guardian    Orange: elite    Gold dot: smith    Blue: relic    White: you", Vector2(area.get_center().x, ly), 15, Color(1, 1, 1, 0.65), true, area.size.x)
