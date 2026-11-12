class_name Hud
extends Control

const SWIPE_MIN := 60.0
const BTN := 160.0
const GOLD := Color(1.0, 0.84, 0.55)

var duel: Duel

var _swipe_touch := -1
var _swipe_start := Vector2.ZERO
var _block_touch := -1
var _trail: Array = []
var _banners: Array = []
var _floaters: Array = []
var _streaks: Array = []
var _hurt := 0.0
var _result_shown := false
var _result_win := false
var _result_age := 0.0
var _font: Font
var _vignette: GradientTexture2D
var _edge_tex: GradientTexture2D
var _edge := 0.0
var _edge_col := Color.WHITE
var _pulse := 0.0
var _e_hp_lag := 1.0
var _p_hp_lag := 1.0
var _clock := 0.0
var _caption := ""
var _caption_age := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://fonts/cinzel-700.woff2"):
		_font = load("res://fonts/cinzel-700.woff2")
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.62))
	g.set_offset(0, 0.45)
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.0, 1.0)
	_vignette.width = 128
	_vignette.height = 128
	# White at the screen edge and clear in the middle; tinted when drawn (edge flashes).
	var ge := Gradient.new()
	ge.set_color(0, Color(1, 1, 1, 0))
	ge.set_color(1, Color(1, 1, 1, 0.85))
	ge.set_offset(0, 0.5)
	_edge_tex = GradientTexture2D.new()
	_edge_tex.gradient = ge
	_edge_tex.fill = GradientTexture2D.FILL_RADIAL
	_edge_tex.fill_from = Vector2(0.5, 0.5)
	_edge_tex.fill_to = Vector2(1.0, 1.0)
	_edge_tex.width = 64
	_edge_tex.height = 64


func _rects() -> Dictionary:
	var s := size
	var m := 26.0
	var mx := 50.0
	return {
		"dodge_l": Rect2(mx, s.y - BTN - m, BTN, BTN),
		"dodge_r": Rect2(s.x - BTN - mx, s.y - BTN - m, BTN, BTN),
		"block": Rect2(s.x * 0.5 - BTN * 0.55, s.y - BTN * 0.85 - m, BTN * 1.1, BTN * 0.85),
		"super": Rect2(s.x - BTN * 0.8 - mx, s.y - BTN * 1.95 - m * 2.0, BTN * 0.8, BTN * 0.8),
		"pause": Rect2(s.x - 64 - mx, 30, 64, 64),
		"flask": Rect2(mx + BTN * 0.1, s.y - BTN * 1.95 - m * 2.0, BTN * 0.8, BTN * 0.8),
		"spell": Rect2(mx + BTN * 0.1, s.y - BTN * 2.8 - m * 2.6, BTN * 0.8, BTN * 0.8),
		"ranged": Rect2(s.x - BTN * 0.8 - mx, s.y - BTN * 2.8 - m * 2.6, BTN * 0.8, BTN * 0.8),
	}


func _alert_rect(i: int) -> Rect2:
	var o: Dictionary = duel.others[i]
	var x := 250.0 if float(o.side) < 0.0 else size.x - 250.0 - 96.0
	return Rect2(x, 130 + (i / 2) * 110.0, 96, 96)


func _menu_rects() -> Array:
	var s := size
	var w := 420.0
	var out := []
	for i in 3:
		out.append(Rect2(s.x * 0.5 - w * 0.5, s.y * 0.3 + i * 78.0, w, 62))
	return out


func _card_rects(n: int) -> Array:
	var s := size
	var w := minf(310.0, (s.x - 120.0) / 3.0 - 20.0)
	var total := n * w + (n - 1) * 24.0
	var out := []
	for i in n:
		out.append(Rect2(s.x * 0.5 - total * 0.5 + i * (w + 24.0), s.y * 0.56, w, 190))
	return out


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _swipe_touch and not duel.paused:
			_trail.append({"p": event.position, "t": 0.0})
			var v: Vector2 = event.position - _swipe_start
			if v.length() >= SWIPE_MIN:
				duel.input_swipe(v)

				_swipe_start = event.position
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_A, KEY_LEFT: duel.input_dodge(-1)
			KEY_D, KEY_RIGHT: duel.input_dodge(1)
			KEY_SPACE: duel.input_block(true)
			KEY_F: duel.input_super()
			KEY_Q: duel.input_potion()
			KEY_R: duel.input_ranged()
			KEY_C: duel.input_spell()
			KEY_ESCAPE, KEY_P: duel.set_paused(not duel.paused)
			KEY_ENTER:
				if not duel.started:
					duel.begin()
				elif _result_shown and _result_age > 0.8:
					duel.proceed("")
	elif event is InputEventKey and not event.pressed and event.keycode == KEY_SPACE:
		duel.input_block(false)


func _on_press(index: int, pos: Vector2) -> void:
	if not duel.started:
		duel.begin()
		return
	if _result_shown:
		_press_result(pos)
		return
	var r := _rects()
	if duel.paused:
		var m := _menu_rects()
		if m[0].has_point(pos) or r.pause.has_point(pos):
			duel.set_paused(false)
		elif m[1].has_point(pos):
			Run.data.assist = not Run.data.assist
			Run.save()
		elif m[2].has_point(pos):
			Run.data.sound = not Run.data.sound
			AudioServer.set_bus_mute(0, not Run.data.sound)
			Run.save()
		return
	for i in duel.others.size():
		if _alert_rect(i).grow(14).has_point(pos):
			duel.switch_target(i)
			return
	if r.pause.has_point(pos):
		duel.set_paused(true)
	elif r.dodge_l.has_point(pos):
		duel.input_dodge(-1)
	elif r.dodge_r.has_point(pos):
		duel.input_dodge(1)
	elif r.block.has_point(pos):
		_block_touch = index
		duel.input_block(true)
	elif r.super.has_point(pos):
		duel.input_super()
	elif r.flask.has_point(pos):
		duel.input_potion()
	elif duel.spell_id != "" and r.spell.has_point(pos):
		duel.input_spell()
	elif duel.ranged_id != "" and r.ranged.has_point(pos):
		duel.input_ranged()
	elif _swipe_touch == -1:
		_swipe_touch = index
		_swipe_start = pos
		_trail.clear()
		_trail.append({"p": pos, "t": 0.0})


func _press_result(_pos: Vector2) -> void:
	if _result_age >= 0.8:
		duel.proceed("")


func _on_release(index: int) -> void:
	if index == _block_touch:
		_block_touch = -1
		duel.input_block(false)
	if index == _swipe_touch:
		_swipe_touch = -1


func banner(text: String, color: Color, life := 0.8) -> void:
	_banners.append({"text": text, "color": color, "age": 0.0, "life": life})
	if _banners.size() > 2:
		_banners.pop_front()


func float_text(text: String, world_pos: Vector3, color: Color, big := false) -> void:
	var cam: Camera3D = duel.cam
	if cam.is_position_behind(world_pos):
		return
	_floaters.append({"text": text, "color": color, "pos": cam.unproject_position(world_pos), "age": 0.0, "big": big})


func slash_streak(v: Vector2, heavy := false) -> void:
	var c := size * Vector2(0.5, 0.42) + Vector2(randf_range(-40, 40), randf_range(-40, 40))
	var d := v.normalized() * size.y * (0.6 if heavy else 0.42)
	_streaks.append({"a": c - d, "b": c + d, "age": 0.0,
		"color": Color(1.0, 0.8, 0.4) if heavy else Color.WHITE, "w": 18.0 if heavy else 10.0})


func enemy_streak(dir: int) -> void:
	var c := size * 0.5
	var d: Vector2 = [Vector2(1, 0.25), Vector2(-1, 0.25), Vector2(0.15, 1), Vector2(0.3, 0.3)][dir]
	d = d.normalized() * size.x * 0.45
	_streaks.append({"a": c - d, "b": c + d, "age": 0.0, "color": Color(1.0, 0.2, 0.15), "w": 22.0})


func shot_streak() -> void:
	_streaks.append({"a": size * Vector2(0.2, 0.75), "b": size * Vector2(0.5, 0.42), "age": 0.0, "color": Color(0.9, 0.95, 1.0), "w": 7.0})


func caption(text: String) -> void:
	if text != "":
		_caption = text
		_caption_age = 0.0


func hurt_flash() -> void:
	_hurt = 1.0


## A coloured flash round the screen edge: gold for a perfect parry, blue when the player's posture breaks.
func edge_flash(color: Color) -> void:
	_edge = 1.0
	_edge_col = color


## The foe's posture bar swells for a moment (perfect parry, posture broken).
func posture_pulse() -> void:
	_pulse = 1.0


func show_result(win: bool) -> void:
	_result_shown = true
	_result_win = win
	_result_age = 0.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	_clock += real
	for t in _trail:
		t.t += real
	_trail = _trail.filter(func(t): return t.t < 0.25)
	for b in _banners:
		b.age += real
	_banners = _banners.filter(func(b): return b.age < b.life)
	for f in _floaters:
		f.age += real
	_floaters = _floaters.filter(func(f): return f.age < 0.8)
	for s in _streaks:
		s.age += real
	_streaks = _streaks.filter(func(s): return s.age < 0.18)
	_hurt = move_toward(_hurt, 0.0, real * 2.5)
	_edge = move_toward(_edge, 0.0, real * 2.8)
	_pulse = move_toward(_pulse, 0.0, real * 2.0)
	_caption_age += real
	if _result_shown:
		_result_age += real
	_e_hp_lag = move_toward(_e_hp_lag, duel.e_hp / duel.def.max_hp, real * 0.35)
	_p_hp_lag = move_toward(_p_hp_lag, duel.p_hp / duel.player_max_hp, real * 0.35)
	queue_redraw()


func _text(text: String, pos: Vector2, font_size: int, color: Color, centered := true, zoom := 1.0) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := pos - Vector2(w * 0.5, 0) if centered else pos
	if zoom != 1.0:
		draw_set_transform(pos, 0.0, Vector2(zoom, zoom))
		p -= pos
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, color.a * 0.8))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	if zoom != 1.0:
		draw_set_transform(Vector2.ZERO)


func _bar(r: Rect2, frac: float, lag: float, fill: Color, trim := true) -> void:
	draw_rect(r.grow(3), Color(0, 0, 0, 0.65))
	draw_rect(r, Color(0.1, 0.1, 0.12, 0.9))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(lag, 0, 1), r.size.y)), Color(1, 1, 1, 0.55))
	var fr := Rect2(r.position, Vector2(r.size.x * clampf(frac, 0, 1), r.size.y))
	draw_rect(fr, fill)
	draw_rect(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.4)), Color(1, 1, 1, 0.16))
	if trim:
		draw_rect(r.grow(3), Color(GOLD.r, GOLD.g, GOLD.b, 0.55), false, 1.5)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _disc(r: Rect2, active: bool, tint: Color) -> Vector2:
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.5
	draw_circle(c, rad, Color(0, 0, 0, 0.28))
	draw_circle(c, rad, Color(tint.r, tint.g, tint.b, 0.42 if active else 0.14))
	draw_arc(c, rad, 0, TAU, 48, Color(tint.r, tint.g, tint.b, 0.95 if active else 0.55), 3.0, true)
	return c


func _chevrons(c: Vector2, dir: float, col: Color) -> void:
	for i in 2:
		var x := c.x + dir * (i * 22.0 - 16.0)
		draw_polyline(PackedVector2Array([Vector2(x - dir * 14, c.y - 24), Vector2(x + dir * 10, c.y), Vector2(x - dir * 14, c.y + 24)]), col, 6.0, true)


func _arrow(c: Vector2, d: Vector2, col: Color, length := 64.0, width := 8.0) -> void:
	var tip := c + d * length * 0.5
	var tail := c - d * length * 0.5
	var n := Vector2(-d.y, d.x)
	draw_line(tail, tip, col, width, true)
	draw_colored_polygon(PackedVector2Array([tip + d * 18.0, tip + n * 18.0, tip - n * 18.0]), col)


func _draw() -> void:
	var s := size
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, s), false)
	if _hurt > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0.05, 0.05, _hurt * 0.35))
	if _edge > 0.0:
		draw_texture_rect(_edge_tex, Rect2(Vector2.ZERO, s), false, Color(_edge_col.r, _edge_col.g, _edge_col.b, _edge))
	var bars: float = duel.cinematic * s.y * 0.1
	if bars > 0.5:
		draw_rect(Rect2(0, 0, s.x, bars), Color.BLACK)
		draw_rect(Rect2(0, s.y - bars, s.x, bars), Color.BLACK)

	var ui: float = 1.0 - clampf(duel.cinematic * 2.0, 0.0, 1.0)
	if ui > 0.01 and not _result_shown:
		_draw_meters(s)
		_draw_telegraph(s)
		_draw_tutorial(s)

	for st in _streaks:
		var a: float = 1.0 - st.age / 0.18
		var col: Color = st.color
		col.a = a
		draw_line(st.a, st.b, col, float(st.w) * a + 2.0, true)
	if _trail.size() >= 2:
		for i in range(1, _trail.size()):
			var a2: float = 1.0 - _trail[i].t / 0.25
			draw_line(_trail[i - 1].p, _trail[i].p, Color(1.0, 0.92, 0.7, a2 * 0.9), 10.0 * a2 + 1.0, true)

	for f in _floaters:
		var k: float = f.age / 0.8
		var fc: Color = f.color
		fc.a = 1.0 - k * k
		_text(f.text, f.pos + Vector2(0, -70.0 * k), 54 if f.big else 34, fc)

	var by := s.y * 0.3
	for b in _banners:
		var k2: float = b.age / b.life
		var bc: Color = b.color
		bc.a = clampf((1.0 - k2) * 3.0, 0.0, 1.0)
		_text(b.text, Vector2(s.x * 0.5, by), 52, bc, true, 0.96 + 0.35 * (1.0 - minf(b.age * 8.0, 1.0)))
		by += 62.0

	var exec_ready: bool = (duel.e_state == Duel.EState.OPEN and duel.open_reason == "posture" and duel.result == "") \
		or (not duel.pvp.is_empty() and Time.get_ticks_msec() < duel.pvp_exec_until and duel.result == "")
	if exec_ready:
		var xp := 0.65 + 0.35 * sin(_clock * 14.0)
		_text("SWIPE TO EXECUTE", Vector2(s.x * 0.5, s.y * 0.52), 60, Color(1.0, 0.72, 0.3, xp))
	elif duel.e_state == Duel.EState.FINISHER:
		var pulse := 0.6 + 0.4 * sin(_clock * 12.0)
		_text("SWIPE TO FINISH", Vector2(s.x * 0.5, s.y * 0.52), 60, Color(1, 0.9, 0.6, pulse))
		if duel.can_spare:
			_text("OR HOLD BLOCK TO STAY YOUR HAND", Vector2(s.x * 0.5, s.y * 0.62), 28, Color(0.7, 0.85, 1.0, 0.9))
		if duel.def.display_name in ["The Hollow Regent", "The Usurper King"]:
			_text("OR TAP SURGE TO TAKE THE THRONE", Vector2(s.x * 0.5, s.y * 0.7), 26, Color(1.0, 0.6, 0.25, 0.9))
	elif duel.e_state == Duel.EState.OPEN and duel.result == "" and duel.tutorial_hint == "":
		_text("STRIKE!", Vector2(s.x * 0.5, s.y * 0.22), 30, Color(1, 0.95, 0.75, 0.85))

	if _caption != "" and _caption_age < 4.5 and not _result_shown:
		var ca := clampf(minf(_caption_age * 3.0, (4.5 - _caption_age) * 2.0), 0.0, 1.0)
		var cw := _font.get_string_size(_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 60.0
		draw_rect(Rect2(s.x * 0.5 - cw * 0.5, s.y * 0.66 - 30, cw, 44), Color(0, 0, 0, 0.55 * ca))
		_text("\"" + _caption + "\"", Vector2(s.x * 0.5, s.y * 0.66), 22, Color(1, 0.95, 0.85, ca))
	if _result_shown:
		_draw_result(s)
	elif ui > 0.01 or (duel.e_state == Duel.EState.FINISHER and duel.def.kind == "guardian"):
		_draw_buttons()
		if duel.paused:
			_draw_pause(s)


func _draw_title(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.25))
	_text("ASHGRAVE", Vector2(s.x * 0.5, s.y * 0.36), 120, GOLD)
	draw_line(Vector2(s.x * 0.5 - 260, s.y * 0.4), Vector2(s.x * 0.5 + 260, s.y * 0.4), Color(GOLD.r, GOLD.g, GOLD.b, 0.6), 2.0)
	_diamond(Vector2(s.x * 0.5, s.y * 0.4), 8.0, GOLD)
	var d: Dictionary = Run.data
	var line := "Bloodline %d     Level %d     Stair %d of %d" % [d.bloodline, d.level, d.floor, Run.FLOORS]
	if int(d.loop) > 0:
		line += "     Ascension %d" % d.loop
	_text(line, Vector2(s.x * 0.5, s.y * 0.48), 24, Color(1, 1, 1, 0.8))
	_text("TAP TO BEGIN", Vector2(s.x * 0.5, s.y * 0.74), 36, Color(1, 1, 1, 0.55 + 0.45 * sin(_clock * 3.0)))


func _draw_meters(s: Vector2) -> void:
	draw_set_transform(Vector2(0, 12))
	var ew := minf(s.x * 0.46, 600.0)
	var ex := (s.x - ew) * 0.5
	_text(duel.def.display_name, Vector2(s.x * 0.5, 42), 26, Color(1.0, 0.86, 0.7))
	_bar(Rect2(ex, 54, ew, 18), duel.e_hp / duel.def.max_hp, _e_hp_lag,
		Color(0.98, 0.35, 0.12) if duel.enraged else Color(0.82, 0.16, 0.16))
	var pr := Rect2(ex + ew * 0.15, 79, ew * 0.7, 8)
	var pfrac: float = duel.e_posture / duel.def.break_max
	var full: bool = pfrac >= 0.999
	if _pulse > 0.0 or full:
		var sw: float = _pulse * 5.0 + (3.0 + 2.0 * sin(_clock * 14.0) if full else 0.0)
		draw_rect(pr.grow(3.0 + sw), Color(1.0, 0.85, 0.3, 0.25 + 0.3 * maxf(_pulse, 1.0 if full else 0.0)))
	_bar(pr, pfrac, 0.0, Color(1.0, 0.95, 0.6) if full else Color(1.0, 0.8, 0.25), false)
	draw_rect(pr.grow(1.0), Color(1.0, 0.8, 0.25, 0.3), false, 1.0)
	_diamond(Vector2(pr.position.x - 14.0, pr.position.y + 4.0), 6.0 + 3.0 * _pulse, Color(1.0, 0.8, 0.25))
	_diamond(Vector2(ex - 16, 63), 9.0, GOLD)
	_diamond(Vector2(ex + ew + 16, 63), 9.0, GOLD)

	draw_set_transform(Vector2(30, 12))
	_text("LV %d" % Run.combat_level(), Vector2(28, 40), 20, GOLD, false)
	_bar(Rect2(92, 24, 250, 16), duel.p_hp / duel.player_max_hp, _p_hp_lag, Color(0.3, 0.8, 0.4))
	var ppost: float = 1.0 - duel.shield / maxf(duel.shield_max, 1.0)
	_bar(Rect2(92, 48, 170, 7), ppost, 0.0, Color(0.45, 0.65, 1.0).lerp(Color(1.0, 0.55, 0.35), clampf((ppost - 0.7) / 0.3, 0.0, 1.0)), false)
	draw_rect(Rect2(92, 48, 170, 7).grow(1.0), Color(0.45, 0.65, 1.0, 0.35), false, 1.0)
	_diamond(Vector2(78, 52), 6.0, Color(0.45, 0.65, 1.0))
	for i in (Run.FLOORS if Run.data.in_tower else 0):
		var here: bool = i + 1 == int(Run.data.floor)
		var done: bool = i + 1 < int(Run.data.floor)
		_diamond(Vector2(100 + i * 24.0, 76), 9.0 if here else 6.0,
			GOLD if here else (Color(0.6, 0.55, 0.45) if done else Color(1, 1, 1, 0.22)))

	draw_set_transform(Vector2.ZERO)
	if duel.hit_combo >= 2:
		_text("%d HITS" % duel.hit_combo, Vector2(s.x - 190, s.y * 0.3), 38, Color(1.0, 0.9, 0.5))


func _draw_buttons() -> void:
	var r := _rects()
	var can_dodge: bool = duel.dodge_charges >= 1.0
	var dcol := Color(0.7, 0.85, 1.0) if can_dodge else Color(0.5, 0.5, 0.55)
	var cl := _disc(r.dodge_l, duel.p_state == Duel.PState.DODGE and duel.dodge_dir < 0, dcol)
	_chevrons(cl, -1.0, Color(1, 1, 1, 0.85 if can_dodge else 0.35))
	var cr := _disc(r.dodge_r, duel.p_state == Duel.PState.DODGE and duel.dodge_dir > 0, dcol)
	_chevrons(cr, 1.0, Color(1, 1, 1, 0.85 if can_dodge else 0.35))
	for side in [cl, cr]:
		for i in duel.dodge_max:
			var filled: bool = duel.dodge_charges >= i + 1
			_diamond(side + Vector2((i - (duel.dodge_max - 1) * 0.5) * 22.0, -BTN * 0.5 - 16.0), 7.0,
				Color(0.6, 0.9, 1.0) if filled else Color(1, 1, 1, 0.2))

	var has_shield: bool = duel.shield > 0.0
	var cb := _disc(r.block, duel.blocking, Color(0.5, 0.7, 1.0) if has_shield else Color(0.6, 0.35, 0.3))
	var sc := Color(1, 1, 1, 0.85 if has_shield else 0.35)
	draw_polyline(PackedVector2Array([cb + Vector2(-22, -24), cb + Vector2(22, -24), cb + Vector2(22, 4),
		cb + Vector2(0, 28), cb + Vector2(-22, 4), cb + Vector2(-22, -24)]), sc, 5.0, true)

	if not duel.pvp.is_empty():
		var mine: bool = duel.pvp_turn == "attack"
		var hint := "YOUR ATTACK: SWIPE LEFT, RIGHT, DOWN OR UP" if mine else "DEFEND: PARRY, DODGE OR BLOCK"
		_text(hint, Vector2(size.x * 0.5, 130), 22, Color(1.0, 0.85, 0.5) if mine else Color(0.65, 0.85, 1.0))
		for i in 3:
			_diamond(Vector2(size.x * 0.5 + (i - 1) * 30.0, 158), 9.0, Color(1.0, 0.8, 0.3) if mine and i < duel.pvp_left else Color(1, 1, 1, 0.2))
		var pc2: Vector2 = r.pause.get_center()
		draw_rect(Rect2(pc2 + Vector2(-13, -15), Vector2(8, 30)), Color(1, 1, 1, 0.6))
		draw_rect(Rect2(pc2 + Vector2(5, -15), Vector2(8, 30)), Color(1, 1, 1, 0.6))
		return
	var full: bool = duel.super_meter >= 100.0
	var glow := 0.5 + 0.5 * sin(_clock * 8.0) if full else 0.0
	var cs: Vector2 = r.super.get_center()
	var srad: float = r.super.size.x * 0.5
	draw_circle(cs, srad, Color(0, 0, 0, 0.3))
	draw_circle(cs, srad, Color(1.0, 0.55, 0.15, 0.25 + 0.3 * glow if full else 0.1))
	draw_arc(cs, srad, -PI * 0.5, -PI * 0.5 + TAU * duel.super_meter / 100.0, 48, Color(1.0, 0.6, 0.2), 7.0, true)
	_text("SURGE", cs + Vector2(0, 8), 20, Color(1, 1, 1, 1.0 if full else 0.45))

	var flasks := int(Run.data.potions)
	var cf := _disc(r.flask, false, Color(0.4, 1.0, 0.55) if flasks > 0 else Color(0.5, 0.5, 0.5))
	draw_polyline(PackedVector2Array([cf + Vector2(-8, -24), cf + Vector2(8, -24), cf + Vector2(8, -10), cf + Vector2(20, 14),
		cf + Vector2(12, 24), cf + Vector2(-12, 24), cf + Vector2(-20, 14), cf + Vector2(-8, -10), cf + Vector2(-8, -24)]),
		Color(1, 1, 1, 0.85 if flasks > 0 else 0.3), 4.0, true)
	_text(str(flasks), cf + Vector2(34, -22), 22, Color(1, 1, 1, 0.9))
	if duel.spell_id != "":
		var ready: bool = duel.mana >= 100.0
		var scol: Color = {"ember_bolt": Items.ELEMENT_COLORS.ember, "frost_bind": Items.ELEMENT_COLORS.frost}.get(duel.spell_id, Color(0.6, 0.75, 1.0))
		var csp: Vector2 = r.spell.get_center()
		var rad: float = r.spell.size.x * 0.5
		draw_circle(csp, rad, Color(0, 0, 0, 0.3))
		draw_circle(csp, rad, Color(scol.r, scol.g, scol.b, 0.3 + 0.2 * sin(_clock * 8.0) if ready else 0.1))
		draw_arc(csp, rad, -PI * 0.5, -PI * 0.5 + TAU * duel.mana / 100.0, 48, scol, 6.0, true)
		_text("SPELL", csp + Vector2(0, 8), 20, Color(1, 1, 1, 1.0 if ready else 0.45))
	if duel.ranged_id != "":
		var has: bool = duel.shots > 0
		var crg := _disc(r.ranged, false, Color(0.9, 0.95, 1.0) if has else Color(0.5, 0.5, 0.5))
		_arrow(crg + Vector2(-4, 4), Vector2(0.7, -0.7), Color(1, 1, 1, 0.85 if has else 0.3), 44.0, 5.0)
		_text(str(duel.shots), crg + Vector2(36, -22), 22, Color(1, 1, 1, 0.9))

	for i in duel.others.size():
		var o: Dictionary = duel.others[i]
		var ar := _alert_rect(i)
		var ac := ar.get_center()
		var warn: bool = float(o.tell) > 0.0
		var acol := Color(1.0, 0.2, 0.15) if warn else Color(1.0, 0.8, 0.5)
		draw_circle(ac, 48.0, Color(0, 0, 0, 0.45))
		draw_circle(ac, 48.0, Color(acol.r, acol.g, acol.b, 0.35 + 0.3 * sin(_clock * 16.0) if warn else 0.12))
		draw_arc(ac, 48.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(o.hp) / (o.def as EnemyDef).max_hp, 0.0, 1.0), 40, acol, 5.0, true)
		if warn:
			_text("!", ac + Vector2(0, 20), 60, acol)
		else:
			_arrow(ac, Vector2.LEFT if float(o.side) < 0.0 else Vector2.RIGHT, Color(1, 1, 1, 0.8), 40.0, 5.0)
		_text((o.def as EnemyDef).display_name, ac + Vector2(0, 70), 15, Color(1, 1, 1, 0.8))
	if duel.warded:
		_text("WARDED", Vector2(size.x * 0.5, size.y - 190), 20, Color(0.6, 0.75, 1.0, 0.9))
	var pc: Vector2 = r.pause.get_center()
	draw_rect(Rect2(pc + Vector2(-13, -15), Vector2(8, 30)), Color(1, 1, 1, 0.6))
	draw_rect(Rect2(pc + Vector2(5, -15), Vector2(8, 30)), Color(1, 1, 1, 0.6))


func _draw_telegraph(s: Vector2) -> void:
	if not Run.data.assist and not duel.tutorial:
		return
	if duel.e_state != Duel.EState.WINDUP:
		return
	var c := s * Vector2(0.5, 0.42)
	var left: float = duel.e_timer
	var a: AttackDef = duel.cur_attack
	var thrust := a.dir == AttackDef.Dir.THRUST
	var in_window: bool = left <= duel.parry_window and not thrust
	var col: Color = Color(1.0, 1.0, 0.85) if in_window else duel.tell_color()

	var k := clampf(left / duel.windup_total, 0.0, 1.0)
	draw_arc(c, 46.0, 0, TAU, 48, Color(col.r, col.g, col.b, 0.5), 3.0, true)
	draw_arc(c, 46.0 + 130.0 * k, 0, TAU, 64, col, 6.0 if in_window else 3.0, true)
	if thrust:
		_text("!", c + Vector2(0, 22), 64, col)
		_text("DODGE", c + Vector2(0, 112), 24, col)
		return

	_arrow(c, [Vector2.LEFT, Vector2.RIGHT, Vector2.UP][a.dir], col)
	if a.heavy:
		_text("CANNOT BLOCK", c + Vector2(0, 112), 22, duel.tell_color())


func _draw_tutorial(s: Vector2) -> void:
	var hint: String = duel.tutorial_hint
	if hint == "":
		return
	var msg := ""
	var c := Vector2(s.x * 0.5, s.y * 0.7)
	match hint:
		"parry":
			if duel.e_state != Duel.EState.WINDUP:
				return
			var word: String = ["LEFT", "RIGHT", "UP"][duel.cur_attack.dir]
			var now: bool = duel.e_timer <= duel.parry_window
			msg = "NOW! SWIPE %s" % word if now else "WAIT FOR THE RING, THEN SWIPE %s" % word
			if now:
				var d: Vector2 = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP][duel.cur_attack.dir]
				var ph := fmod(_clock * 1.6, 1.0)
				var gc := s * Vector2(0.5, 0.42) + d * (ph - 0.5) * 300.0
				draw_circle(gc, 26.0, Color(1, 1, 1, 0.75 * (1.0 - ph)))
		"dodge":
			if duel.e_state != Duel.EState.WINDUP:
				return
			msg = "RED BLADE CANNOT BE PARRIED: TAP DODGE"
		"strike":
			msg = "SWIPE BACK AND FORTH TO STRIKE"
		"execute":
			msg = "THE GOLD BAR IS FULL: ONE SWIPE EXECUTES"
	var w := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 60.0
	draw_rect(Rect2(c.x - w * 0.5, c.y - 38, w, 56), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(c.x - w * 0.5, c.y - 38, w, 56), Color(GOLD.r, GOLD.g, GOLD.b, 0.7), false, 2.0)
	_text(msg, c, 28, Color.WHITE)


func _draw_pause(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.72))
	_text("PAUSED", Vector2(s.x * 0.5, s.y * 0.2), 60, GOLD)
	var labels := ["RESUME", "GUIDE ARROWS: %s" % ("ON" if Run.data.assist else "OFF"), "SOUND: %s" % ("ON" if Run.data.sound else "OFF")]
	var m := _menu_rects()
	for i in 3:
		var r: Rect2 = m[i]
		draw_rect(r, Color(0.12, 0.11, 0.1, 0.9))
		draw_rect(r, Color(GOLD.r, GOLD.g, GOLD.b, 0.7), false, 2.0)
		_text(labels[i], r.get_center() + Vector2(0, 10), 28, Color.WHITE)
	var y := s.y * 0.3 + 3 * 78.0 + 40.0
	_text("COMBOS WHILE THE ENEMY IS OPEN", Vector2(s.x * 0.5, y), 20, Color(1, 1, 1, 0.6))
	var rows := [["FLURRY", [Vector2.LEFT, Vector2.RIGHT, Vector2.LEFT]], ["CLEAVE", [Vector2.LEFT, Vector2.LEFT, Vector2.RIGHT, Vector2.RIGHT]],
		["TEMPEST", [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]]]
	for i in rows.size():
		var cx := s.x * 0.5 + (i - 1) * 300.0
		_text(rows[i][0], Vector2(cx, y + 44.0), 22, GOLD)
		var arr: Array = rows[i][1]
		for j in arr.size():
			_arrow(Vector2(cx + (j - (arr.size() - 1) * 0.5) * 46.0, y + 78.0), arr[j], Color(1, 1, 1, 0.85), 20.0, 4.0)


func _draw_result(s: Vector2) -> void:
	var a := clampf(_result_age * 2.0, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.7 * a))
	var st: Dictionary = duel.stats
	var rw: Dictionary = duel.reward
	var stat_line := "Time %d:%02d     Parries %d (%d perfect)     Best combo %d     Hits taken %d" % [
		int(st.time) / 60, int(st.time) % 60, st.parries, st.perfect, st.best_combo, st.hits_taken]
	if int(st.execs) > 0:
		stat_line += "     Executions %d" % st.execs
	var y := s.y * 0.18
	if not duel.pvp.is_empty():
		var pt := "VICTORY" if _result_win else "DEFEATED"
		_text(pt, Vector2(s.x * 0.5, y), 68, Color(GOLD.r, GOLD.g, GOLD.b, a) if _result_win else Color(0.9, 0.3, 0.25, a))
		var line := "You bested %s." % duel.pvp.name if _result_win else "%s bested you." % duel.pvp.name
		if rw.get("left", false):
			line = "%s left the duel." % duel.pvp.name
		if int(rw.get("gold", 0)) > 0:
			line += "  You take %d gold." % rw.gold
		if int(rw.get("lost_gold", 0)) > 0:
			line += "  You lose %d gold." % rw.lost_gold
		_text(line, Vector2(s.x * 0.5, y + 56), 24, Color(1, 1, 1, a * 0.9))
	elif _result_win:
		var title := "THE FIRE GOES OUT" if rw.get("spared", false) else ("THE TOWER FALLS" if rw.get("cleared", false) else "VICTORY")
		_text(title, Vector2(s.x * 0.5, y), 68, Color(GOLD.r, GOLD.g, GOLD.b, a))
		var loot := "+%d gold" % rw.get("gold", 0)
		for d in rw.get("drops", []):
			loot += "     %s" % d
		if rw.get("flawless", false):
			loot += "     Flawless"
		_text(loot, Vector2(s.x * 0.5, y + 56), 26, Color(1.0, 0.88, 0.5, a))
	elif duel.was_in_tower:
		_text("YOU HAVE FALLEN", Vector2(s.x * 0.5, y), 68, Color(0.9, 0.3, 0.25, a))
		_text("Bloodline %d takes up the sword. Your skills and gear endure." % Run.data.bloodline, Vector2(s.x * 0.5, y + 56), 24, Color(1, 1, 1, a * 0.9))
	else:
		_text("DEFEATED", Vector2(s.x * 0.5, y), 68, Color(0.9, 0.3, 0.25, a))
		_text("You are carried back to Hearthvale. Nothing is lost.", Vector2(s.x * 0.5, y + 56), 24, Color(1, 1, 1, a * 0.9))
	_text(stat_line, Vector2(s.x * 0.5, y + 100), 18, Color(1, 1, 1, a * 0.6))

	var gains: Array = rw.get("gains", [])
	var gy := y + 160.0
	for i in gains.size():
		var g: Array = gains[i]
		var ga := clampf((_result_age - 0.3 - i * 0.12) * 4.0, 0.0, 1.0)
		var row := Rect2(s.x * 0.5 - 300, gy + i * 50.0, 600, 42)
		draw_rect(row, Color(0.1, 0.09, 0.08, 0.9 * ga))
		draw_rect(row, Color(GOLD.r, GOLD.g, GOLD.b, (0.9 if g[3] else 0.35) * ga), false, 2.0)
		_text(g[0], row.position + Vector2(18, 29), 22, Color(GOLD.r, GOLD.g, GOLD.b, ga), false)
		_text("+%d XP" % g[1], row.position + Vector2(250, 29), 20, Color(1, 1, 1, ga), false)
		_text(("LEVEL %d!" if g[3] else "Level %d") % g[2], row.position + Vector2(430, 29), 20, Color(0.5, 1.0, 0.6, ga) if g[3] else Color(1, 1, 1, ga * 0.7), false)
	if _result_age > 0.8:
		_text("TAP TO CONTINUE", Vector2(s.x * 0.5, s.y * 0.92), 30, Color(1, 1, 1, 0.6 + 0.4 * sin(_clock * 4.0)))
