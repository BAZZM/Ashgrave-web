extends Node
## Shared-world presence and player-to-player messages.
##
## Speaks just enough MQTT 3.1.1 over WebSocket to use free public brokers as
## relays. Every relay is joined at once and whatever arrives is merged, so two
## players meet as long as both can reach any one relay in common. (Joining a
## single relay and falling back to the next on failure splits players across
## relays that know nothing of each other.)
##
## Topics:  <WORLD>/p/<id>  a player's state, published a few times a second
##          <WORLD>/c/<id>  messages addressed to one player

signal message(from_id: String, data: Dictionary)

const WORLD := "ashgrave/w1"
const RELAYS := ["wss://broker.emqx.io:8084/mqtt", "wss://broker.hivemq.com:8884/mqtt", "wss://test.mosquitto.org:8081/mqtt"]
## A player unheard for this long is dropped.
const STALE_MS := 9000
const CONNECT_TIMEOUT_MS := 8000
const RETRY_MIN_MS := 3000
const RETRY_MAX_MS := 20000
const PING_MS := 20000
## How long a direct message's id is remembered, to drop the copies that
## arrive through the other relays.
const SEEN_MS := 30000
## A state this many steps or fewer behind the newest one held is a late copy
## from a slower relay. Further behind than that means the sender restarted.
const LATE_STEPS := 40

enum { IDLE, OPENING, HELLO, LIVE }

var enabled := true
## True while at least one relay is live.
var connected := false
## The relay shown to the player: a live one, else the first being tried.
var relay := ""
var my_id := ""
var my_name := ""

## id -> last state heard, plus `seen` (local ticks in ms).
var players := {}

var _links: Array[Link] = []
var _override := ""
var _seq := 0
var _sent := 0
var _session := ""
var _seen := {}


class Link:
	var url := ""
	var ws: WebSocketPeer
	var buf := PackedByteArray()
	var state := IDLE
	var retry_at := 0
	var wait := RETRY_MIN_MS
	var opened_at := 0
	var pinged_at := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relay="):
			_override = a.trim_prefix("--relay=")
		elif a == "--offline":
			enabled = false
	if OS.has_feature("web"):
		# ?relay=wss://host:port/mqtt (comma-separated for several) replaces the built-in list.
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('relay') || ''", true)
		if q is String and q != "":
			_override = q


func start() -> void:
	if my_id != "":
		return
	Run.ensure_loaded()
	if String(Run.data.get("pid", "")) == "":
		Run.data.pid = "%08x" % (randi() & 2147483647)
		Run.data.pname = "Wanderer-%s" % String(Run.data.pid).right(3)
	my_id = Run.data.pid
	my_name = Run.data.pname
	_session = "%08x" % (randi() & 2147483647)
	enabled = enabled and Run.data.get("online", true)
	var urls: Array = RELAYS
	if _override != "":
		urls = Array(_override.split(",", false))
	for url in urls:
		var link := Link.new()
		link.url = String(url).strip_edges()
		_links.append(link)
	relay = _links[0].url


func set_enabled(on: bool) -> void:
	enabled = on
	Run.data.online = on
	Run.save()
	if not on:
		for link in _links:
			_drop(link)
			link.retry_at = 0
			link.wait = RETRY_MIN_MS
		connected = false
		players.clear()


func rename(text: String) -> void:
	text = text.strip_edges().left(16)
	if text == "":
		return
	my_name = text
	Run.data.pname = text
	Run.save()


func publish_state(state: Dictionary) -> void:
	state.n = my_name
	_seq += 1
	state.q = _seq
	_publish(WORLD + "/p/" + my_id, state)


func send_to(id: String, data: Dictionary) -> void:
	data.from = my_id
	data.n = my_name
	_sent += 1
	data.mid = "%s-%d" % [_session, _sent]
	_publish(WORLD + "/c/" + id, data)


func count() -> int:
	return players.size()


func _process(_delta: float) -> void:
	if not enabled or my_id == "":
		return
	# Wall-clock time throughout: frame delta slows with Engine.time_scale and
	# at very low frame rates, and the relays do not.
	var now := Time.get_ticks_msec()
	var live := ""
	for link in _links:
		_tick(link, now)
		if link.state == LIVE and live == "":
			live = link.url
	connected = live != ""
	relay = live if connected else _links[0].url
	for id in players.keys():
		if now - int(players[id].seen) > STALE_MS:
			players.erase(id)
	for key in _seen.keys():
		if now - int(_seen[key]) > SEEN_MS:
			_seen.erase(key)


func _tick(link: Link, now: int) -> void:
	if link.state == IDLE:
		if now >= link.retry_at:
			_open(link, now)
		return
	link.ws.poll()
	var st := link.ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if link.state == OPENING:
			link.state = HELLO
			_send_connect(link)
		while link.ws.get_available_packet_count() > 0:
			link.buf.append_array(link.ws.get_packet())
		_parse(link, now)
		if link.state == LIVE and now - link.pinged_at > PING_MS:
			link.pinged_at = now
			link.ws.send(PackedByteArray([192, 0]))
	elif st == WebSocketPeer.STATE_CLOSED:
		_fail(link, now)
		return
	if link.state in [OPENING, HELLO] and now - link.opened_at > CONNECT_TIMEOUT_MS:
		_fail(link, now)


func _open(link: Link, now: int) -> void:
	link.ws = WebSocketPeer.new()
	link.ws.supported_protocols = PackedStringArray(["mqtt"])
	link.buf = PackedByteArray()
	link.opened_at = now
	if link.ws.connect_to_url(link.url) != OK:
		_fail(link, now)
		return
	link.state = OPENING


func _drop(link: Link) -> void:
	if link.ws:
		link.ws.close()
	link.ws = null
	link.state = IDLE


## Drop the link and try the same relay again later, backing off each time.
func _fail(link: Link, now: int) -> void:
	_drop(link)
	link.retry_at = now + link.wait
	link.wait = mini(link.wait * 2, RETRY_MAX_MS)


static func _str(text: String) -> PackedByteArray:
	var b := text.to_utf8_buffer()
	var out := PackedByteArray([b.size() >> 8, b.size() & 255])
	out.append_array(b)
	return out


## One MQTT packet: fixed header byte, variable-length size, body.
static func _packet(head: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([head])
	var n := body.size()
	while true:
		var digit := n % 128
		n = n / 128
		out.append(digit | (128 if n > 0 else 0))
		if n == 0:
			break
	out.append_array(body)
	return out


func _send_connect(link: Link) -> void:
	var body := _str("MQTT")
	# Protocol level 4, clean session, 30 s keep-alive.
	body.append_array(PackedByteArray([4, 2, 0, 30]))
	body.append_array(_str("ashgrave_" + my_id + "_%d" % (randi() % 10000)))
	link.ws.send(_packet(16, body))


func _subscribe(link: Link, topic: String, pid: int) -> void:
	var body := PackedByteArray([pid >> 8, pid & 255])
	body.append_array(_str(topic))
	body.append(0)
	link.ws.send(_packet(130, body))


func _publish(topic: String, data: Dictionary) -> void:
	var body := _str(topic)
	body.append_array(JSON.stringify(data).to_utf8_buffer())
	var packet := _packet(48, body)
	for link in _links:
		if link.state == LIVE:
			link.ws.send(packet)


func _parse(link: Link, now: int) -> void:
	while link.buf.size() >= 2:
		var kind := link.buf[0] >> 4
		var length := 0
		var mult := 1
		var i := 1
		var complete := false
		while i < link.buf.size() and i < 5:
			length += (link.buf[i] & 127) * mult
			mult *= 128
			i += 1
			if link.buf[i - 1] & 128 == 0:
				complete = true
				break
		if not complete or link.buf.size() < i + length:
			return
		var body := link.buf.slice(i, i + length)
		link.buf = link.buf.slice(i + length)
		match kind:
			2:
				# CONNACK
				if body.size() >= 2 and body[1] == 0:
					link.state = LIVE
					link.wait = RETRY_MIN_MS
					link.pinged_at = now
					_subscribe(link, WORLD + "/p/+", 1)
					_subscribe(link, WORLD + "/c/" + my_id, 2)
				else:
					_fail(link, now)
					return
			3:
				# PUBLISH (QoS 0)
				if body.size() < 2:
					continue
				var tl := (body[0] << 8) | body[1]
				var topic := body.slice(2, 2 + tl).get_string_from_utf8()
				var parsed: Variant = JSON.parse_string(body.slice(2 + tl).get_string_from_utf8())
				if parsed is Dictionary:
					_incoming(topic, parsed, now)


func _incoming(topic: String, data: Dictionary, now: int) -> void:
	var parts := topic.split("/")
	if parts.size() < 4:
		return
	if parts[2] == "p":
		var id := parts[3]
		if id == my_id:
			return
		if players.has(id) and data.has("q") and players[id].has("q"):
			var behind := int(players[id].q) - int(data.q)
			if behind >= 0 and behind <= LATE_STEPS:
				players[id].seen = now
				return
		data.seen = now
		players[id] = data
	elif parts[2] == "c" and parts[3] == my_id:
		var from := String(data.get("from", ""))
		if from == "" or from == my_id:
			return
		if data.has("mid"):
			var key := from + "/" + str(data.mid)
			if _seen.has(key):
				return
			_seen[key] = now
		message.emit(from, data)
