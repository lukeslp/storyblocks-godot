extends Node

## AI Client for connecting to StoryBlocks Flask proxy
## Handles text generation, image generation, and asset caching

signal text_generated(text: String)
signal image_generated(image_path: String)
signal generation_failed(error: String)

var api_base: String = "http://localhost:5000"
var provider: String = "xai"
var text_model: String = "grok-3"
var image_model: String = "grok-2-image-1212"

var http_request: HTTPRequest
var pending_requests: Dictionary = {}

func _ready():
	# Create HTTP request node
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	print("AIClient initialized - API Base: ", api_base)

func set_api_base(base_url: String):
	"""Configure the Flask proxy URL"""
	api_base = base_url

func generate_text(prompt: String, context: Dictionary = {}) -> String:
	"""Generate text using AI (async)"""
	var system_prompt = context.get("system_prompt", "You are a skilled storyteller creating engaging narrative content.")
	var max_tokens = context.get("max_tokens", 500)
	var temperature = context.get("temperature", 0.8)
	
	var body = {
		"provider": provider,
		"model": text_model,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": prompt}
		],
		"max_tokens": max_tokens,
		"temperature": temperature
	}
	
	var request_id = str(Time.get_ticks_msec())
	pending_requests[request_id] = {"type": "text", "prompt": prompt}
	
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(
		api_base + "/api/chat/completions",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	
	if error != OK:
		push_error("Failed to send AI request: " + str(error))
		generation_failed.emit("HTTP request failed")
		return ""
	
	print("AI text generation requested: ", prompt.substr(0, 50), "...")
	
	# Wait for response (will be handled in _on_request_completed)
	return ""

func generate_dialogue(character: String, context: String, mood: String = "neutral") -> String:
	"""Generate character dialogue"""
	var prompt = "Generate a short dialogue line for %s. Context: %s. Mood: %s. Keep it under 100 words." % [character, context, mood]
	var system = "You are writing dialogue for an interactive story. Write naturally and stay in character."
	
	return await generate_text(prompt, {"system_prompt": system, "max_tokens": 150})

func generate_description(subject: String, theme: String = "fantasy") -> String:
	"""Generate a descriptive paragraph"""
	var prompt = "Describe %s in a %s setting. Be vivid and atmospheric. 2-3 sentences." % [subject, theme]
	var system = "You are a descriptive writer creating immersive narrative content."
	
	return await generate_text(prompt, {"system_prompt": system, "max_tokens": 200})

func generate_image(prompt: String, context: Dictionary = {}) -> String:
	"""Generate image using AI (returns local path after download)"""
	var size = context.get("size", "1024x1024")
	var quality = context.get("quality", "standard")
	
	var body = {
		"provider": provider,
		"model": image_model,
		"prompt": prompt,
		"size": size,
		"quality": quality,
		"n": 1
	}
	
	var request_id = str(Time.get_ticks_msec())
	pending_requests[request_id] = {"type": "image", "prompt": prompt}
	
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(
		api_base + "/api/images/generations",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	
	if error != OK:
		push_error("Failed to send image generation request: " + str(error))
		generation_failed.emit("HTTP request failed")
		return ""
	
	print("AI image generation requested: ", prompt.substr(0, 50), "...")
	return ""

func generate_character_portrait(character_name: String, description: String) -> String:
	"""Generate a character portrait"""
	var prompt = "Character portrait of %s. %s. Digital art, detailed face, fantasy RPG style, neutral background." % [character_name, description]
	return await generate_image(prompt, {"size": "512x512"})

func generate_location_image(location_name: String, description: String) -> String:
	"""Generate a location/background image"""
	var prompt = "Fantasy RPG location: %s. %s. Atmospheric, detailed, game background art style." % [location_name, description]
	return await generate_image(prompt, {"size": "1024x1024"})

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	"""Handle HTTP response"""
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("HTTP request failed with result: " + str(result))
		generation_failed.emit("Request failed")
		return
	
	if response_code != 200:
		push_error("API returned error code: " + str(response_code))
		var error_text = body.get_string_from_utf8()
		print("Error response: ", error_text)
		generation_failed.emit("API error: " + str(response_code))
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		push_error("Failed to parse API response")
		generation_failed.emit("Invalid JSON response")
		return
	
	var response = json.data
	
	# Determine request type and handle accordingly
	if response.has("choices"):
		# Text generation response
		var text = response["choices"][0]["message"]["content"]
		print("AI generated text: ", text.substr(0, 100), "...")
		text_generated.emit(text)
	
	elif response.has("data"):
		# Image generation response
		var image_url = response["data"][0]["url"]
		print("AI generated image URL: ", image_url)
		
		# Download the image
		await download_image(image_url)

func download_image(url: String) -> String:
	"""Download an image from URL and save locally"""
	var http = HTTPRequest.new()
	add_child(http)
	
	var error = http.request(url)
	if error != OK:
		push_error("Failed to download image: " + str(error))
		http.queue_free()
		generation_failed.emit("Image download failed")
		return ""
	
	var result = await http.request_completed
	http.queue_free()
	
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		push_error("Image download failed")
		generation_failed.emit("Image download failed")
		return ""
	
	# Save to file
	var image_data = result[3]
	var filename = "generated_" + str(Time.get_ticks_msec()) + ".png"
	var filepath = "user://cache/" + filename
	
	# Ensure cache directory exists
	DirAccess.make_dir_absolute("user://cache")
	
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		file.store_buffer(image_data)
		file.close()
		print("Image saved to: ", filepath)
		image_generated.emit(filepath)
		return filepath
	else:
		push_error("Failed to save image file")
		generation_failed.emit("Failed to save image")
		return ""

func test_connection() -> bool:
	"""Test connection to Flask proxy"""
	var http = HTTPRequest.new()
	add_child(http)
	
	var error = http.request(api_base + "/api/models")
	if error != OK:
		http.queue_free()
		return false
	
	var result = await http.request_completed
	http.queue_free()
	
	return result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
