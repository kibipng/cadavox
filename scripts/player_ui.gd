# player_ui.gd - FIXED VERSION with delayed initialization

extends Control

@onready var health_bar: ProgressBar = $StatsPanel/VBoxContainer/HealthBar
@onready var health_label: Label = $StatsPanel/VBoxContainer/HealthBar/HealthLabel
@onready var coins_label: Label = $StatsPanel/VBoxContainer/CoinsLabel
@onready var death_screen: Control = $DeathScreen

var player_stats_manager: Node
var my_steam_id: int

func _ready():
	print("PlayerUI: Starting _ready()")
	my_steam_id = SteamManager.STEAM_ID
	death_screen.visible = false
	
	# Wait for managers to be created, then initialize
	call_deferred("initialize_ui")

func initialize_ui():
	print("PlayerUI: Initializing UI (deferred)")
	
	# Try to find the manager (should exist now)
	player_stats_manager = get_tree().get_first_node_in_group("player_stats")
	
	print("PlayerUI: Found player_stats_manager: ", player_stats_manager != null)
	print("PlayerUI: My Steam ID: ", my_steam_id)
	
	if player_stats_manager:
		print("PlayerUI: Connecting signals...")
		player_stats_manager.player_health_changed.connect(_on_health_changed)
		player_stats_manager.player_coins_changed.connect(_on_coins_changed)
		player_stats_manager.player_died.connect(_on_player_died)
		player_stats_manager.player_revived.connect(_on_player_revived)
		print("PlayerUI: Signals connected!")
		
		# Initialize UI
		update_health_ui()
		update_coins_ui()
		print("PlayerUI: Setup complete")
	else:
		print("PlayerUI: ERROR - Still could not find player_stats_manager!")
		# Try again in a bit
		await get_tree().create_timer(0.1).timeout
		initialize_ui()

func _on_health_changed(steam_id: int, new_health: int):
	print("PlayerUI: Health changed for ", steam_id, " to ", new_health, " (my ID: ", my_steam_id, ")")
	if steam_id == my_steam_id:
		update_health_ui()

func _on_coins_changed(steam_id: int, new_coins: int):
	print("PlayerUI: Coins changed for ", steam_id, " to ", new_coins, " (my ID: ", my_steam_id, ")")
	if steam_id == my_steam_id:
		update_coins_ui()

func _on_player_died(steam_id: int):
	print("PlayerUI: Player died: ", steam_id, " (my ID: ", my_steam_id, ")")
	if steam_id == my_steam_id:
		death_screen.visible = true

func _on_player_revived(steam_id: int):
	print("PlayerUI: Player revived: ", steam_id, " (my ID: ", my_steam_id, ")")
	if steam_id == my_steam_id:
		death_screen.visible = false
		update_health_ui()

func update_health_ui():
	print("PlayerUI: Updating health UI...")
	if not player_stats_manager:
		print("PlayerUI: ERROR - No player_stats_manager in update_health_ui")
		return
	
	var health = player_stats_manager.get_player_health(my_steam_id)
	var max_health = player_stats_manager.max_health
	
	print("PlayerUI: Health: ", health, "/", max_health)
	
	health_bar.value = health
	health_bar.max_value = max_health
	health_label.text = "%d/%d" % [health, max_health]
	
	# Change color based on health
	if health < max_health * 0.25:
		health_bar.modulate = Color.RED
	elif health < max_health * 0.5:
		health_bar.modulate = Color.YELLOW
	else:
		health_bar.modulate = Color.GREEN
	
	print("PlayerUI: Health UI updated successfully")

func update_coins_ui():
	print("PlayerUI: Updating coins UI...")
	if not player_stats_manager:
		print("PlayerUI: ERROR - No player_stats_manager in update_coins_ui")
		return
	
	var coins = player_stats_manager.get_player_coins(my_steam_id)
	coins_label.text = "Coins: %d" % coins
	print("PlayerUI: Coins UI updated to: ", coins)
