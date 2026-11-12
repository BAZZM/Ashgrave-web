class_name Sfx
extends Node

const Tune := preload("res://scripts/combat_tune.gd")

const NAMES := ["whoosh", "clang", "hit", "block", "hurt", "break", "finish", "tell"]
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

var ambience := true
var _layer_ms := {}


func _ready() -> void:
	for n in NAMES:
		for ext in ["ogg", "wav"]:
			var path := "res://audio/%s.%s" % [n, ext]
			if ResourceLoader.exists(path):
				_streams[n] = load(path)
				break

	if ambience and ResourceLoader.exists("res://audio/ambience.wav"):
		var amb: AudioStreamWAV = load("res://audio/ambience.wav").duplicate()
		amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
		amb.loop_end = int(amb.get_length() * amb.mix_rate)
		var ap := AudioStreamPlayer.new()
		ap.stream = amb
		ap.volume_db = -9.0
		add_child(ap)
		ap.play()
	for i in int(Tune.B1.sfx_pool):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## `pitch` is the base pitch (1.0 = the recording); `pitch_jitter` is added at random.
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.08, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch + randf_range(-pitch_jitter, pitch_jitter), 0.1)
	p.play()


## Play a stack of sounds (Tune.LAYERS). `pitch_mult` scales every part's pitch.
## A layer started less than `layer_gap_ms` ago is skipped, so a burst of events
## cannot pile the same crunch on itself.
func layer(layer_name: String, pitch_mult := 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_layer_ms.get(layer_name, -1000)) < int(Tune.B1.layer_gap_ms):
		return
	_layer_ms[layer_name] = now
	for part in Tune.LAYERS[layer_name]:
		var pitch: float = part[2] * pitch_mult if Tune.B1.pitch_layers else 1.0
		if float(part[3]) <= 0.0:
			play(part[0], part[1], part[4], pitch)
		else:
			get_tree().create_timer(part[3], true, false, true).timeout.connect(play.bind(part[0], part[1], part[4], pitch))
