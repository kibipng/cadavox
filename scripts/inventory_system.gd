# inventory_system.gd - SINGLE SLOT VERSION
extends Node

signal item_added(player_steam_id: int, item_type: String)
signal item_removed(player_steam_id: int, item_type: String)
signal item_used(player_steam_id: int, item_type: String)
signal inventory_full(player_steam_id: int, attempted_item: String)

# Player inventories - {steam_id: item_type} (only ONE item per player!)
var player_inventories = {}

# Item definitions
var item_definitions = {
	"word_gun": {
		"name": "Word Gun",
		"description": "Shoot letters from your words!",
		"usable": true,
		"permanent": true  # Doesn't get consumed on use
	},
	"blue_turtle_shell": {
		"name": "Blue Shell",
		"description": "Targets the richest player!",
		"usable": true,
		"permanent": false  # Gets consumed on use
	},
	"health_potion": {
		"name": "Health Potion", 
		"description": "Restores 25 HP",
		"usable": true,
		"permanent": false
	},
	"max_hp_boost": {
		"name": "Max HP Boost",
		"description": "Permanently increases max HP by 20",
		"usable": true,
		"permanent": false
	}
}

func _ready():
	add_to_group("inventory_system")

func add_item(steam_id: int, item_type: String) -> bool:
	# Check if player already has an item
	if player_inventories.has(steam_id) and player_inventories[steam_id] != "":
		print("Player ", steam_id, " inventory full! Has: ", player_inventories[steam_id], " | Tried to add: ", item_type)
		inventory_full.emit(steam_id, item_type)
		return false
	
	# Add the item
	player_inventories[steam_id] = item_type
	
	# Sync to all clients
	sync_inventory_change(steam_id, item_type)
	
	item_added.emit(steam_id, item_type)
	print("Added ", item_type, " to player ", steam_id, "'s inventory")
	return true

func remove_item(steam_id: int) -> String:
	var removed_item = ""
	
	if player_inventories.has(steam_id):
		removed_item = player_inventories[steam_id]
		player_inventories[steam_id] = ""
		
		# Sync to all clients
		sync_inventory_change(steam_id, "")
		
		item_removed.emit(steam_id, removed_item)
		print("Removed ", removed_item, " from player ", steam_id)
	
	return removed_item

func get_player_item(steam_id: int) -> String:
	if player_inventories.has(steam_id):
		return player_inventories[steam_id]
	return ""

func has_item(steam_id: int, item_type: String = "") -> bool:
	var current_item = get_player_item(steam_id)
	
	if item_type == "":
		# Check if player has ANY item
		return current_item != ""
	else:
		# Check for specific item
		return current_item == item_type

func use_item(steam_id: int) -> bool:
	var item_type = get_player_item(steam_id)
	
	if item_type == "":
		print("Player ", steam_id, " has no item to use!")
		return false
	
	print("Player ", steam_id, " using item: ", item_type)
	
	# Handle different item types
	var success = false
	match item_type:
		"word_gun":
			success = activate_word_gun(steam_id)
		"blue_turtle_shell":
			success = activate_blue_shell(steam_id)
		"health_potion":
			success = use_health_potion(steam_id)
		"max_hp_boost":
			success = use_max_hp_boost(steam_id)
		_:
			print("Unknown item type: ", item_type)
			return false
	
	if success:
		# Remove item if it's not permanent
		var item_def = item_definitions.get(item_type, {})
		if not item_def.get("permanent", false):
			remove_item(steam_id)
		
		item_used.emit(steam_id, item_type)
	
	return success

func drop_item(steam_id: int) -> bool:
	var dropped_item = remove_item(steam_id)
	
	if dropped_item != "":
		# Create dropped item in world (optional feature)
		create_dropped_item_pickup(steam_id, dropped_item)
		print("Player ", steam_id, " dropped: ", dropped_item)
		return true
	
	return false

func create_dropped_item_pickup(dropper_steam_id: int, item_type: String):
	# Find the player who dropped it
	for player in get_tree().get_nodes_in_group("players"):
		if player.steam_id == dropper_steam_id:
			var drop_position = player.global_position + Vector3(0, 1, 0)
			
			# Spawn a visual pickup (you'd create this scene)
			# var pickup_scene = preload("res://scenes/item_pickup.tscn")
			# var pickup = pickup_scene.instantiate()
			# pickup.setup_item(item_type, drop_position)
			# get_tree().current_scene.add_child(pickup)
			
			# For now, just spawn the item name as text
			var main = get_node("/root/Main")
			if main and main.has_method("spawn_word_locally"):
				main.spawn_word_locally(item_type.to_upper(), drop_position, 0.0)
			
			break

# Item usage functions
func activate_word_gun(steam_id: int) -> bool:
	print("Player ", steam_id, " activated word gun!")
	
	# Find the player and enable word gun mode
	for player in get_tree().get_nodes_in_group("players"):
		if player.steam_id == steam_id:
			if player.has_method("enable_word_gun_mode"):
				player.enable_word_gun_mode()
				return true
			break
	
	return false

func activate_blue_shell(steam_id: int) -> bool:
	print("Player ", steam_id, " used blue shell!")
	
	# Find the richest player
	var richest_player_id = find_richest_player(steam_id)
	if richest_player_id == -1:
		print("No valid target for blue shell")
		return false
	
	# Create blue shell projectile
	create_blue_shell_projectile(steam_id, richest_player_id)
	return true

func use_health_potion(steam_id: int) -> bool:
	print("Player ", steam_id, " used health potion!")
	
	var player_stats = get_tree().get_first_node_in_group("player_stats")
	if player_stats:
		var current_hp = player_stats.get_player_health(steam_id)
		var max_hp = player_stats.max_health
		
		# Don't use if already at full health
		if current_hp >= max_hp:
			print("Player already at full health!")
			return false
		
		var heal_amount = 25
		var new_hp = min(current_hp + heal_amount, max_hp)
		
		player_stats.player_stats[steam_id]["health"] = new_hp
		player_stats.player_health_changed.emit(steam_id, new_hp)
		player_stats.sync_player_stats(steam_id)
		
		return true
	
	return false

func use_max_hp_boost(steam_id: int) -> bool:
	print("Player ", steam_id, " used max HP boost!")
	
	var player_stats = get_tree().get_first_node_in_group("player_stats")
	if player_stats:
		# This would need to be implemented in player_stats_manager
		# For now, just heal to full and give temporary boost
		player_stats.player_stats[steam_id]["health"] = player_stats.max_health
		player_stats.player_health_changed.emit(steam_id, player_stats.max_health)
		player_stats.sync_player_stats(steam_id)
		
		return true
	
	return false

func find_richest_player(exclude_steam_id: int = -1) -> int:
	var player_stats = get_tree().get_first_node_in_group("player_stats")
	if not player_stats:
		return -1
	
	var richest_id = -1
	var most_coins = -1
	
	for steam_id in player_stats.player_stats.keys():
		if steam_id == exclude_steam_id:
			continue  # Don't target yourself
		
		var coins = player_stats.get_player_coins(steam_id)
		if coins > most_coins:
			most_coins = coins
			richest_id = steam_id
	
	return richest_id

func create_blue_shell_projectile(sender_id: int, target_id: int):
	# Find target player position
	var target_pos = Vector3.ZERO
	for player in get_tree().get_nodes_in_group("players"):
		if player.steam_id == target_id:
			target_pos = player.global_position
			break
	
	if target_pos == Vector3.ZERO:
		return
	
	# Find sender position
	var sender_pos = Vector3.ZERO
	for player in get_tree().get_nodes_in_group("players"):
		if player.steam_id == sender_id:
			sender_pos = player.global_position + Vector3(0, 10, 0)
			break
	
	# Create the blue shell projectile
	var shell_scene = preload("res://scenes/blue_shell.tscn")
	var shell_instance = shell_scene.instantiate()
	
	shell_instance.global_position = sender_pos
	shell_instance.target_position = target_pos
	shell_instance.target_steam_id = target_id
	shell_instance.sender_steam_id = sender_id
	
	get_tree().current_scene.add_child(shell_instance)
	
	# Sync to all clients
	var shell_data = {
		"message": "blue_shell_fired",
		"sender_id": sender_id,
		"target_id": target_id,
		"start_pos": [sender_pos.x, sender_pos.y, sender_pos.z],
		"target_pos": [target_pos.x, target_pos.y, target_pos.z]
	}
	SteamManager.send_p2p_packet(0, shell_data)

func sync_inventory_change(steam_id: int, item_type: String):
	var sync_data = {
		"message": "inventory_sync",
		"steam_id": steam_id,
		"item": item_type
	}
	SteamManager.send_p2p_packet(0, sync_data)

func handle_inventory_sync(sync_data: Dictionary):
	var steam_id = sync_data["steam_id"]
	var item = sync_data["item"]
	
	player_inventories[steam_id] = item
	
	if item != "":
		item_added.emit(steam_id, item)
	else:
		item_removed.emit(steam_id, "")

func handle_blue_shell_fired(shell_data: Dictionary):
	# Create blue shell on other clients
	var sender_id = shell_data["sender_id"]
	var target_id = shell_data["target_id"]
	var start_pos_array = shell_data["start_pos"]
	var target_pos_array = shell_data["target_pos"]
	
	var start_pos = Vector3(start_pos_array[0], start_pos_array[1], start_pos_array[2])
	var target_pos = Vector3(target_pos_array[0], target_pos_array[1], target_pos_array[2])
	
	var shell_scene = preload("res://scenes/blue_shell.tscn")
	var shell_instance = shell_scene.instantiate()
	
	shell_instance.global_position = start_pos
	shell_instance.target_position = target_pos
	shell_instance.target_steam_id = target_id
	shell_instance.sender_steam_id = sender_id
	
	get_tree().current_scene.add_child(shell_instance)

# Get all player inventories (for UI display)
func get_all_inventories() -> Dictionary:
	return player_inventories.duplicate()
