# challenge_manager.gd
extends Node

signal challenge_started(challenge_data: Dictionary)
signal challenge_ended()
signal player_failed_challenge(player_steam_id: int)

# Challenge timing
var challenge_duration: float = 30.0
var time_between_challenges: float = 45.0
var challenge_timer: float = 0.0
var between_challenges_timer: float = 0.0
var current_challenge: Dictionary = {}
var is_challenge_active: bool = false

# Challenge definitions
var available_challenges = [
	{
		"id": "first_to_die",
		"name": "First to Die Wins!",
		"description": "First player to die gets 10 coins and revives!",
		"type": "special",
		"validation_func": "handle_first_to_die"
	},
	{
		"id": "no_long_words",
		"name": "Short Words Only!",
		"description": "No words longer than 4 letters",
		"type": "word_filter", 
		"validation_func": "validate_short_words"
	},
	{
		"id": "must_contain_letter",
		"name": "Letter Hunt!",
		"description": "All words must contain: %s",
		"type": "word_filter",
		"validation_func": "validate_contains_letter",
		"random_letter": true
	},
	{
		"id": "starts_with_letter",
		"name": "Letter Start!",
		"description": "All words must start with: %s",
		"type": "word_filter",
		"validation_func": "validate_starts_with",
		"random_letter": true
	},
	{
		"id": "count_to_20",
		"name": "Count Together!",
		"description": "All players count to 20 together",
		"type": "special",
		"validation_func": "handle_counting"
	}
]

# Counting challenge state
var current_count = 0
var target_count = 20
var players_who_counted = []

# Player tracking
var failed_players = []
var player_stats_manager: Node

func _ready():
	add_to_group("challenge_manager")
	between_challenges_timer = time_between_challenges
	
	# Get player stats manager
	player_stats_manager = get_tree().get_first_node_in_group("player_stats")
	if player_stats_manager:
		player_stats_manager.player_died.connect(_on_player_died)

func _process(delta):
	if SteamManager.is_lobby_host:  # Only host manages challenges
		if is_challenge_active:
			challenge_timer -= delta
			if challenge_timer <= 0:
				end_challenge()
		else:
			between_challenges_timer -= delta
			if between_challenges_timer <= 0:
				start_random_challenge()

func start_random_challenge():
	var challenge = available_challenges[randi() % available_challenges.size()].duplicate()
	
	# Add random letter if needed
	if challenge.get("random_letter", false):
		var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		var random_letter = letters[randi() % letters.length()]
		challenge["letter"] = random_letter
		challenge["description"] = challenge["description"] % random_letter
	
	current_challenge = challenge
	is_challenge_active = true
	challenge_timer = challenge_duration
	failed_players.clear()
	
	# Reset counting state
	current_count = 0
	players_who_counted.clear()
	
	# Send via SteamManager (following your existing pattern)
	var packet_data = {
		"message": "challenge_start",
		"challenge": challenge,
		"duration": challenge_duration
	}
	SteamManager.send_p2p_packet(0, packet_data)
	
	# Trigger locally
	challenge_started.emit(challenge)
	print("Challenge started: ", challenge["name"])

func end_challenge():
	is_challenge_active = false
	between_challenges_timer = time_between_challenges
	
	# Handle challenge-specific endings
	match current_challenge.get("id", ""):
		"count_to_20":
			if current_count >= target_count:
				reward_all_players(5)  # Everyone gets 5 coins for completing count
			else:
				punish_failed_players()
		"first_to_die":
			pass  # Already handled when someone dies
		_:
			punish_failed_players()
	
	# Send end message
	var packet_data = {
		"message": "challenge_end"
	}
	SteamManager.send_p2p_packet(0, packet_data)
	
	challenge_ended.emit()
	current_challenge.clear()
	failed_players.clear()
	print("Challenge ended")

# Called by Main.gd when SteamManager receives challenge messages
func handle_challenge_start(challenge_data: Dictionary):
	current_challenge = challenge_data["challenge"]
	is_challenge_active = true
	challenge_timer = challenge_data["duration"]
	failed_players.clear()
	
	# Reset counting state
	current_count = 0
	players_who_counted.clear()
	
	challenge_started.emit(current_challenge)
	print("Received challenge: ", current_challenge["name"])

func handle_challenge_end():
	is_challenge_active = false
	current_challenge.clear()
	failed_players.clear()
	current_count = 0
	players_who_counted.clear()
	challenge_ended.emit()
	print("Challenge ended")

func handle_counting_progress(progress_data: Dictionary):
	current_count = progress_data["current_count"]

# WORD VALIDATION
func validate_word(word: String, player_steam_id: int) -> bool:
	if not is_challenge_active:
		return true
	
	var challenge_id = current_challenge.get("id", "")
	
	match challenge_id:
		"no_long_words":
			return validate_short_words(word, player_steam_id)
		"must_contain_letter":
			return validate_contains_letter(word, player_steam_id)
		"starts_with_letter":
			return validate_starts_with(word, player_steam_id)
		"count_to_20":
			return handle_counting_word(word, player_steam_id)
		"first_to_die":
			return true  # No word restrictions for this challenge
		_:
			return true

func validate_short_words(word: String, player_steam_id: int) -> bool:
	var is_valid = word.length() <= 4
	if not is_valid and not failed_players.has(player_steam_id):
		failed_players.append(player_steam_id)
		player_failed_challenge.emit(player_steam_id)
	return is_valid

func validate_contains_letter(word: String, player_steam_id: int) -> bool:
	var required_letter = current_challenge.get("letter", "A").to_lower()
	var is_valid = word.to_lower().contains(required_letter)
	if not is_valid and not failed_players.has(player_steam_id):
		failed_players.append(player_steam_id)
		player_failed_challenge.emit(player_steam_id)
	return is_valid

func validate_starts_with(word: String, player_steam_id: int) -> bool:
	var required_letter = current_challenge.get("letter", "A")
	var is_valid = word.to_upper().begins_with(required_letter)
	if not is_valid and not failed_players.has(player_steam_id):
		failed_players.append(player_steam_id)
		player_failed_challenge.emit(player_steam_id)
	return is_valid

func handle_counting_word(word: String, player_steam_id: int) -> bool:
	# Check if the word is the next number in sequence
	var expected_number = str(current_count + 1)
	
	if word == expected_number:
		current_count += 1
		players_who_counted.append(player_steam_id)
		
		# Sync counting progress
		sync_counting_progress()
		
		# Check if we completed the count
		if current_count >= target_count:
			# Success! End challenge early
			call_deferred("end_challenge")
		
		return true
	
	# Wrong number - this player fails
	if not failed_players.has(player_steam_id):
		failed_players.append(player_steam_id)
		player_failed_challenge.emit(player_steam_id)
	
	return false

func sync_counting_progress():
	var sync_data = {
		"message": "counting_progress",
		"current_count": current_count
	}
	SteamManager.send_p2p_packet(0, sync_data)

# PLAYER DEATH HANDLING
func _on_player_died(steam_id: int):
	if not is_challenge_active or current_challenge.get("id") != "first_to_die":
		return
	
	# First person to die wins!
	if player_stats_manager:
		player_stats_manager.add_coins(steam_id, 10)
		player_stats_manager.revive_player(steam_id)
	
	print("Player ", steam_id, " won first-to-die challenge!")
	
	# End the challenge
	call_deferred("end_challenge")

# PUNISHMENT AND REWARDS
func punish_failed_players():
	if not player_stats_manager:
		return
	
	for steam_id in failed_players:
		# Damage failed players
		player_stats_manager.damage_player(steam_id, 25)
		
		# Also spawn a bomb for visual effect
		spawn_punishment_bomb(steam_id)

func reward_all_players(coin_amount: int):
	if not player_stats_manager:
		return
	
	for player in get_tree().get_nodes_in_group("players"):
		player_stats_manager.add_coins(player.steam_id, coin_amount)

func spawn_punishment_bomb(player_steam_id: int):
	for player in get_tree().get_nodes_in_group("players"):
		if player.steam_id == player_steam_id:
			var bomb_pos = player.global_position + Vector3(0, 5, 0)
			var main = get_node("/root/Main")
			if main and main.has_method("spawn_word_locally"):
				main.spawn_word_locally("💣", bomb_pos, 0.0)
			break

func get_current_challenge() -> Dictionary:
	return current_challenge

func is_challenge_running() -> bool:
	return is_challenge_active

func get_counting_progress() -> int:
	return current_count
