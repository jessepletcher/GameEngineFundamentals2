extends SceneTree
var checks := 0
var failures := 0
var manager: Node
var state: Node
var music_capture: AudioEffectCapture
var ambience_capture: AudioEffectCapture
var sfx_capture: AudioEffectCapture

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func capture_bus(name: String) -> AudioEffectCapture:
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, name)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(index, capture)
	return capture

func peak(capture: AudioEffectCapture) -> float:
	var samples := capture.get_buffer(capture.get_frames_available())
	var value := 0.0
	for sample in samples:
		value = maxf(value, maxf(absf(sample.x), absf(sample.y)))
	return value

func backgrounds(music: bool, ambience: bool, label: String) -> void:
	# Godot reports stream_paused=false when playback has never started. A
	# stopped configured player is also a valid silent startup state.
	check(manager.music_player.stream_paused == (manager.music_muted or manager._shop_open) or not manager.music_player.playing, label + " music pause state")
	check(manager.ambience_player.stream_paused == (manager.music_muted or manager._shop_open) or not manager.ambience_player.playing, label + " ambience pause state")
	await create_timer(0.15).timeout # allow in-flight mixer buffers to drain
	music_capture.clear_buffer()
	ambience_capture.clear_buffer()
	await create_timer(0.18).timeout
	var music_peak := peak(music_capture)
	var ambience_peak := peak(ambience_capture)
	print("PCM %s music=%s ambience=%s" % [label, music_peak, ambience_peak])
	check((music_peak > 0.00001) == music, "%s music PCM peak=%s" % [label, music_peak])
	check((ambience_peak > 0.00001) == ambience, "%s ambience PCM peak=%s" % [label, ambience_peak])

func tone(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var samples := int(seconds * 22050)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		data.encode_s16(i * 2, int(sin(float(i) * TAU * 440.0 / 22050.0) * 12000))
	stream.data = data
	return stream

func route_sfx() -> void:
	for player in manager._player_pool + manager._temp_players:
		player.bus = "TestSFX"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	manager = root.get_node("AudioManager")
	state = root.get_node("GameState")
	music_capture = capture_bus("TestMusic")
	ambience_capture = capture_bus("TestAmbience")
	sfx_capture = capture_bus("TestSFX")
	manager.music_player.bus = "TestMusic"
	manager.ambience_player.bus = "TestAmbience"
	route_sfx()
	var stream := tone(2.0)
	manager.set_music_muted(true)
	manager.play_music(stream)
	manager.play_ambience(stream, 0.5)
	await backgrounds(false, false, "muted startup")
	check(not manager.music_player.playing and not manager.ambience_player.playing, "muted startup defers playback")
	manager.set_music_muted(false)
	await backgrounds(true, true, "unmute starts configured streams")
	manager.set_music_muted(true)
	var before: float = manager.ambience_player.get_playback_position()
	await backgrounds(false, false, "mute stops audible output")
	await create_timer(0.3).timeout
	check(absf(manager.ambience_player.get_playback_position() - before) < 0.05, "muted ambience preserves playback position")
	manager.set_music_muted(false)
	await backgrounds(true, true, "resume muted playing streams")
	manager.set_shop_open(true)
	await backgrounds(false, false, "shop pauses background")
	manager.set_music_muted(true)
	manager.set_music_muted(false)
	await backgrounds(false, false, "unmute in shop cannot bypass shop pause")
	manager.set_music_muted(true)
	manager.set_shop_open(false)
	await backgrounds(false, false, "leaving shop respects mute")
	manager.set_music_muted(false)
	await backgrounds(true, true, "unmute after shop resumes")

	# Force the production playback-position trim boundary, not a fake timer.
	manager.ambience_player.seek(1.45)
	await create_timer(0.25).timeout
	check(manager.ambience_player.get_playback_position() < 0.5, "ambience loops at trimmed playback boundary")
	await backgrounds(true, true, "audio continues after ambience loop")
	manager.ambience_player.seek(1.3)
	manager.set_shop_open(true)
	before = manager.ambience_player.get_playback_position()
	await create_timer(0.5).timeout
	check(absf(manager.ambience_player.get_playback_position() - before) < 0.05, "shop does not advance restart clock")
	manager.set_shop_open(false)
	await create_timer(0.4).timeout
	check(manager.ambience_player.get_playback_position() < 0.5, "ambience loops after resumed playback reaches boundary")
	manager.play_ambience(tone(0.15), 20.0)
	await create_timer(0.6).timeout
	check(manager._ambience_loop_end > 0 and manager.ambience_player.playing, "short non-looping ambience restarts safely")
	await backgrounds(true, true, "natural finished restart")

	# Active pool/overflow SFX stop immediately; unmute only permits new effects.
	manager.set_music_muted(true)
	manager._sounds.hit = stream
	manager.set_sfx_muted(false)
	for i in 10:
		manager.play_sfx("hit")
	route_sfx()
	check(manager._temp_players.size() == 2, "SFX test exercises overflow players")
	sfx_capture.clear_buffer()
	await create_timer(0.2).timeout
	check(peak(sfx_capture) > 0.00001, "SFX emits PCM before mute")
	manager.set_sfx_muted(true)
	await create_timer(0.1).timeout
	sfx_capture.clear_buffer()
	manager.play_sfx("hit")
	await create_timer(0.2).timeout
	check(peak(sfx_capture) == 0 and manager._temp_players.is_empty(), "SFX mute stops and releases active overflow")
	for player in manager._player_pool:
		check(not player.playing, "SFX mute stops each pooled player")
	manager.set_sfx_muted(false)
	sfx_capture.clear_buffer()
	await create_timer(0.18).timeout
	check(peak(sfx_capture) == 0, "unmute does not replay old SFX")
	manager.play_sfx("hit")
	await create_timer(0.18).timeout
	check(peak(sfx_capture) > 0.00001, "new SFX works after unmute")
	AudioServer.set_bus_volume_db(0, -3.0)
	manager.set_shop_open(true)
	check(AudioServer.get_bus_volume_db(0) == -3.0, "shop ducking preserves master volume")
	check(is_equal_approx(manager._player_pool[0].volume_db, linear_to_db(manager.hit_volume) - 20.0), "shop ducks active SFX only")
	manager.set_shop_open(false)
	check(is_equal_approx(manager._player_pool[0].volume_db, linear_to_db(manager.hit_volume)), "shop exit restores SFX base volume")
	AudioServer.set_bus_volume_db(0, 0.0)
	manager.set_sfx_muted(true)

	# Actual scene and assets: saved mute, shop callbacks, reload while shop open.
	state.music_muted = true
	state.sfx_muted = true
	state.window_mode = "windowed"
	check(state.save(), "persist startup mute preferences")
	state.music_muted = false
	check(state.load_game() and state.music_muted, "reload saved mute preference")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	await backgrounds(false, false, "real scene respects saved mute")
	manager.set_music_muted(false)
	manager.music_player.seek(5.0)
	manager.ambience_player.seek(5.0)
	await backgrounds(true, true, "real game assets unmute")
	game._on_open_shop_pressed()
	await create_timer(0.5).timeout
	await backgrounds(false, false, "real shop entry")
	game._on_shop_close_requested()
	await create_timer(0.5).timeout
	await backgrounds(true, true, "real shop exit")
	game._on_open_shop_pressed()
	await create_timer(0.5).timeout
	game.free()
	await process_frame
	state.music_muted = false
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	check(not manager._shop_open and not manager._sfx_ducked, "scene reload clears stale shop pause/duck")
	await backgrounds(true, true, "real scene reload resumes existing streams")
	manager.ambience_player.seek(manager._ambience_loop_end - 0.1)
	await create_timer(1.0).timeout
	check(manager.ambience_player.get_playback_position() < 2.0, "real nature asset skips final 20 seconds: position=%s end=%s" % [manager.ambience_player.get_playback_position(), manager._ambience_loop_end])
	game.free()
	await process_frame
	manager.cleanup_audio()
	await backgrounds(false, false, "cleanup silences all background output")
	check(manager.music_player.stream == null and manager.ambience_player.stream == null, "cleanup releases streams")
	print("AUDIO_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
