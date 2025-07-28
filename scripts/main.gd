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

# Very conservative word batching variables
var pending_words: Array = []
var word_batch_timer: float = 0.0
var word_batch_interval: float = 3.0
var max_words_per_batch: int = 2

# Manager references
@onready var challenge_manager: Node
@onready var player_stats_manager: Node
@onready var chest_system: Node
@onready var inventory_system: Node
@onready var subtitle_system: Node

func _ready() -> void:
	add_to_group("main")
	peer = SteamManager.peer
	
	peer.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	
	# Initialize ALL systems
	player_stats_manager = preload("res://scripts/player_stats_manager.gd").new()
	add_child(player_stats_manager)
	player_stats_manager.name = "PlayerStatsManager"
	
	challenge_manager = preload("res://scripts/challenge_manager.gd").new()
	add_child(challenge_manager)
	challenge_manager.name = "ChallengeManager"
	
	chest_system = preload("res://scripts/chest_system.gd").new()
	add_child(chest_system)
	chest_system.name = "ChestSystem"
	
	inventory_system = preload("res://scripts/inventory_system.gd").new()
	add_child(inventory_system)
	inventory_system.name = "InventorySystem"
	
	# Initialize subtitle system using the class from player_subtitle_overlay.gd
	#subtitle_system = preload("res://scripts/player_subtitle_overlay.gd").SubtitleSystemManager.new()
	#add_child(subtitle_system)
	#subtitle_system.name = "SubtitleSystem"
	
	print("Main: All systems initialized!")
	
	await get_tree().process_frame
	print("Main: Nodes in player_stats group: ", get_tree().get_nodes_in_group("player_stats"))
	print("Main: Nodes in challenge_manager group: ", get_tree().get_nodes_in_group("challenge_manager"))

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
		
		var spawned_player = player_spawner.spawn_host()
		initialize_new_player(spawned_player)

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

# Initialize player stats when they spawn
func initialize_new_player(player_node):
	if player_stats_manager and player_node:
		player_stats_manager.initialize_player(player_node.steam_id)
	
	# Add subtitle overlay for this player
	if subtitle_system:
		subtitle_system.on_player_joined(player_node)

# Broadcast terrain seed to all clients
func broadcast_terrain_seed():
	var seed_data = {
		"message": "terrain_seed",
		"seed": terrain_seed,
		"steam_id": SteamManager.STEAM_ID,
		"username": SteamManager.STEAM_USERNAME
	}
	print("Broadcasting terrain seed: ", terrain_seed)
	SteamManager.send_p2p_packet(0, seed_data)

# Handle received terrain seed
func handle_terrain_seed(seed_data: Dictionary):
	if !terrain_seed_set:
		terrain_seed = seed_data["seed"]
		terrain_seed_set = true
		apply_terrain_seed()
		print("Applied terrain seed: ", terrain_seed, " from ", seed_data["username"])
	else:
		print("Terrain seed already set, ignoring new seed from ", seed_data.get("username", "Unknown"))

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

# Modified spawn_word function with challenge validation
func spawn_word(new_text: String):
	var new_words = find_differences_in_sentences(previous_sentence, remove_punctuation(new_text))
	
	for word in new_words:
		# Validate word against current challenge
		var is_valid = true
		if challenge_manager:
			is_valid = challenge_manager.validate_word(word, SteamManager.STEAM_ID)
		
		# Only spawn if valid and not already in word bank
		if is_valid and !word_bank.has(word.to_lower()):
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

func send_word_batch():
	if pending_words.size() == 0:
		return
	
	# Send only very small batches, one at a time
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
	if sender_steam_id != SteamManager.STEAM_ID:
		apply_terrain_destruction(pos, radius)
		print("Applied terrain destruction at ", pos, " with radius ", radius, " from ", destruction_data["username"])

func apply_terrain_destruction(pos: Vector3, radius: float):
	var terrain = get_node("Terrain")
	if terrain:
		var voxel_tool = terrain.get_voxel_tool()
		voxel_tool.mode = VoxelTool.MODE_REMOVE
		voxel_tool.do_sphere(pos, radius)

# CHALLENGE MESSAGE HANDLERS
func handle_challenge_start(message_data: Dictionary):
	if challenge_manager:
		challenge_manager.handle_challenge_start(message_data)

func handle_challenge_end(message_data: Dictionary):
	if challenge_manager:
		challenge_manager.handle_challenge_end()

func handle_counting_progress(message_data: Dictionary):
	if challenge_manager:
		challenge_manager.handle_counting_progress(message_data)

func handle_player_stats_sync(message_data: Dictionary):
	if player_stats_manager:
		player_stats_manager.handle_stats_sync(message_data)

# NEW CHEST SYSTEM HANDLERS
func handle_chest_spawned(message_data: Dictionary):
	if chest_system:
		chest_system.handle_chest_spawned(message_data)

func handle_chest_opened(message_data: Dictionary):
	if chest_system:
		chest_system.handle_chest_opened(message_data)

func handle_mimic_activated(message_data: Dictionary):
	if chest_system:
		chest_system.handle_mimic_activated(message_data)

# NEW INVENTORY SYSTEM HANDLERS
func handle_inventory_sync(message_data: Dictionary):
	if inventory_system:
		inventory_system.handle_inventory_sync(message_data)

func handle_blue_shell_fired(message_data: Dictionary):
	if inventory_system:
		inventory_system.handle_blue_shell_fired(message_data)

func handle_blue_shell_exploded(message_data: Dictionary):
	# Handle blue shell explosions
	var shells = get_tree().get_nodes_in_group("blue_shells")
	for shell in shells:
		if shell.has_method("handle_explosion_sync"):
			shell.handle_explosion_sync(message_data)

# NEW WORD GUN HANDLER
func handle_word_gun_shot(message_data: Dictionary):
	print("Word gun shot received from player ", message_data["steam_id"])
	# The word gun system will handle creating the projectile

# NEW SUBTITLE HANDLER
func handle_player_speech_subtitle(message_data: Dictionary):
	if subtitle_system:
		subtitle_system.handle_player_speech(message_data)

func _on_speech_to_text_transcribed_msg(is_partial: Variant, new_text: Variant) -> void:
	if !is_partial:
		spawn_word(new_text)
		previous_sentence = remove_punctuation(new_text)
		
		# Send subtitle to other players
		if main_player:
			var speech_data = {
				"message": "player_speech_subtitle",
				"steam_id": SteamManager.STEAM_ID,
				"text": new_text,
				"position": [main_player.global_position.x, main_player.global_position.y, main_player.global_position.z]
			}
			SteamManager.send_p2p_packet(0, speech_data)
		
		# Load word gun if active
		if main_player and main_player.has_method("load_word_gun_ammo"):
			var words = new_text.split(" ")
			if words.size() > 0:
				main_player.load_word_gun_ammo(words[-1])  # Last word spoken
