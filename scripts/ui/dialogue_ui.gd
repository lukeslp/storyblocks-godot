extends Control

## Enhanced Dialogue UI with portraits, backgrounds, and AI integration

@onready var background_image = $BackgroundLayer/BackgroundImage
@onready var portrait_container = $PortraitLayer/PortraitContainer
@onready var portrait_image = $PortraitLayer/PortraitContainer/PortraitImage
@onready var dialogue_panel = $DialogueLayer/DialoguePanel
@onready var speaker_label = $DialogueLayer/DialoguePanel/MarginContainer/VBoxContainer/SpeakerLabel
@onready var dialogue_label = $DialogueLayer/DialoguePanel/MarginContainer/VBoxContainer/DialogueLabel
@onready var choices_container = $DialogueLayer/DialoguePanel/MarginContainer/VBoxContainer/ChoicesContainer
@onready var stats_panel = $UILayer/StatsPanel
@onready var stats_label = $UILayer/StatsPanel/StatsLabel

# Theme toggle
var dark_mode: bool = true

# Animation
var text_reveal_speed: float = 0.03
var current_text: String = ""
var revealed_chars: int = 0
var text_timer: float = 0.0

func _ready():
	# Connect to game manager
	var game_manager = get_node("/root/GameManager")
	game_manager.story_loaded.connect(_on_story_loaded)
	game_manager.node_changed.connect(_on_node_changed)
	game_manager.state_changed.connect(_on_state_changed)
	
	# Connect to media manager
	var media_manager = get_node("/root/MediaManager")
	media_manager.portrait_loaded.connect(_on_portrait_loaded)
	media_manager.background_loaded.connect(_on_background_loaded)
	
	# Load story
	game_manager.load_story("res://stories/demo.json")
	
	# Apply initial theme
	apply_theme()

func _process(delta):
	# Animate text reveal
	if revealed_chars < current_text.length():
		text_timer += delta
		if text_timer >= text_reveal_speed:
			text_timer = 0.0
			revealed_chars += 1
			dialogue_label.visible_ratio = float(revealed_chars) / float(current_text.length())

func _on_story_loaded(story_data: Dictionary):
	print("Story loaded in UI: ", story_data.get("title", "Unknown"))
	
	# Start background music if available
	var media_manager = get_node("/root/MediaManager")
	media_manager.play_music("ambient", 2.0)

func _on_node_changed(node_id: String, node_data: Dictionary):
	"""Update UI when story node changes"""
	display_node(node_data)

func _on_state_changed(game_state: Dictionary):
	"""Update stats display"""
	update_stats_display(game_state)

func display_node(node: Dictionary):
	"""Display a story node"""
	# Clear previous choices
	for child in choices_container.get_children():
		child.queue_free()
	
	# Update speaker
	var speaker = node.get("speaker", "NARRATOR")
	speaker_label.text = speaker
	
	# Update dialogue text with animation
	current_text = node.get("text", "")
	revealed_chars = 0
	dialogue_label.text = current_text
	dialogue_label.visible_ratio = 0.0
	
	# Load portrait if character is speaking
	if speaker != "NARRATOR":
		var media_manager = get_node("/root/MediaManager")
		var portrait = await media_manager.load_portrait(speaker.to_lower())
		if portrait:
			portrait_image.texture = portrait
			portrait_container.visible = true
	else:
		portrait_container.visible = false
	
	# Load background based on node title/location
	var location = extract_location(node)
	if location:
		var media_manager = get_node("/root/MediaManager")
		var background = await media_manager.load_background(location)
		if background:
			background_image.texture = background
	
	# Create choice buttons
	var choices = node.get("choices", [])
	for i in range(choices.size()):
		var choice = choices[i]
		create_choice_button(i, choice)

func create_choice_button(index: int, choice: Dictionary):
	"""Create a choice button"""
	var button = Button.new()
	button.text = choice.get("text", "Continue")
	button.pressed.connect(_on_choice_selected.bind(index))
	
	# Style the button
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size = Vector2(0, 40)
	
	# Add skill check indicator
	var skill_check = choice.get("skill_check", {})
	if not skill_check.is_empty():
		var skill = skill_check.get("skill", "")
		var difficulty = skill_check.get("difficulty", 0)
		button.text = "[%s %d] %s" % [skill.to_upper(), difficulty, button.text]
		button.modulate = Color(0.9, 0.8, 0.5)  # Highlight skill checks
	
	# Check if choice is available
	var condition = choice.get("condition", null)
	if condition:
		var game_manager = get_node("/root/GameManager")
		var story_importer = game_manager.story_importer
		var game_state = game_manager.get_game_state()
		
		if not story_importer.check_condition(condition, game_state):
			button.disabled = true
			button.text += " (Locked)"
			button.modulate = Color(0.5, 0.5, 0.5)
	
	choices_container.add_child(button)

func _on_choice_selected(choice_index: int):
	"""Handle choice selection"""
	# Play sound effect
	var media_manager = get_node("/root/MediaManager")
	media_manager.play_sfx("click")
	
	# Select choice in game manager
	var game_manager = get_node("/root/GameManager")
	game_manager.select_choice(choice_index)

func extract_location(node: Dictionary) -> String:
	"""Extract location identifier from node"""
	var title = node.get("title", "").to_lower()
	
	# Common location keywords
	var locations = ["forest", "tavern", "castle", "dungeon", "village", "cave", "temple", "river", "mountain"]
	
	for location in locations:
		if title.contains(location):
			return location
	
	return ""

func update_stats_display(game_state: Dictionary):
	"""Update the stats panel"""
	var stats = game_state.get("stats", {})
	var inventory = game_state.get("inventory", [])
	
	var text = "=== CHARACTER ===\n"
	
	# Display stats
	for stat in stats:
		text += "%s: %d\n" % [stat.capitalize(), stats[stat]]
	
	# Display inventory
	if inventory.size() > 0:
		text += "\n=== INVENTORY ===\n"
		for item in inventory:
			text += "• %s\n" % item.capitalize()
	
	stats_label.text = text

func _on_portrait_loaded(character: String, texture: Texture2D):
	"""Handle portrait loaded event"""
	print("Portrait loaded for: ", character)

func _on_background_loaded(location: String, texture: Texture2D):
	"""Handle background loaded event"""
	print("Background loaded for: ", location)

func toggle_theme():
	"""Toggle between light and dark mode (Swedish style)"""
	dark_mode = not dark_mode
	apply_theme()

func apply_theme():
	"""Apply current theme"""
	if dark_mode:
		# Dark theme
		background_image.modulate = Color(0.8, 0.8, 0.8)
		dialogue_panel.modulate = Color(1.0, 1.0, 1.0)
	else:
		# Light theme
		background_image.modulate = Color(1.0, 1.0, 1.0)
		dialogue_panel.modulate = Color(0.95, 0.95, 0.95)

func _input(event):
	"""Handle input"""
	# Skip text animation
	if event.is_action_pressed("ui_accept") and revealed_chars < current_text.length():
		revealed_chars = current_text.length()
		dialogue_label.visible_ratio = 1.0
		get_viewport().set_input_as_handled()
	
	# Toggle theme with T key
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		toggle_theme()
