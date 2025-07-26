extends Node3D

@onready var lobbies_list: VBoxContainer = $MultiplayerUI/VBoxContainer/LobbiesScrollContainer/LobbiesList
@onready var multiplayer_ui: Control = $MultiplayerUI
@onready var player_spawner: MultiplayerSpawner = $Players/PlayerSpawner
@onready var letter_spawner: MultiplayerSpawner = $Letters/LetterSpawner

const TEXT_CHARACTER = preload("res://scenes/text_character.tscn")

var lobby_id = 0

var previous_sentence: String = ""

var lobby_created: bool = false

var peer = SteamMultiplayerPeer
var word_bank = []
var main_player

# Add terrain seed management
var terrain_seed: int = -1
var terrain_seed_set: bool = false

# Optimized word batching variables
var pending_words: Array = []
var word_batch_timer: float = 0.0
var word_batch_interval: float = 1.0  # Increased to 1 second to reduce packet frequency
var max_words_per_batch: int = 5      # Limit words per batch to keep packets small

func _ready() -> void:
	add_to_group("main")  # Add this so SteamManager can find the main scene
	peer = SteamManager.peer
	
	peer.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)

func _process(delta: float) -> void:
	word_batch_timer += delta
	if word_batch_timer >= word_batch_interval and pending_words.size() > 0:
		send_word_batch()
		word_batch_timer = 0.0

func _on_host_btn_pressed() -> void:
	if lobby_created:
		return 
	
	peer.create_lobby(SteamMultiplayerPeer.LOBBY_TYPE_PUBLIC)
	multiplayer.multiplayer_peer = peer

func remove_punctuation(text: String) -> String:
	var unwanted_chars = [".", ",", ":", ";", "!", "?", "'", "(", ")"]
	var cleaned_text = ""
	for char in text:
		if not char in unwanted_chars:
			cleaned_text += char
	return cleaned_text

func _on_join_btn_pressed() -> void:
	var lobbies_btns = lobbies_list.get_children()
	for i in lobbies_btns:
		i.queue_free()
	
	open_lobby_list()

func open_lobby_list():
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

func _on_lobby_created(connect: int, _lobby_id: int):
	if connect:
		lobby_id = _lobby_id
		Steam.setLobbyData(lobby_id, "name", str(SteamManager.STEAM_USERNAME + "'s lobby -312-"))
		Steam.setLobbyJoinable(lobby_id, true)
		
		SteamManager.lobby_id = lobby_id
		SteamManager.is_lobby_host = true
		
		hide_menu()
		
		# Host generates and broadcasts the terrain seed
		if terrain_seed == -1:
			randomize()
			terrain_seed = randi()
			broadcast_terrain_seed()
		
		player_spawner.spawn_host()

func _on_lobby_match_list(lobbies: Array):
	var i = 0
	for lobby in lobbies:
		var lobby_name = Steam.getLobbyData(lobby, "name")
		var member_count = Steam.getNumLobbyMembers(lobby)
		var max_players = Steam.getLobbyMemberLimit(lobby)
		
		if lobby_name.contains("-312-"):
			var but := Button.new()
			but.set_text("{0} | {1}/{2}".format([lobby_name.replace(" -312-", ""), member_count, max_players]))
			but.set_size(Vector2(400, 50))
			but.pressed.connect(join_lobby.bind(lobby))
			lobbies_list.add_child(but)
			i += 1
	
	if i <= 0:
		var but := Button.new()
		but.set_text("no lobbies found :( (maybe try refreshing?)")
		but.set_size(Vector2(400, 50))
		lobbies_list.add_child(but)

func join_lobby(_lobby_id):
	peer.connect_lobby(_lobby_id)
	multiplayer.multiplayer_peer = peer
	lobby_id = _lobby_id
	hide_menu()

func hide_menu():
	multiplayer_ui.hide()

# Broadcast terrain seed to all clients
func broadcast_terrain_seed():
	var seed_data = {
		"message": "terrain_seed",
		"seed": terrain_seed,
		"steam_id": SteamManager.STEAM_ID,
		"username": SteamManager.STEAM_USERNAME
	}
	SteamManager.send_p2p_packet(0, seed_data)

# Handle received terrain seed
func handle_terrain_seed(seed_data: Dictionary):
	if !terrain_seed_set:
		terrain_seed = seed_data["seed"]
		apply_terrain_seed()
		print("Received terrain seed: ", terrain_seed, " from ", seed_data["username"])

# Apply the terrain seed to all players and terrain
func apply_terrain_seed():
	if terrain_seed == -1:
		return
		
	terrain_seed_set = true
	
	# Apply to terrain
	var terrain = get_node("Terrain")
	if terrain:
		terrain.generator.noise.seed = terrain_seed
	
	# Apply to all players
	for player in get_tree().get_nodes_in_group("players"):
		if player.has_method("set_terrain_seed"):
			player.set_terrain_seed(terrain_seed)

func find_differences_in_sentences(og_sentence: String, new_sentence: String) -> Array[String]:
	var og = og_sentence.split(" ")
	var new = new_sentence.split(" ")
	var diff: Array[String] = []
	
	for word in new:
		if !og.has(word):
			diff.append(word)
	
	return diff

# Modified spawn_word function with optimized batching
func spawn_word(new_text: String):
	var new_words = find_differences_in_sentences(previous_sentence, remove_punctuation(new_text))
	
	for word in new_words:
		if !word_bank.has(word.to_lower()):
			var pos = Vector3(randf_range(-20, 20), 50, randf_range(-20, 20))
			var rotation_y = randf_range(-360, 360)
			
			# Add to pending batch
			pending_words.append({
				"word": word,
				"position": [pos.x, pos.y, pos.z],
				"rotation_y": rotation_y
			})
			
			# Also spawn locally
			spawn_word_locally(word, pos, rotation_y)
			
			# Send immediately if we hit the batch limit (prevents large packets)
			if pending_words.size() >= max_words_per_batch:
				send_word_batch()
				word_batch_timer = 0.0

func send_word_batch():
	if pending_words.size() == 0:
		return
	
	# Split into smaller batches if needed
	while pending_words.size() > 0:
		var batch_size = min(max_words_per_batch, pending_words.size())
		var current_batch = pending_words.slice(0, batch_size)
		pending_words = pending_words.slice(batch_size)
		
		# Send this batch
		var batch_data = {
			"message": "spawn_word_batch",
			"words": current_batch,
			"steam_id": SteamManager.STEAM_ID,
			"username": SteamManager.STEAM_USERNAME
		}
		
		SteamManager.send_p2p_packet(0, batch_data)
		
		# Small delay between batches to avoid overwhelming Steam
		if pending_words.size() > 0:
			await get_tree().create_timer(0.1).timeout

# Function to spawn words locally on each client with synchronized rotation
func spawn_word_locally(word: String, pos: Vector3, rotation_y: float):
	if !word_bank.has(word.to_lower()):
		letter_spawner.print_3d(word, pos, rotation_y)
		word_bank.append(word.to_lower())
		
		if main_player == null:
			var players = get_tree().get_nodes_in_group("players")
			if players.size() > 0:
				main_player = players[0]
		
		if main_player != null:
			main_player.spawn_text.append([word.to_lower(), pos])

# Function called by SteamManager when word data is received
func handle_word_spawn(word_data: Dictionary):
	var word = word_data["word"]
	var pos_array = word_data["position"]
	var pos = Vector3(pos_array[0], pos_array[1], pos_array[2])
	var rotation_y = word_data["rotation_y"]
	
	spawn_word_locally(word, pos, rotation_y)

# Add handler for batched words
func handle_word_batch_spawn(batch_data: Dictionary):
	var words = batch_data["words"]
	for word_info in words:
		var word = word_info["word"]
		var pos_array = word_info["position"]
		var pos = Vector3(pos_array[0], pos_array[1], pos_array[2])
		var rotation_y = word_info["rotation_y"]
		
		spawn_word_locally(word, pos, rotation_y)

# Function called by SteamManager when terrain destruction data is received
func handle_terrain_destruction(destruction_data: Dictionary):
	var pos_array = destruction_data["position"]
	var pos = Vector3(pos_array[0], pos_array[1], pos_array[2])
	var radius = destruction_data["radius"]
	var sender_steam_id = destruction_data["steam_id"]
	
	# Only apply if this destruction is from someone else
	# (the sender already applied it locally)
	if sender_steam_id != SteamManager.STEAM_ID:
		apply_terrain_destruction(pos, radius)
		print("Applied terrain destruction at ", pos, " with radius ", radius, " from ", destruction_data["username"])

func apply_terrain_destruction(pos: Vector3, radius: float):
	var terrain = get_node("Terrain")
	if terrain:
		var voxel_tool = terrain.get_voxel_tool()
		voxel_tool.mode = VoxelTool.MODE_REMOVE
		voxel_tool.do_sphere(pos, radius)

func _on_speech_to_text_transcribed_msg(is_partial: Variant, new_text: Variant) -> void:
	if !is_partial:
		spawn_word(new_text)
		previous_sentence = remove_punctuation(new_text)
