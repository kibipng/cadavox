# chest_manager.gd
extends Node

signal chest_spawned(chest_position: Vector3)
signal chest_opened(chest_id: int, player_steam_id: int, reward: Dictionary)

# Chest spawning configuration
var chest_spawn_interval: float = 0.1  # Spawn every 30 seconds
var max_chests_on_map: int = 500
var chest_spawn_timer: float = 0.0

# Chest tracking
var active_chests: Dictionary = {}  # chest_id -> chest_data
var next_chest_id: int = 0

# Chest types and rewards
var chest_types = {
	"common": {
		"cost": 10,
		"color": Color.BROWN,
		"rewards": [
			{"type": "health", "amount": 25},
			{"type": "coins", "amount": 15},
			{"type": "immunity", "duration": 5.0},
			{"type": "item", "item_id": "word_gun"}
		]
	},
	"rare": {
		"cost": 25,
		"color": Color.BLUE,
		"rewards": [
			{"type": "health", "amount": 50},
			{"type": "coins", "amount": 30},
			{"type": "immunity", "duration": 10.0},
			{"type": "speed_boost", "duration": 15.0},
			{"type": "item", "item_id": "word_gun"}  # Add this
		]
	},
	"legendary": {
		"cost": 50,
		"color": Color.GOLD,
		"rewards": [
			{"type": "full_heal", "amount": 100},
			{"type": "coins", "amount": 100},
			{"type": "immunity", "duration": 20.0},
			{"type": "flight", "duration": 10.0},
			{"type": "item", "item_id": "blue_shell"}  # Add this
		]
	}
}

# References
var terrain: VoxelTerrain
var player_stats_manager: Node

func _ready():
	add_to_group("chest_manager")
	
	# Get references
	terrain = get_node("/root/Main/Terrain")
	player_stats_manager = get_tree().get_first_node_in_group("player_stats")
	
	# Only host manages chest spawning
	chest_spawn_timer = chest_spawn_interval

func _process(delta):
	if not SteamManager.is_lobby_host:
		return
	
	chest_spawn_timer -= delta
	if chest_spawn_timer <= 0 and active_chests.size() < max_chests_on_map:
		spawn_random_chest()
		chest_spawn_timer = chest_spawn_interval

func spawn_random_chest():
	# Find a good spawn location below terrain
	var spawn_pos = find_chest_spawn_location()
	if spawn_pos == Vector3.ZERO:
		return  # Couldn't find good location
	
	# Choose chest type (weighted random)
	var chest_type = choose_chest_type()
	
	var chest_data = {
		"id": next_chest_id,
		"type": chest_type,
		"position": [spawn_pos.x, spawn_pos.y, spawn_pos.z],
		"cost": chest_types[chest_type]["cost"],
		"opened": false
	}
	
	active_chests[next_chest_id] = chest_data
	next_chest_id += 1
	
	# Broadcast chest spawn to all clients
	var spawn_message = {
		"message": "chest_spawn",
		"chest_data": chest_data
	}
	SteamManager.send_p2p_packet(0, spawn_message)
	
	# Spawn locally
	spawn_chest_locally(chest_data)
	
	print("Spawned ", chest_type, " chest at ", spawn_pos)

func find_chest_spawn_location() -> Vector3:
	var terrain_bounds = 20  # Match your terrain size
	var max_attempts = 20
	
	for i in range(max_attempts):
		# Random surface position
		var x = randf_range(-terrain_bounds, terrain_bounds)
		var z = randf_range(-terrain_bounds, terrain_bounds)
		
		# Find surface height using voxel tool
		var voxel_tool = terrain.get_voxel_tool()
		var surface_y = find_surface_height(voxel_tool, Vector3(x, 0, z))
		
		if surface_y != -999:  # Found valid surface
			# Spawn chest slightly below surface in a small cave
			var chest_y = surface_y - randf_range(3, 8) - 20
			return Vector3(x, chest_y, z)
	
	return Vector3.ZERO  # Failed to find location

func find_surface_height(voxel_tool: VoxelTool, pos: Vector3) -> float:
	# Raycast down from above terrain to find surface
	for y in range(20, -30, -1):  # Start high, go down
		var test_pos = Vector3(pos.x, y, pos.z)
		var voxel_value = voxel_tool.get_voxel(test_pos)
		
		if voxel_value > 0.5:  # Hit solid terrain
			return float(y + 1)  # Return position just above surface
	
	return -999  # No surface found

func choose_chest_type() -> String:
	var rand = randf()
	if rand < 0.6:  # 60% common
		return "common"
	elif rand < 0.85:  # 25% rare
		return "rare"
	else:  # 15% legendary
		return "legendary"

func spawn_chest_locally(chest_data: Dictionary):
	# Load and instantiate chest scene
	var chest_scene = preload("res://scenes/treasure_chest.tscn")
	var chest_instance = chest_scene.instantiate()
	
	
	# Set chest properties
	var pos_array = chest_data["position"]
	var pos = Vector3(pos_array[0], pos_array[1], pos_array[2])
	
	chest_instance.global_position = pos
	chest_instance.chest_id = chest_data["id"]
	chest_instance.chest_type = chest_data["type"]
	chest_instance.unlock_cost = chest_data["cost"]
	chest_instance.chest_manager = self
	
	# Add to scene
	var chests_node = get_node("/root/Main/Chests")
	if not chests_node:
		chests_node = Node3D.new()
		chests_node.name = "Chests"
		get_node("/root/Main").add_child(chests_node)
	
	chests_node.add_child(chest_instance)

# Called when player attempts to open chest
func attempt_open_chest(chest_id: int, player_steam_id: int) -> bool:
	if not active_chests.has(chest_id) or active_chests[chest_id]["opened"]:
		return false
	
	var chest_data = active_chests[chest_id]
	var cost = chest_data["cost"]
	
	# Check if player has enough coins
	if not player_stats_manager:
		return false
	
	var player_coins = player_stats_manager.get_player_coins(player_steam_id)
	if player_coins < cost:
		return false
	
	# Deduct coins and give reward
	player_stats_manager.add_coins(player_steam_id, -cost)
	
	# Generate reward
	var reward = generate_reward(chest_data["type"])
	apply_reward(player_steam_id, reward)
	
	# Mark chest as opened
	active_chests[chest_id]["opened"] = true
	
	# Broadcast chest opening
	var open_message = {
		"message": "chest_opened",
		"chest_id": chest_id,
		"player_steam_id": player_steam_id,
		"reward": reward
	}
	SteamManager.send_p2p_packet(0, open_message)
	
	# Emit signal
	chest_opened.emit(chest_id, player_steam_id, reward)
	
	return true

func generate_reward(chest_type: String) -> Dictionary:
	var possible_rewards = chest_types[chest_type]["rewards"]
	var chosen_reward = possible_rewards[randi() % possible_rewards.size()]
	return chosen_reward.duplicate()

func apply_reward(player_steam_id: int, reward: Dictionary):
	match reward["type"]:
		"health":
			# Add health (handled by player_stats_manager)
			if player_stats_manager:
				var current_health = player_stats_manager.get_player_health(player_steam_id)
				var max_health = player_stats_manager.max_health
				var new_health = min(current_health + reward["amount"], max_health)
				# We need to add a heal function to player_stats_manager
				player_stats_manager.heal_player(player_steam_id, reward["amount"])
		
		"full_heal":
			if player_stats_manager:
				player_stats_manager.heal_player(player_steam_id, 999)  # Full heal
		
		"coins":
			if player_stats_manager:
				player_stats_manager.add_coins(player_steam_id, reward["amount"])
		
		"immunity":
			apply_challenge_immunity(player_steam_id, reward["duration"])
		
		"speed_boost":
			apply_speed_boost(player_steam_id, reward["duration"])
		
		"flight":
			apply_flight_ability(player_steam_id, reward["duration"])
		"item":
			var players = get_tree().get_nodes_in_group("players")
			for player in players:
				if player.steam_id == player_steam_id:
					player.give_item(reward["item_id"])
					break

func apply_challenge_immunity(player_steam_id: int, duration: float):
	# Add immunity effect to player
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.steam_id == player_steam_id:
			player.add_status_effect("immunity", duration)
			break

func apply_speed_boost(player_steam_id: int, duration: float):
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.steam_id == player_steam_id:
			player.add_status_effect("speed_boost", duration)
			break

func apply_flight_ability(player_steam_id: int, duration: float):
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.steam_id == player_steam_id:
			player.add_status_effect("flight", duration)
			break

# Message handlers (called by Main.gd)
func handle_chest_spawn(message_data: Dictionary):
	spawn_chest_locally(message_data["chest_data"])

func handle_chest_opened(message_data: Dictionary):
	var chest_id = message_data["chest_id"]
	if active_chests.has(chest_id):
		active_chests[chest_id]["opened"] = true
	
	# Update local chest visual
	var chests_node = get_node("/root/Main/Chests")
	if chests_node:
		for chest in chests_node.get_children():
			if chest.chest_id == chest_id:
				chest.set_opened_state()
				break
