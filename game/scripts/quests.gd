class_name Quests
extends RefCounted

## Quests as data. The tables live in quest_data_core.gd (the five that shipped first) and
## quest_data_act1.gd (Act 1, pasted from docs/story/ACT1.md); the schema is docs/STORY_BIBLE.md
## section 9. This file only runs them. A quest's save entry stays {step, count, done}.

const CoreData := preload("res://scripts/quest_data_core.gd")
const Act1Data := preload("res://scripts/quest_data_act1.gd")

const NPCS := {
	"smith": "Brannoc the Smith", "elder": "Elder Maren", "alchemist": "Sister Wren",
	"fisher": "Old Tam", "ranger": "Warden Isolde", "villager": "Villager",
}

const ACT_NAMES := {1: "The Thirty-First", 2: "Send No One", 3: "A Keeper"}

static var QUESTS: Dictionary = _build()
static var _sorted: Array = []
## Bumped whenever quest state changes; the HUD rebuilds its cached journal and tracker text on it.
static var rev := 0

const SMALL_TALK := [
	"The tower was quieter when I was young. Or I was.",
	"Tam at the lake says the pike are biting.",
	"Brannoc will forge anything if you bring the ore.",
	"Do not go into Mirefen without a flask or two.",
	"They say the stones east of the bridge hum at night.",
]


static func _build() -> Dictionary:
	var all := {}
	all.merge(CoreData.QUESTS)
	all.merge(Act1Data.QUESTS)
	return all


## Quest ids in play order (the `order` field, default 100).
static func ids() -> Array:
	if _sorted.is_empty():
		_sorted = QUESTS.keys()
		_sorted.sort_custom(func(a, b): return int(QUESTS[a].get("order", 100)) < int(QUESTS[b].get("order", 100)))
	return _sorted


static func touch() -> void:
	rev += 1


# ---------------------------------------------------------------- conditions and variants

static func _cmp(a: int, op: String, b: int) -> bool:
	match op:
		">=": return a >= b
		"<=": return a <= b
		">": return a > b
		"<": return a < b
	return a == b


## "name OP n" with OP one of >= <= > < =; returns [name, op, n] or an empty array.
static func _split_cmp(s: String) -> Array:
	for op in [">=", "<=", ">", "<", "="]:
		var at := s.find(op)
		if at > 0:
			return [s.substr(0, at), op, int(s.substr(at + op.length()))]
	return []


## One condition from the schema: quest:id (done), active:id, flag:id=value, relic:N, tier:N (beaten),
## loop>=N, bloodline>=N, skill:id>=N, item:id, mat:id[>=N]; a leading ! negates.
static func cond(c: String) -> bool:
	if c.begins_with("!"):
		return not cond(c.substr(1))
	var d: Dictionary = Run.data
	if not c.contains(":"):
		var p := _split_cmp(c)
		if p.is_empty():
			return false
		return _cmp(int(d.get(p[0], 0)), p[1], p[2])
	var kind := c.get_slice(":", 0)
	var rest := c.substr(kind.length() + 1)
	match kind:
		"quest": return d.quests.has(rest) and bool(d.quests[rest].get("done", false))
		"active": return active(rest)
		"flag":
			var kv := rest.split("=", true, 1)
			return str(d.flags.get(kv[0], "")) == (kv[1] if kv.size() > 1 else "")
		"relic": return d.relics.has(int(rest)) or d.relics.has(float(int(rest)))
		"tier": return int(d.best_floor) > int(rest)
		"item": return d.inventory.has(rest)
		"skill":
			var s := _split_cmp(rest)
			return not s.is_empty() and _cmp(Run.skill(s[0]), s[1], s[2])
		"mat":
			var m := _split_cmp(rest)
			if m.is_empty():
				return Run.mat(rest) >= 1
			return _cmp(Run.mat(m[0]), m[1], m[2])
	return false


## A line, a list of lines or a variant {"if": [[condition, value], ...], "else": value}, as a flat
## list of non-empty strings. The first matching condition wins.
static func lines(v: Variant) -> Array:
	var out: Array = []
	if v is String:
		if v != "":
			out.append(v)
	elif v is Array:
		for x in v:
			out.append_array(lines(x))
	elif v is Dictionary:
		for pair in v.get("if", []):
			if cond(pair[0]):
				return lines(pair[1])
		return lines(v.get("else", ""))
	return out


static func requires_met(q: Dictionary) -> bool:
	for c in q.get("requires", []):
		if not cond(c):
			return false
	return true


# ---------------------------------------------------------------- state

static func state(id: String) -> Dictionary:
	return Run.data.quests.get(id, {})


static func started(id: String) -> bool:
	return Run.data.quests.has(id)


static func active(id: String) -> bool:
	return Run.data.quests.has(id) and not state(id).get("done", false)


static func step(id: String) -> Dictionary:
	var steps: Array = QUESTS[id].steps
	return steps[clampi(int(state(id).get("step", 0)), 0, steps.size() - 1)]


## Not started, open to start (its conditions hold) and offered by an NPC rather than starting itself.
static func offerable(id: String) -> bool:
	var q: Dictionary = QUESTS[id]
	return not started(id) and not q.get("auto", false) and requires_met(q)


static func progress(id: String) -> String:
	if state(id).get("done", false):
		return "Complete"
	var st := step(id)
	var text: String = st.text
	if st.do == "kill":
		text += "  (%d of %d)" % [int(state(id).get("count", 0)), st.need]
	return text


## The tracker line: quest name and the step's `track` text (the full text where a step has none).
static func track_text(id: String) -> String:
	var st := step(id)
	var t: String = st.get("track", st.text)
	if st.do == "kill" and int(st.need) > 1:
		t += " (%d of %d)" % [int(state(id).get("count", 0)), st.need]
	return "%s: %s" % [QUESTS[id].name, t]


## The journal text for a finished quest: its closing entry, or its first closing line.
static func journal_text(id: String) -> String:
	var q: Dictionary = QUESTS[id]
	if q.has("journal"):
		return q.journal
	var f := lines(q.get("finish", []))
	return f[0] if not f.is_empty() else "Complete"


static func marker(npc: String) -> String:
	for id in ids():
		var q: Dictionary = QUESTS[id]
		if not started(id):
			if q.giver == npc and offerable(id):
				return "!"
		elif active(id) and step(id).get("to", "") == npc:
			return "!"
	return ""


static func _has_mats(mats: Dictionary) -> bool:
	for m in mats:
		if Run.mat(m) < int(mats[m]):
			return false
	return true


static func _state_ok(st: Dictionary) -> bool:
	match st.do:
		"find": return cond("relic:%d" % int(st.relic))
		"win": return cond("tier:%d" % int(st.tier))
	return false


static func _begin(id: String) -> void:
	Run.data.quests[id] = {"step": 0, "count": 0, "done": false}
	Run.captions.append("Quest started: %s." % QUESTS[id].name)
	touch()
	Run.save()


## Steps that are state checks (find a relic, beat a tier) pass at once if the save already says so,
## and quests that start themselves start when their conditions hold. Safe to call at any time.
static func sync() -> void:
	for id in ids():
		var q: Dictionary = QUESTS[id]
		if q.get("auto", false) and not started(id) and requires_met(q):
			_begin(id)
			Run.captions.append("%s: %s" % [q.name, step(id).text])
		if active(id) and step(id).do in ["find", "win"] and _state_ok(step(id)):
			for line in _advance(id):
				Run.captions.append(line)
			if active(id):
				Run.captions.append("%s: %s" % [q.name, step(id).text])


## Finish the current step. Returns what is said: the step's `say` lines (for a choice, the `reply` to it),
## then, if that was the last step, the quest's closing lines.
static func _advance(id: String, choice := "") -> Array:
	var st := step(id)
	var said: Array
	if st.do == "choose":
		said = lines(st.get("reply", {}).get(choice, []))
	else:
		said = lines(st.get("say", []))
	var qs := state(id)
	qs.step = int(qs.step) + 1
	qs.count = 0
	touch()
	if int(qs.step) >= QUESTS[id].steps.size():
		return said + _complete(id)
	Run.save()
	if step(id).do in ["find", "win"] and _state_ok(step(id)):
		said.append_array(_advance(id))
	return said


static func _complete(id: String) -> Array:
	var q: Dictionary = QUESTS[id]
	state(id).done = true
	var r: Dictionary = q.reward
	var got: Array = []
	if r.has("gold"):
		Run.data.gold += int(r.gold)
		got.append("%d gold" % r.gold)
	for sk in r.get("xp", {}):
		Run.train(sk, int(r.xp[sk]))
	if r.has("item"):
		Run.add_item(r.item)
		got.append(Items.info(r.item).name)
	if r.has("tools"):
		Run.data.tools.axe = maxi(int(Run.data.tools.axe), int(r.tools))
		Run.data.tools.pick = maxi(int(Run.data.tools.pick), int(r.tools))
		got.append("copper axe and pick")
	for m in r.get("mats", {}):
		Run.add_mat(m, int(r.mats[m]))
		got.append("%d %s" % [int(r.mats[m]), str(Craft.MATS[m].name).to_lower()])
	for lid in r.get("lore", []):
		if Story.found(lid):
			got.append(Story.lore_entry(lid).name)
	for k in r.get("flags", {}):
		Run.data.flags[k] = r.flags[k]
	Run.captions.append("Quest complete: %s.%s" % [q.name, ("  Received " + ", ".join(got) + ".") if not got.is_empty() else ""])
	touch()
	Run.save()
	var out := lines(q.finish)
	sync()
	return out


static func talk(npc: String) -> Dictionary:
	sync()
	var out := {"name": NPCS.get(npc, npc), "lines": [], "choices": []}
	# 1. An active step addressed to this NPC comes before any new offer.
	var reminder: Array = []
	for id in ids():
		if not active(id):
			continue
		var st := step(id)
		if st.get("to", "") != npc:
			continue
		match st.do:
			"bring":
				if _has_mats(st.mats):
					for m in st.mats:
						Run.add_mat(m, -int(st.mats[m]))
					out.lines = _advance(id)
					return out
				if reminder.is_empty():
					reminder = [st.text]
			"talk":
				out.lines = _advance(id)
				return out
			"choose":
				out.lines = lines(st.say)
				for c in st.choices:
					out.choices.append([c[0], "choose:%s:%s" % [id, c[1]]])
				return out
	if not reminder.is_empty():
		out.lines = reminder
		return out
	# 2. New offers from this giver, in `order`.
	for id in ids():
		var q: Dictionary = QUESTS[id]
		if q.giver == npc and offerable(id):
			out.lines = lines(q.offer)
			out.choices = [[q.get("accept", "I will do it."), "accept:" + id], [q.get("decline", "Not now."), "bye"]]
			return out
	# 3. A quest this NPC gave and the player is still working on.
	for id in ids():
		if active(id) and QUESTS[id].giver == npc:
			out.lines = [progress(id)]
			return out
	# 4. Nothing asked: an idle line from data, then the villagers' small talk.
	out.lines = lines(Act1Data.IDLE.get(npc, ""))
	if out.lines.is_empty() and npc == "villager":
		out.lines = [SMALL_TALK[randi() % SMALL_TALK.size()]]
	return out


static func act(action: String) -> Array:
	var parts := action.split(":")
	match parts[0]:
		"accept":
			_begin(parts[1])
			var first: Array = [step(parts[1]).text]
			if step(parts[1]).do in ["find", "win"] and _state_ok(step(parts[1])):
				first.append_array(_advance(parts[1]))
			return first
		"choose":
			var id := parts[1]
			Run.data.flags[id] = parts[2]
			match action:
				"choose:poach:tally":
					Run.add_item("hunters_bow")
					Run.add_mat("arrow", 30)
					Run.captions.append("Isolde gives you a Hunter's Bow and 30 arrows.")
				"choose:poach:bribe":
					Run.data.gold += 300
					Run.captions.append("You keep the poachers' 300 gold. Isolde says nothing.")
			return _advance(id, parts[2])
	return []


static func on_kill(foe: String) -> void:
	for id in ids():
		if active(id) and step(id).do == "kill" and foe in step(id).foes:
			state(id).count = int(state(id).get("count", 0)) + 1
			touch()
			if int(state(id).count) >= int(step(id).need):
				for line in _advance(id):
					Run.captions.append(line)
				if active(id):
					Run.captions.append("%s: %s" % [QUESTS[id].name, step(id).text])
	sync()


static func on_reach(place: String) -> void:
	for id in ids():
		if active(id) and step(id).do == "reach" and step(id).place == place:
			for line in _advance(id):
				Run.captions.append(line)
			if active(id):
				Run.captions.append("%s: %s" % [QUESTS[id].name, step(id).text])
	sync()
