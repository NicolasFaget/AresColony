extends Node
## Autoload « AudioManager » : effets sonores, vent et bande son.
##
## Les morceaux de la bande son s'enchaînent ; un filtre la rend plus feutrée la nuit et pendant les tempêtes.

const SOUNDS := ["click", "tab", "fail", "upgrade", "milestone", "whoosh", "build", "alert",
		"landing", "evacuation",
		# Événements naturels et dangers.
		"quake", "eclipse", "geyser", "rain", "frost", "dune", "aurora",
		"storm", "flare", "meteor", "breakdown", "dilemma",
		# Récompenses et actions du joueur.
		"objective", "era", "discovery", "quiz_right", "quiz_wrong", "research_done", "challenge",
		"repair", "clean", "rover", "rover_back", "launch", "recruit"]
## Ambiances en boucle : vent de Mars, vent épais de Titan, ronron de la base (mondes sans air).
const AMBIENCES := ["wind", "titan", "base"]
const BASE_HUM_DB := -6.0
const SFX_VOICES := 10

## Bande son du jeu : les morceaux s'enchaînent dans un ordre tiré au hasard, sans redite immédiate.
const MUSIC := ["red_horizon", "the_red_horizon", "first_dome_at_dawn", "apex_of_discovery"]
## Silence entre deux morceaux (secondes).
const MUSIC_GAP := 3.0
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
var _ambiences := {}
var _ambience_id := "wind"
var _music: AudioStreamPlayer
var _playlist: Array = []
var _track := ""
var _music_filter: AudioEffectLowPassFilter
var _last_play := {}
var _mood := "day"
## Cérès n'a pas d'air : pas de vent, on entend la base. Titan : un vent grave, sourd, dans l'air épais.
var _airless := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for sound_name in SOUNDS:
		_streams[sound_name] = load("res://art/audio/%s.wav" % sound_name)
	for i in SFX_VOICES:
		_sfx.append(_player("SFX"))
	_music = _player("Music")
	_music.volume_db = MUSIC_VOLUME_DB
	_music.finished.connect(func() -> void: get_tree().create_timer(MUSIC_GAP).timeout.connect(_next_track))
	_next_track()

	for id: String in AMBIENCES:
		var loop: AudioStreamWAV = load("res://art/audio/ambience_%s.wav" % id)
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_end = int(loop.get_length() * loop.mix_rate)
		_ambiences[id] = loop
	_ambience = _player("Ambience")
	_ambience.stream = _ambiences["wind"]
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


## Lance le morceau suivant. La liste est mélangée à chaque tour, sans rejouer le dernier entendu.
func _next_track() -> void:
	if _playlist.is_empty():
		_playlist = MUSIC.duplicate()
		_playlist.shuffle()
		if _playlist.size() > 1 and _playlist[0] == _track:
			_playlist.push_back(_playlist.pop_front())
	_track = _playlist.pop_front()
	var stream: AudioStreamMP3 = load("res://art/audio/music_%s.mp3" % _track)
	stream.loop = false
	_music.stream = stream
	_music.play()


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
		_ambience.volume_db = BASE_HUM_DB if _airless else lerpf(-8.0, 4.0, clampf(strength, 0.0, 1.0))


## Ambiance du monde affiché : air (vent) ou vide, timbre du vent.
func set_world(planet: String) -> void:
	_airless = not ColonyContent.PLANETS[planet].atmosphere
	var id := "base" if _airless else ("titan" if planet == "titan" else "wind")
	if _ambience != null and id != _ambience_id:
		_ambience_id = id
		_ambience.stream = _ambiences[id]
		_ambience.play()
	set_wind(0.0)


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
