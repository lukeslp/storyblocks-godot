extends Node

## Game Manager - Handles game state, story progression, and system coordination

signal story_loaded(story_data: Dictionary)
signal node_changed(node_id: String, node_data: Dictionary)
signal state_changed(game_state: Dictionary)

# Story data
var current_story: Dictionary = {}
var current_node_id: String = ""
var current_node: Dictionary = {}

# Game state
var game_state: Dictionary = {
	"stats": {},
	"inventory": [],
	"flags": {},
	"variables": {},
	"relationships": {}
}

# Systems
var story_importer
var ai_enabled: bool = true

func _ready():
	# Initialize story importer
	var StoryImporterClass = load("res://scripts/import/story_importer.gd")
	story_importer = StoryImporterClass.new()
	add_child(story_importer)
	
	print("GameManager initialized")

func load_story(story_path: String):
	"""Load a StoryBlocks JSON story"""
	print("Loading story: ", story_path)
	
	current_story = story_importer.import_story(story_path)
	
	if current_story.is_empty():
		push_error("Failed to load story")
		return false
	
	# Initialize game state from story
	var initial_state = current_story.get("initial_state", {})
	game_state["stats"] = initial_state.get("stats", {})
	game_state["inventory"] = initial_state.get("inventory", [])
	game_state["flags"] = initial_state.get("flags", {})
	game_state["variables"] = initial_state.get("variables", {})
	game_state["relationships"] = initial_state.get("relationships", {})
	
	# Start at the beginning
	var start_node = current_story.get("start_node", "start")
	goto_node(start_node)
	
	story_loaded.emit(current_story)
	print("Story loaded: ", current_story.get("title", "Unknown"))
	return true

func goto_node(node_id: String):
	"""Navigate to a specific story node"""
	if not current_story.has("nodes"):
		push_error("No story loaded")
		return
	
	var nodes = current_story["nodes"]
	if not nodes.has(node_id):
		push_error("Node not found: " + node_id)
		return
	
	current_node_id = node_id
	current_node = nodes[node_id]
	
	# Apply node effects
	var effects = current_node.get("effects", [])
	if effects.size() > 0:
		story_importer.apply_effects(effects, game_state)
		state_changed.emit(game_state)
	
	# Check if AI enhancement is needed
	if ai_enabled and should_enhance_with_ai(current_node):
		await enhance_node_with_ai()
	
	node_changed.emit(node_id, current_node)
	print("Navigated to node: ", node_id, " - ", current_node.get("title", ""))

func select_choice(choice_index: int):
	"""Select a dialogue choice"""
	var choices = current_node.get("choices", [])
	
	if choice_index < 0 or choice_index >= choices.size():
		push_error("Invalid choice index: " + str(choice_index))
		return
	
	var choice = choices[choice_index]
	
	# Check condition
	var condition = choice.get("condition", null)
	if condition and not story_importer.check_condition(condition, game_state):
		push_warning("Choice condition not met")
		return
	
	# Check skill check
	var skill_check = choice.get("skill_check", {})
	if not skill_check.is_empty():
		var success = perform_skill_check(skill_check)
		if not success:
			# Handle failure (could branch to different node)
			print("Skill check failed")
	
	# Apply choice effects
	var effects = choice.get("effects", [])
	if effects.size() > 0:
		story_importer.apply_effects(effects, game_state)
		state_changed.emit(game_state)
	
	# Navigate to next node
	var next_node = choice.get("next", "")
	if next_node:
		goto_node(next_node)

func perform_skill_check(skill_check: Dictionary) -> bool:
	"""Perform a skill check"""
	var skill = skill_check.get("skill", "")
	var difficulty = skill_check.get("difficulty", 10)
	
	# Get skill value from stats
	var skill_value = game_state.get("stats", {}).get(skill, 0)
	
	# Roll dice (1d20 for more dramatic range)
	var roll = randi() % 20 + 1
	var total = skill_value + roll
	
	var success = total >= difficulty
	
	print("Skill check: ", skill, " (", skill_value, ") + ", roll, " = ", total, " vs ", difficulty, " - ", "SUCCESS" if success else "FAILURE")
	
	return success

func should_enhance_with_ai(node: Dictionary) -> bool:
	"""Check if node should be enhanced with AI"""
	# Only enhance if text is short or placeholder
	var text = node.get("text", "")
	return text.length() < 50 or text.contains("[AI]") or text.contains("[GENERATE]")

func enhance_node_with_ai():
	"""Use AI to enhance current node text"""
	var ai_client = get_node("/root/AIClient")
	if not ai_client:
		return
	
	var context = {
		"title": current_node.get("title", ""),
		"type": current_node.get("type", "story"),
		"game_state": game_state,
		"story_title": current_story.get("title", "")
	}
	
	var prompt = build_ai_prompt(context)
	
	print("Enhancing node with AI...")
	ai_client.text_generated.connect(_on_ai_text_generated, CONNECT_ONE_SHOT)
	ai_client.generate_text(prompt, {"max_tokens": 300})

func build_ai_prompt(context: Dictionary) -> String:
	"""Build prompt for AI text generation"""
	var prompt = "You are writing for an interactive story titled '%s'.\n" % context.get("story_title", "Unknown")
	prompt += "Current scene: %s\n" % context.get("title", "Unknown")
	prompt += "Scene type: %s\n\n" % context.get("type", "story")
	prompt += "Write a vivid, engaging paragraph (2-4 sentences) that describes this scene.\n"
	prompt += "Keep the tone mysterious and atmospheric. Use second person ('You')."
	
	return prompt

func _on_ai_text_generated(text: String):
	"""Handle AI-generated text"""
	if text and not text.is_empty():
		current_node["text"] = text
		node_changed.emit(current_node_id, current_node)
		print("Node enhanced with AI")

func get_current_node() -> Dictionary:
	"""Get the current story node"""
	return current_node

func get_game_state() -> Dictionary:
	"""Get the current game state"""
	return game_state

func get_stat(stat_name: String) -> int:
	"""Get a stat value"""
	return game_state.get("stats", {}).get(stat_name, 0)

func has_item(item_name: String) -> bool:
	"""Check if player has an item"""
	return game_state.get("inventory", []).has(item_name)

func has_flag(flag_name: String) -> bool:
	"""Check if a flag is set"""
	return game_state.get("flags", {}).get(flag_name, false)

func save_game(slot: int = 0):
	"""Save game state"""
	var save_data = {
		"story_title": current_story.get("title", ""),
		"current_node": current_node_id,
		"game_state": game_state,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	var save_path = "user://save_%d.json" % slot
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("Game saved to slot ", slot)
		return true
	else:
		push_error("Failed to save game")
		return false

func load_game(slot: int = 0):
	"""Load game state"""
	var save_path = "user://save_%d.json" % slot
	if not FileAccess.file_exists(save_path):
		push_error("Save file not found")
		return false
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		push_error("Failed to open save file")
		return false
	
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	
	if parse_result != OK:
		push_error("Failed to parse save file")
		return false
	
	var save_data = json.data
	game_state = save_data.get("game_state", {})
	var node_id = save_data.get("current_node", "start")
	
	goto_node(node_id)
	state_changed.emit(game_state)
	
	print("Game loaded from slot ", slot)
	return true
