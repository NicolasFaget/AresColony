extends Node
## Autoload « AudioManager » : effets sonores, vent et bande son.
##
## La bande son tourne en boucle ; un filtre la rend plus feutrée la nuit et pendant les tempêtes.

const SOUNDS := ["click", "tab", "fail", "upgrade", "milestone", "whoosh", "build", "alert",
		"landing", "evacuation"]
const SFX_VOICES := 10

## Bande son du jeu, jouée en boucle.
const MUSIC := "res://art/audio/music_red_horizon.mp3"
const MUSIC_VOLUME_DB := -6.0

## Ambiance selon l'état de la colonie : la musique est plus ou moins feutrée (filtre passe-bas, Hz).
const MOODS := {
	"day": 20000.0,
	"night": 5000.0,
	"storm": 2200.0,
}

var _streams := {}
var _sfx: Array[AudioStreamPlayer] = []
var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_filter: AudioEffectLowPassFilter
var _last_play := {}
var _mood := "day"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for sound_name in SOUNDS:
		_streams[sound_name] = load("res://art/audio/%s.wav" % sound_name)
	for i in SFX_VOICES:
		_sfx.append(_player("SFX"))
	var track: AudioStreamMP3 = load(MUSIC)
	track.loop = true
	_music = _player("Music")
	_music.stream = track
	_music.volume_db = MUSIC_VOLUME_DB
	_music.play()

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


## Change l'ambiance musicale : la bande son devient progressivement plus ou moins feutrée.
func set_mood(mood_id: String) -> void:
	if not MOODS.has(mood_id) or mood_id == _mood:
		return
	_mood = mood_id
	var tween := create_tween()
	tween.tween_property(_music_filter, "cutoff_hz", MOODS[mood_id], 4.0)


## Vent plus fort pendant les tempêtes.
func set_wind(strength: float) -> void:
	if _ambience != null:
		_ambience.volume_db = lerpf(-8.0, 4.0, clampf(strength, 0.0, 1.0))


## Active ou coupe musique, ambiance et effets selon les préférences du joueur.
func apply_settings() -> void:
	var settings: Dictionary = GameManager.settings
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not settings.music)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Ambience"), not settings.sound)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not settings.sound)


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
	_music_filter = AudioEffectLowPassFilter.new()
	_music_filter.cutoff_hz = MOODS["day"]
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
