extends Node
## Autoload « AudioManager » : effets sonores, ambiance des vagues et musique adaptative.
##
## La musique est jouée note par note par un petit séquenceur, avec trois instruments
## synthétisés (art/audio/music_*.wav, générés par tools/make_sounds.py) transposés à la volée.
## Chaque zone a son ambiance : tempo, tonalité, accords, densité de mélodie, filtre.
## Lumineuse le jour, feutrée la nuit, tendue pendant les tempêtes.

const SOUNDS := ["click", "tab", "fail", "upgrade", "milestone", "whoosh", "build", "alert",
		"landing", "evacuation"]
const SFX_VOICES := 10

## Instruments : fichier, note MIDI enregistrée, volume (dB), polyphonie.
const INSTRUMENTS := {
	"kalimba": ["music_kalimba", 72, -7.0, 6],
	"pad": ["music_pad", 48, -13.0, 6],
	"bass": ["music_bass", 36, -9.0, 2],
}

const MAJOR := [0, 4, 7]
const MINOR := [0, 3, 7]

## Ambiance musicale selon l'état de la colonie. key : tonique (0 = do), scale : gamme de la
## mélodie, chords : [degré, accord] sur deux mesures chacun, density : probabilité d'une note par croche.
const MOODS := {
	"day": { "bpm": 84.0, "key": 2, "scale": [0, 2, 4, 7, 9], "density": 0.42, "cutoff": 9000.0,
			"chords": [[0, MAJOR], [7, MAJOR], [9, MINOR], [5, MAJOR]] },
	"night": { "bpm": 66.0, "key": 9, "scale": [0, 3, 5, 7, 10], "density": 0.22, "cutoff": 3500.0,
			"chords": [[0, MINOR], [8, MAJOR], [3, MAJOR], [10, MAJOR]] },
	"storm": { "bpm": 76.0, "key": 1, "scale": [0, 1, 3, 7, 8], "density": 0.3, "cutoff": 2600.0,
			"chords": [[0, MINOR], [1, MAJOR], [0, MINOR], [10, MINOR]] },
}

## Croches par accord (deux mesures de 4 temps).
const STEPS_PER_CHORD := 16

var _streams := {}
var _sfx: Array[AudioStreamPlayer] = []
var _voices := {}
var _next_voice := {}
var _ambience: AudioStreamPlayer
var _music_filter: AudioEffectLowPassFilter
var _last_play := {}

var _mood: Dictionary = MOODS["day"]
var _pending_mood := ""
var _step := 0
var _step_timer := 0.0
var _melody_degree := 4
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_buses()
	for sound_name in SOUNDS:
		_streams[sound_name] = load("res://art/audio/%s.wav" % sound_name)
	for i in SFX_VOICES:
		_sfx.append(_player("SFX"))
	for instrument: String in INSTRUMENTS:
		var spec: Array = INSTRUMENTS[instrument]
		var stream: AudioStream = load("res://art/audio/%s.wav" % spec[0])
		var players: Array[AudioStreamPlayer] = []
		for i in spec[3]:
			var p := _player("Music")
			p.stream = stream
			p.volume_db = spec[2]
			players.append(p)
		_voices[instrument] = players
		_next_voice[instrument] = 0

	var wind: AudioStreamWAV = load("res://art/audio/ambience_wind.wav")
	wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind.loop_end = int(wind.get_length() * wind.mix_rate)
	_ambience = _player("Ambience")
	_ambience.stream = wind
	_ambience.volume_db = -6.0
	_ambience.play()
	apply_settings()


## Joue un effet. Le même effet ne se répète pas plus d'une fois tous les `min_interval` secondes.
func play(sound_name: String, volume_db := 0.0, pitch := 1.0, min_interval := 0.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if min_interval > 0.0 and now - _last_play.get(sound_name, -INF) < min_interval:
		return
	_last_play[sound_name] = now
	var player := _free_sfx_player()
	player.stream = _streams.get(sound_name)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Change l'ambiance musicale (au prochain accord, pour rester en mesure).
func set_mood(mood_id: String) -> void:
	if MOODS.has(mood_id) and MOODS[mood_id] != _mood:
		_pending_mood = mood_id


## Vent plus fort pendant les tempêtes.
func set_wind(strength: float) -> void:
	if _ambience != null:
		_ambience.volume_db = lerpf(-8.0, 4.0, clampf(strength, 0.0, 1.0))


## Active ou coupe musique, ambiance et effets selon les préférences du joueur.
func apply_settings() -> void:
	var state := GameManager.engine.state
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not state.music_enabled)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Ambience"), not state.sound_enabled)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not state.sound_enabled)


# ---------- Séquenceur ----------

func _process(delta: float) -> void:
	_step_timer -= delta
	while _step_timer <= 0.0:
		_play_step()
		_step_timer += 60.0 / _mood.bpm / 2.0


@warning_ignore("integer_division")
func _play_step() -> void:
	var in_chord := _step % STEPS_PER_CHORD
	if in_chord == 0:
		if not _pending_mood.is_empty():
			_apply_mood(_pending_mood)
		var chords: Array = _mood.chords
		var chord: Array = chords[(_step / STEPS_PER_CHORD) % chords.size()]
		var root: int = _wrap(_mood.key + chord[0])
		for interval: int in chord[1]:
			_note("pad", 48 + root + interval)
		_note("bass", 36 + root)
	elif in_chord == 8 and _mood.bpm >= 70.0:
		var chord: Array = _mood.chords[(_step / STEPS_PER_CHORD) % _mood.chords.size()]
		_note("bass", 36 + _wrap(_mood.key + chord[0]), -3.0)

	# Mélodie : marche aléatoire sur la gamme, plus dense sur les temps forts.
	var density: float = _mood.density * (1.3 if _step % 2 == 0 else 0.6)
	if _rng.randf() < density:
		_melody_degree = clampi(_melody_degree + _rng.randi_range(-2, 2), 0, 9)
		var scale: Array = _mood.scale
		var note: int = 72 + _mood.key + scale[_melody_degree % scale.size()] + 12 * (_melody_degree / scale.size()) - 12
		_note("kalimba", note, _rng.randf_range(-5.0, 0.0))
	_step += 1


func _note(instrument: String, midi_note: int, volume_offset := 0.0) -> void:
	var players: Array = _voices[instrument]
	var index: int = _next_voice[instrument]
	_next_voice[instrument] = (index + 1) % players.size()
	var player: AudioStreamPlayer = players[index]
	var spec: Array = INSTRUMENTS[instrument]
	player.pitch_scale = pow(2.0, (midi_note - spec[1]) / 12.0)
	player.volume_db = spec[2] + volume_offset
	player.play()


func _apply_mood(mood_id: String) -> void:
	_mood = MOODS[mood_id]
	_pending_mood = ""
	var tween := create_tween()
	tween.tween_property(_music_filter, "cutoff_hz", _mood.cutoff, 4.0)


## Ramène une hauteur relative dans [-5, 6] demi-tons : transpositions modérées, timbres naturels.
static func _wrap(semitones: int) -> int:
	var s := posmod(semitones, 12)
	return s - 12 if s > 6 else s


# ---------- Mixage ----------

func _setup_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")

	var music := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(music, -4.0)
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.75
	reverb.damping = 0.4
	reverb.wet = 0.35
	reverb.dry = 0.85
	AudioServer.add_bus_effect(music, reverb)
	_music_filter = AudioEffectLowPassFilter.new()
	_music_filter.cutoff_hz = MOODS["day"].cutoff
	AudioServer.add_bus_effect(music, _music_filter)

	var sfx := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(sfx, -5.0)
	# Plusieurs effets simultanés ne doivent jamais saturer.
	AudioServer.add_bus_effect(sfx, AudioEffectHardLimiter.new())
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), -10.0)


## À la fermeture : coupe les voix en cours et retire les bus ajoutés (et leurs effets).
func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	for bus_name in ["Ambience", "SFX", "Music"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index != -1:
			AudioServer.remove_bus(index)


func _player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _free_sfx_player() -> AudioStreamPlayer:
	for player in _sfx:
		if not player.playing:
			return player
	return _sfx[0]
