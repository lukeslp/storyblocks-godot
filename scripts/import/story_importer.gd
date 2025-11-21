extends Node
class_name StoryImporter

## Imports StoryBlocks JSON format into Godot-compatible dialogue data

func import_story(file_path: String) -> Dictionary:
	"""Load and parse a StoryBlocks JSON story file"""
	if not FileAccess.file_exists(file_path):
		push_error("Story file not found: " + file_path)
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open story file: " + file_path)
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		push_error("Failed to parse JSON: " + json.get_error_message())
		return {}
	
	var story_data = json.data
	return convert_story(story_data)

func convert_story(story_data: Dictionary) -> Dictionary:
	"""Convert StoryBlocks format to Godot dialogue format"""
	var converted = {
		"title": story_data.get("title", "Untitled Story"),
		"author": story_data.get("author", "Unknown"),
		"description": story_data.get("description", ""),
		"start_node": story_data.get("startNode", "start"),
		"initial_state": story_data.get("initialState", {}),
		"nodes": {}
	}
	
	# Convert each node
	var nodes = story_data.get("nodes", {})
	for node_id in nodes:
		var node = nodes[node_id]
		converted["nodes"][node_id] = convert_node(node_id, node)
	
	return converted

func convert_node(node_id: String, node: Dictionary) -> Dictionary:
	"""Convert a single StoryBlocks node to Godot format"""
	var converted = {
		"id": node_id,
		"type": node.get("type", "story"),
		"title": node.get("title", ""),
		"text": node.get("text", ""),
		"speaker": determine_speaker(node),
		"choices": [],
		"effects": node.get("effects", []),
		"conditions": node.get("condition", null)
	}
	
	# Convert choices
	var choices = node.get("choices", [])
	for choice in choices:
		converted["choices"].append(convert_choice(choice))
	
	return converted

func convert_choice(choice: Dictionary) -> Dictionary:
	"""Convert a StoryBlocks choice to Godot format"""
	return {
		"text": choice.get("text", "Continue"),
		"next": choice.get("next", ""),
		"condition": choice.get("condition", null),
		"effects": choice.get("effects", []),
		"skill_check": extract_skill_check(choice)
	}

func determine_speaker(node: Dictionary) -> String:
	"""Determine the speaker for a node"""
	var title = node.get("title", "")
	var text = node.get("text", "")
	
	# Check if it's narration or dialogue
	if text.begins_with("You ") or text.begins_with("Your "):
		return "NARRATOR"
	
	# Use title as speaker if it looks like a character name
	if title.length() > 0 and title.length() < 30:
		return title.to_upper()
	
	return "NARRATOR"

func extract_skill_check(choice: Dictionary) -> Dictionary:
	"""Extract skill check requirements from choice text"""
	var text = choice.get("text", "")
	var condition = choice.get("condition", "")
	
	# Parse skill checks from text like "[Wisdom >= 50]"
	var regex = RegEx.new()
	regex.compile("\\[([A-Za-z]+)\\s*>=?\\s*(\\d+)\\]")
	var result = regex.search(text)
	
	if result:
		return {
			"skill": result.get_string(1).to_lower(),
			"difficulty": int(result.get_string(2))
		}
	
	# Parse from condition string
	if condition:
		regex.compile("stats\\.([A-Za-z]+)\\s*>=?\\s*(\\d+)")
		result = regex.search(condition)
		if result:
			return {
				"skill": result.get_string(1).to_lower(),
				"difficulty": int(result.get_string(2))
			}
	
	return {}

func apply_effects(effects: Array, game_state: Dictionary):
	"""Apply node/choice effects to game state"""
	for effect in effects:
		var effect_type = effect.get("type", "")
		
		match effect_type:
			"modifyState":
				modify_state(effect, game_state)
			"setFlag":
				set_flag(effect, game_state)
			"addItem":
				add_item(effect, game_state)
			"removeItem":
				remove_item(effect, game_state)

func modify_state(effect: Dictionary, game_state: Dictionary):
	"""Modify a stat value"""
	var variable = effect.get("variable", "")
	var operation = effect.get("operation", "set")
	var value = effect.get("value", 0)
	
	# Parse variable path like "stats.courage"
	var parts = variable.split(".")
	if parts.size() != 2:
		return
	
	var category = parts[0]
	var key = parts[1]
	
	if not game_state.has(category):
		game_state[category] = {}
	
	var current = game_state[category].get(key, 0)
	
	match operation:
		"set":
			game_state[category][key] = value
		"add":
			game_state[category][key] = current + value
		"subtract":
			game_state[category][key] = current - value
		"multiply":
			game_state[category][key] = current * value

func set_flag(effect: Dictionary, game_state: Dictionary):
	"""Set a boolean flag"""
	var flag = effect.get("flag", "")
	var value = effect.get("value", true)
	
	if not game_state.has("flags"):
		game_state["flags"] = {}
	
	game_state["flags"][flag] = value

func add_item(effect: Dictionary, game_state: Dictionary):
	"""Add item to inventory"""
	var item = effect.get("item", "")
	
	if not game_state.has("inventory"):
		game_state["inventory"] = []
	
	if not game_state["inventory"].has(item):
		game_state["inventory"].append(item)

func remove_item(effect: Dictionary, game_state: Dictionary):
	"""Remove item from inventory"""
	var item = effect.get("item", "")
	
	if not game_state.has("inventory"):
		return
	
	var idx = game_state["inventory"].find(item)
	if idx >= 0:
		game_state["inventory"].remove_at(idx)

func check_condition(condition: String, game_state: Dictionary) -> bool:
	"""Evaluate a condition string against game state"""
	if not condition or condition.is_empty():
		return true
	
	# Simple condition parser
	# Supports: stats.wisdom >= 50, flags.found_key, inventory.has("sword")
	
	var regex = RegEx.new()
	
	# Check stat conditions
	regex.compile("stats\\.([A-Za-z]+)\\s*([><=]+)\\s*(\\d+)")
	var result = regex.search(condition)
	if result:
		var stat = result.get_string(1)
		var operator = result.get_string(2)
		var value = int(result.get_string(3))
		var current = game_state.get("stats", {}).get(stat, 0)
		return compare_values(current, operator, value)
	
	# Check flag conditions
	regex.compile("flags\\.([A-Za-z_]+)")
	result = regex.search(condition)
	if result:
		var flag = result.get_string(1)
		return game_state.get("flags", {}).get(flag, false)
	
	# Check inventory conditions
	regex.compile("inventory\\.has\\([\"']([^\"']+)[\"']\\)")
	result = regex.search(condition)
	if result:
		var item = result.get_string(1)
		return game_state.get("inventory", []).has(item)
	
	return true

func compare_values(a, operator: String, b) -> bool:
	"""Compare two values with an operator"""
	match operator:
		">=":
			return a >= b
		">":
			return a > b
		"<=":
			return a <= b
		"<":
			return a < b
		"==", "=":
			return a == b
		"!=":
			return a != b
	return false
