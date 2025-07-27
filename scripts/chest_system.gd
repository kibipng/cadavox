# chest_system.gd - ENHANCED VERSION
extends Node

signal chest_opened(chest_type: String, items: Array, player_steam_id: int)
signal chest_spawned(chest_position: Vector3, chest_type: String)

# Chest types with custom mesh paths
var chest_types = {
	"common": {
		"cost": 5,
		"mesh_path": "res://models/common_chest.tres",
		"material_color": Color.BROWN,
		"spawn_chance": 0.7,
		"items": [
			{"type": "coins", "amount": 8, "chance": 0.4},          # Most common
			{"type": "health_potion", "chance": 0.3},               # Useful healing
			{"type": "coins", "amount": 15, "chance": 0.2},         # Bonus coins
			{"type": "word_gun", "chance": 0.1}                     # Rare weapon
		]
	},
	"rare": {
		"cost": 15,
		"mesh_path": "res://models/rare_chest.tres",
		"material_color": Color.PURPLE,
		"spawn_chance": 0.25,
		"items": [
			{"type": "blue_turtle_shell", "chance": 0.35},          # High chance for powerful item
			{"type": "word_gun", "chance": 0.25},                   # Good chance for weapon
			{"type": "coins", "amount": 30, "chance": 0.2},         # Big coin bonus
			{"type": "max_hp_boost", "chance": 0.15},               # Rare permanent upgrade
			{"type": "full_heal", "chance": 0.05}                   # Emergency heal
		]
	},
	"mimic": {
		"cost": 5,
		"mesh_path": "res://models/common_chest.tres",
		"material_color": Color.BROWN,
		"spawn_chance": 0.05,
		"damage": 40,  # Increased damage since inventory is more valuable now
		"explosion_radius": 6.0
	}
}

# Active chests in the world
var active_chests = {}
var chest_id_counter = 0

# Terrain reference for spawning
var terrain: VoxelTerrain

func _ready():
	add_to_group("chest_system")
	
	# Get terrain reference
	terrain = get_node("/root/Main/Terrain")
	
	# Start spawning chests periodically
	spawn_initial_chests()
	
	# Spawn new chests every few minutes
	var timer = Timer.new()
	timer.wait_time = 120.0  # 2 minutes
	timer.timeout.connect(spawn_random_chest)
	timer.autostart = true
	add_child(timer)

func spawn_initial_chests():
	# Spawn some chests at game start
	for i in range(5):
		await get_tree().create_timer(randf() * 10.0).timeout
		spawn_random_chest()

func spawn_random_chest():
	if not terrain:
		return
	
	# Find a random underground position
	var attempts = 0
	while attempts < 10:
		var x = randf_range(-50, 50)
		var z = randf_range(-50, 50)
		var surface_y = get_surface_height(x, z)
		var chest_y = surface_y - randf_range(5, 15)  # 5-15 blocks underground
		
		var chest_pos = Vector3(x, chest_y, z)
		
		# Determine chest type
		var chest_type = determine_chest_type()
		
		# Create the chest
		create_chest(chest_pos, chest_type)
		break
		
		attempts += 1

func get_surface_height(x: float, z: float) -> float:
	# Simple approximation - you might need to adjust this based on your terrain
	if terrain and terrain.generator and terrain.generator.noise:
		return terrain.generator.noise.get_noise_2d(x, z) * 20.0
	return 0.0

func determine_chest_type() -> String:
	var roll = randf()
	
	if roll < chest_types["mimic"]["spawn_chance"]:
		return "mimic"
	elif roll < chest_types["mimic"]["spawn_chance"] + chest_types["rare"]["spawn_chance"]:
		return "rare"
	else:
		return "common"

func create_chest(position: Vector3, chest_type: String):
	chest_id_counter += 1
	var chest_id = chest_id_counter
	
	# Store chest data
	active_chests[chest_id] = {
		"position": position,
		"type": chest_type,
		"discovered": false,
		"opened": false
	}
	
	# Spawn chest visually
	spawn_chest_visual(chest_id, position, chest_type)
	
	# Sync to all clients
	var chest_data = {
		"message": "chest_spawned",
		"chest_id": chest_id,
		"position": [position.x, position.y, position.z],
		"chest_type": chest_type
	}
	SteamManager.send_p2p_packet(0, chest_data)
	
	print("Spawned ", chest_type, " chest at ", position)

func spawn_chest_visual(chest_id: int, position: Vector3, chest_type: String):
	# Create the actual 3D chest object
	var chest_scene = preload("res://scenes/chest.tscn")
	var chest_instance = chest_scene.instantiate()
	get_tree().current_scene.add_child(chest_instance)
	
	chest_instance.global_position = position
	chest_instance.chest_id = chest_id
	chest_instance.chest_type = chest_type
	chest_instance.setup_chest(chest_types[chest_type])
	
	# Add to scene
	
	chest_spawned.emit(position, chest_type)

func attempt_open_chest(chest_id: int, player_steam_id: int) -> bool:
	if not active_chests.has(chest_id):
		return false
	
	var chest = active_chests[chest_id]
	if chest["opened"]:
		return false
	
	var chest_type = chest["type"]
	var cost = chest_types[chest_type]["cost"]
	
	# Get player stats
	var player_stats = get_tree().get_first_node_in_group("player_stats")
	if not player_stats:
		return false
	
	var player_coins = player_stats.get_player_coins(player_steam_id)
	
	# Check if player has enough coins
	if player_coins < cost:
		print("Player ", player_steam_id, " doesn't have enough coins (", player_coins, "/", cost, ")")
		return false
	
	# Handle mimic chest
	if chest_type == "mimic":
		handle_mimic_chest(chest_id, player_steam_id)
		return true
	
	# Deduct coins
	player_stats.add_coins(player_steam_id, -cost)
	
	# Generate rewards
	var rewards = generate_chest_rewards(chest_type)
	
	# Apply rewards
	apply_chest_rewards(rewards, player_steam_id)
	
	# Mark as opened
	chest["opened"] = true
	
	# Sync to all clients
	var open_data = {
		"message": "chest_opened",
		"chest_id": chest_id,
		"player_steam_id": player_steam_id,
		"rewards": rewards,
		"chest_type": chest_type
	}
	SteamManager.send_p2p_packet(0, open_data)
	
	chest_opened.emit(chest_type, rewards, player_steam_id)
	
	print("Player ", player_steam_id, " opened ", chest_type, " chest and got: ", rewards)
	return true

func handle_mimic_chest(chest_id: int, player_steam_id: int):
	print("MIMIC CHEST ACTIVATED! Player ", player_steam_id, " triggered a mimic!")
	
	var chest = active_chests[chest_id]
	var position = chest["position"]
	
	# Deal damage to player
	var player_stats = get_tree().get_first_node_in_group("player_stats")
	if player_stats:
		player_stats.damage_player(player_steam_id, chest_types["mimic"]["damage"])
	
	# Create explosion effect at chest position
	create_explosion_effect(Vector3(position[0], position[1], position[2]))
	
	# Mark as opened (destroyed)
	chest["opened"] = true
	
	# Sync mimic activation
	var mimic_data = {
		"message": "mimic_activated",
		"chest_id": chest_id,
		"player_steam_id": player_steam_id,
		"position": position
	}
	SteamManager.send_p2p_packet(0, mimic_data)

func generate_chest_rewards(chest_type: String) -> Array:
	var rewards = []
	var items = chest_types[chest_type]["items"]
	
	# Roll for each possible item
	for item in items:
		if randf() < item["chance"]:
			rewards.append(item.duplicate())
	
	# Ensure at least one reward
	if rewards.is_empty():
		rewards.append(items[0].duplicate())
	
	return rewards

func apply_chest_rewards(rewards: Array, player_steam_id: int):
	var player_stats = get_tree().get_first_node_in_group("player_stats")
	var inventory = get_tree().get_first_node_in_group("inventory_system")
	
	for reward in rewards:
		match reward["type"]:
			"coins":
				# Coins always work (no inventory needed)
				if player_stats:
					player_stats.add_coins(player_steam_id, reward["amount"])
					print("Gave ", reward["amount"], " coins to player ", player_steam_id)
			
			"health_potion", "word_gun", "blue_turtle_shell", "max_hp_boost":
				# Items need inventory space
				if inventory:
					var success = inventory.add_item(player_steam_id, reward["type"])
					if success:
						print("Gave ", reward["type"], " to player ", player_steam_id)
					else:
						print("Player ", player_steam_id, " inventory full! Couldn't give ", reward["type"])
						# Optionally: Give coins instead as compensation
						if player_stats:
							var compensation = get_item_coin_value(reward["type"])
							player_stats.add_coins(player_steam_id, compensation)
							print("Gave ", compensation, " coins instead (inventory full)")
			
			"full_heal":
				# Instant effects don't need inventory
				if player_stats:
					player_stats.player_stats[player_steam_id]["health"] = player_stats.max_health
					player_stats.player_health_changed.emit(player_steam_id, player_stats.max_health)
					player_stats.sync_player_stats(player_steam_id)
					print("Fully healed player ", player_steam_id)

func get_item_coin_value(item_type: String) -> int:
	# Compensation coins if inventory is full
	match item_type:
		"health_potion":
			return 8
		"word_gun":
			return 15
		"blue_turtle_shell":
			return 12
		"max_hp_boost":
			return 20
		_:
			return 5

func create_explosion_effect(position: Vector3):
	# Create visual explosion effect
	var main = get_node("/root/Main")
	if main and main.has_method("spawn_word_locally"):
		# Spawn explosion "words"
		main.spawn_word_locally("💥", position, 0.0)
		main.spawn_word_locally("BOOM", position + Vector3(1, 0, 0), 0.0)
	
	# Destroy terrain around the mimic
	var terrain_node = get_node("/root/Main/Terrain")
	if terrain_node:
		var voxel_tool = terrain_node.get_voxel_tool()
		voxel_tool.mode = VoxelTool.MODE_REMOVE
		voxel_tool.do_sphere(position, chest_types["mimic"]["explosion_radius"])

# Handle incoming chest messages
func handle_chest_spawned(chest_data: Dictionary):
	var chest_id = chest_data["chest_id"]
	var pos_array = chest_data["position"]
	var position = Vector3(pos_array[0], pos_array[1], pos_array[2])
	var chest_type = chest_data["chest_type"]
	
	active_chests[chest_id] = {
		"position": position,
		"type": chest_type,
		"discovered": false,
		"opened": false
	}
	
	spawn_chest_visual(chest_id, position, chest_type)

func handle_chest_opened(open_data: Dictionary):
	var chest_id = open_data["chest_id"]
	if active_chests.has(chest_id):
		active_chests[chest_id]["opened"] = true
	
	chest_opened.emit(open_data["chest_type"], open_data["rewards"], open_data["player_steam_id"])

func handle_mimic_activated(mimic_data: Dictionary):
	var pos_array = mimic_data["position"]
	var position = Vector3(pos_array[0], pos_array[1], pos_array[2])
	
	create_explosion_effect(position)
