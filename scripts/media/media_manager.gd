extends Node

## Media Manager - Handles portraits, backgrounds, music, and sound effects

signal portrait_loaded(character: String, texture: Texture2D)
signal background_loaded(location: String, texture: Texture2D)
signal music_changed(track_name: String)

# Caches
var portrait_cache: Dictionary = {}
var background_cache: Dictionary = {}
var audio_cache: Dictionary = {}

# Audio players
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var current_music_track: String = ""
var music_fade_tween: Tween

# Settings
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var enable_music: bool = true
var enable_sfx: bool = true

func _ready():
	# Create audio players
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "SFX"
	add_child(sfx_player)
	
	# Set initial volumes
	music_player.volume_db = linear_to_db(music_volume)
	sfx_player.volume_db = linear_to_db(sfx_volume)
	
	print("MediaManager initialized")

## Portrait Management

func load_portrait(character_id: String, generate_if_missing: bool = true) -> Texture2D:
	"""Load or generate a character portrait"""
	# Check cache first
	if portrait_cache.has(character_id):
		return portrait_cache[character_id]
	
	# Try to load from file
	var portrait_path = "res://assets/portraits/%s.png" % character_id.to_lower()
	if FileAccess.file_exists(portrait_path):
		var texture = load(portrait_path)
		if texture:
			portrait_cache[character_id] = texture
			portrait_loaded.emit(character_id, texture)
			return texture
	
	# Try user:// directory (for AI-generated images)
	var user_path = "user://portraits/%s.png" % character_id.to_lower()
	if FileAccess.file_exists(user_path):
		var image = Image.new()
		var error = image.load(user_path)
		if error == OK:
			var texture = ImageTexture.create_from_image(image)
			portrait_cache[character_id] = texture
			portrait_loaded.emit(character_id, texture)
			return texture
	
	# Generate with AI if requested
	if generate_if_missing:
		print("Portrait not found for ", character_id, " - requesting AI generation")
		await generate_portrait_ai(character_id)
		return await load_portrait(character_id, false)  # Retry after generation
	
	# Return placeholder
	return create_placeholder_portrait(character_id)

func generate_portrait_ai(character_id: String, description: String = ""):
	"""Request AI generation of character portrait"""
	if not description:
		description = "A mysterious character in a fantasy setting"
	
	var ai_client = get_node("/root/AIClient")
	if not ai_client:
		push_error("AIClient not found")
		return
	
	# Generate image
	var image_path = await ai_client.generate_character_portrait(character_id, description)
	
	if image_path:
		# Move to portraits directory
		DirAccess.make_dir_absolute("user://portraits")
		var dest_path = "user://portraits/%s.png" % character_id.to_lower()
		DirAccess.copy_absolute(image_path, dest_path)
		print("Portrait generated and saved: ", dest_path)

func create_placeholder_portrait(character_id: String) -> Texture2D:
	"""Create a simple placeholder portrait"""
	var image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.3, 0.4, 1.0))
	
	# Add a simple circle
	for y in range(256):
		for x in range(256):
			var dx = x - 128
			var dy = y - 128
			var dist = sqrt(dx*dx + dy*dy)
			if dist < 80:
				image.set_pixel(x, y, Color(0.5, 0.5, 0.6, 1.0))
	
	var texture = ImageTexture.create_from_image(image)
	portrait_cache[character_id] = texture
	return texture

## Background Management

func load_background(location_id: String, generate_if_missing: bool = true) -> Texture2D:
	"""Load or generate a location background"""
	# Check cache
	if background_cache.has(location_id):
		return background_cache[location_id]
	
	# Try to load from file
	var bg_path = "res://assets/backgrounds/%s.png" % location_id.to_lower()
	if FileAccess.file_exists(bg_path):
		var texture = load(bg_path)
		if texture:
			background_cache[location_id] = texture
			background_loaded.emit(location_id, texture)
			return texture
	
	# Try user:// directory
	var user_path = "user://backgrounds/%s.png" % location_id.to_lower()
	if FileAccess.file_exists(user_path):
		var image = Image.new()
		var error = image.load(user_path)
		if error == OK:
			var texture = ImageTexture.create_from_image(image)
			background_cache[location_id] = texture
			background_loaded.emit(location_id, texture)
			return texture
	
	# Generate with AI if requested
	if generate_if_missing:
		print("Background not found for ", location_id, " - requesting AI generation")
		await generate_background_ai(location_id)
		return await load_background(location_id, false)
	
	# Return placeholder
	return create_placeholder_background(location_id)

func generate_background_ai(location_id: String, description: String = ""):
	"""Request AI generation of location background"""
	if not description:
		description = "A mysterious location in a fantasy world"
	
	var ai_client = get_node("/root/AIClient")
	if not ai_client:
		push_error("AIClient not found")
		return
	
	var image_path = await ai_client.generate_location_image(location_id, description)
	
	if image_path:
		DirAccess.make_dir_absolute("user://backgrounds")
		var dest_path = "user://backgrounds/%s.png" % location_id.to_lower()
		DirAccess.copy_absolute(image_path, dest_path)
		print("Background generated and saved: ", dest_path)

func create_placeholder_background(location_id: String) -> Texture2D:
	"""Create a simple placeholder background"""
	var image = Image.create(1024, 576, false, Image.FORMAT_RGBA8)
	
	# Create a gradient
	for y in range(576):
		var color = Color(0.1, 0.1, 0.15, 1.0).lerp(Color(0.2, 0.15, 0.2, 1.0), float(y) / 576.0)
		for x in range(1024):
			image.set_pixel(x, y, color)
	
	var texture = ImageTexture.create_from_image(image)
	background_cache[location_id] = texture
	return texture

## Audio Management

func play_music(track_name: String, fade_time: float = 1.0):
	"""Play background music with optional crossfade"""
	if not enable_music:
		return
	
	if current_music_track == track_name and music_player.playing:
		return  # Already playing this track
	
	var track_path = find_music_file(track_name)
	if not track_path:
		push_warning("Music track not found: " + track_name)
		return
	
	var stream = load(track_path)
	if not stream:
		push_error("Failed to load music: " + track_path)
		return
	
	# Fade out current music
	if music_player.playing and fade_time > 0:
		if music_fade_tween:
			music_fade_tween.kill()
		music_fade_tween = create_tween()
		music_fade_tween.tween_property(music_player, "volume_db", -80, fade_time)
		await music_fade_tween.finished
	
	# Start new music
	music_player.stream = stream
	music_player.play()
	current_music_track = track_name
	
	# Fade in
	if fade_time > 0:
		music_player.volume_db = -80
		if music_fade_tween:
			music_fade_tween.kill()
		music_fade_tween = create_tween()
		music_fade_tween.tween_property(music_player, "volume_db", linear_to_db(music_volume), fade_time)
	else:
		music_player.volume_db = linear_to_db(music_volume)
	
	music_changed.emit(track_name)
	print("Playing music: ", track_name)

func stop_music(fade_time: float = 1.0):
	"""Stop music with optional fade out"""
	if not music_player.playing:
		return
	
	if fade_time > 0:
		if music_fade_tween:
			music_fade_tween.kill()
		music_fade_tween = create_tween()
		music_fade_tween.tween_property(music_player, "volume_db", -80, fade_time)
		await music_fade_tween.finished
	
	music_player.stop()
	current_music_track = ""

func play_sfx(sound_name: String):
	"""Play a sound effect"""
	if not enable_sfx:
		return
	
	var sound_path = find_sfx_file(sound_name)
	if not sound_path:
		push_warning("Sound effect not found: " + sound_name)
		return
	
	var stream = load(sound_path)
	if not stream:
		push_error("Failed to load sound: " + sound_path)
		return
	
	sfx_player.stream = stream
	sfx_player.play()

func find_music_file(track_name: String) -> String:
	"""Find music file by name"""
	var extensions = [".ogg", ".mp3", ".wav"]
	var base_path = "res://assets/audio/music/"
	
	for ext in extensions:
		var path = base_path + track_name + ext
		if FileAccess.file_exists(path):
			return path
	
	return ""

func find_sfx_file(sound_name: String) -> String:
	"""Find sound effect file by name"""
	var extensions = [".wav", ".ogg", ".mp3"]
	var base_path = "res://assets/audio/sfx/"
	
	for ext in extensions:
		var path = base_path + sound_name + ext
		if FileAccess.file_exists(path):
			return path
	
	return ""

func set_music_volume(volume: float):
	"""Set music volume (0.0 to 1.0)"""
	music_volume = clamp(volume, 0.0, 1.0)
	music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(volume: float):
	"""Set sound effects volume (0.0 to 1.0)"""
	sfx_volume = clamp(volume, 0.0, 1.0)
	sfx_player.volume_db = linear_to_db(sfx_volume)

func toggle_music(enabled: bool):
	"""Enable or disable music"""
	enable_music = enabled
	if not enabled and music_player.playing:
		stop_music(0.5)

func toggle_sfx(enabled: bool):
	"""Enable or disable sound effects"""
	enable_sfx = enabled
