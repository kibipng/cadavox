# player_stats_manager.gd
extends Node

signal player_health_changed(steam_id: int, new_health: int)
signal player_coins_changed(steam_id: int, new_coins: int)
signal player_died(steam_id: int)
signal player_revived(steam_id: int)

# Player stats dictionary - {steam_id: {health: int, coins: int, is_dead: bool}}
var player_stats = {}
var max_health = 100

func _ready():
	add_to_group("player_stats")

# Initialize player stats when they join
func initialize_player(steam_id: int):
	player_stats[steam_id] = {
		"health": max_health,
		"coins": 10000,
		"is_dead": false
	}
	
	# Sync to all clients
	sync_player_stats(steam_id)

# Damage a player
func damage_player(steam_id: int, damage: int):
	if not player_stats.has(steam_id) or player_stats[steam_id]["is_dead"]:
		return
	
	player_stats[steam_id]["health"] -= damage
	player_stats[steam_id]["health"] = max(0, player_stats[steam_id]["health"])
	
	player_health_changed.emit(steam_id, player_stats[steam_id]["health"])
	
	# Check if player died
	if player_stats[steam_id]["health"] <= 0:
		kill_player(steam_id)
	
	# Sync to all clients
	sync_player_stats(steam_id)

# Kill a player
func kill_player(steam_id: int):
	if not player_stats.has(steam_id):
		return
	
	player_stats[steam_id]["health"] = 0
	player_stats[steam_id]["is_dead"] = true
	
	player_died.emit(steam_id)
	sync_player_stats(steam_id)

# Revive a player
func revive_player(steam_id: int):
	if not player_stats.has(steam_id):
		return
	
	player_stats[steam_id]["health"] = max_health
	player_stats[steam_id]["is_dead"] = false
	
	player_revived.emit(steam_id)
	sync_player_stats(steam_id)

# Add coins to a player
func add_coins(steam_id: int, amount: int):
	if not player_stats.has(steam_id):
		initialize_player(steam_id)
	
	player_stats[steam_id]["coins"] += amount
	player_coins_changed.emit(steam_id, player_stats[steam_id]["coins"])
	
	# Sync to all clients
	sync_player_stats(steam_id)

# Get player stats
func get_player_health(steam_id: int) -> int:
	if player_stats.has(steam_id):
		return player_stats[steam_id]["health"]
	return max_health

func get_player_coins(steam_id: int) -> int:
	if player_stats.has(steam_id):
		return player_stats[steam_id]["coins"]
	return 0

func is_player_dead(steam_id: int) -> bool:
	if player_stats.has(steam_id):
		return player_stats[steam_id]["is_dead"]
	return false

# Sync player stats across all clients
func sync_player_stats(steam_id: int):
	if not player_stats.has(steam_id):
		return
	
	var sync_data = {
		"message": "player_stats_sync",
		"target_steam_id": steam_id,
		"health": player_stats[steam_id]["health"],
		"coins": player_stats[steam_id]["coins"],
		"is_dead": player_stats[steam_id]["is_dead"]
	}
	
	SteamManager.send_p2p_packet(0, sync_data)

func heal_player(steam_id: int, heal_amount: int):
	if not player_stats.has(steam_id) or player_stats[steam_id]["is_dead"]:
		return
	
	player_stats[steam_id]["health"] += heal_amount
	player_stats[steam_id]["health"] = min(player_stats[steam_id]["health"], max_health)
	
	player_health_changed.emit(steam_id, player_stats[steam_id]["health"])
	sync_player_stats(steam_id)

# Handle incoming player stats sync (called by Main.gd)
func handle_stats_sync(sync_data: Dictionary):
	var target_steam_id = sync_data["target_steam_id"]
	
	if not player_stats.has(target_steam_id):
		player_stats[target_steam_id] = {}
	
	player_stats[target_steam_id]["health"] = sync_data["health"]
	player_stats[target_steam_id]["coins"] = sync_data["coins"]
	player_stats[target_steam_id]["is_dead"] = sync_data["is_dead"]
	
	# Emit signals for UI updates
	player_health_changed.emit(target_steam_id, sync_data["health"])
	player_coins_changed.emit(target_steam_id, sync_data["coins"])
