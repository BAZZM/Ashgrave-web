class_name Sfx
extends Node

const NAMES := ["whoosh", "clang", "hit", "block", "hurt", "break", "finish", "tell"]
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

var ambience := true


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
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
