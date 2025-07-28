extends Node

const PACKET_READ_LIMIT: int = 16

var STEAM_APP_ID : int = 480
var STEAM_USERNAME : String = ""
var STEAM_ID : int = 0

var is_lobby_host : bool
var lobby_id : int
var lobby_members : Array

var peer : SteamMultiplayerPeer = SteamMultiplayerPeer.new()

# Separate rate limiting for different packet types
var voice_queue: Array = []
var data_queue: Array = []

# Voice packets - more frequent for real-time audio
var voice_last_send_time: float = 0.0
var voice_send_interval: float = 0.05  # 50ms for voice (20 FPS)
var max_voice_queue_size: int = 3

# Data packets - less frequent for game state
var data_last_send_time: float = 0.0
var data_send_interval: float = 0.2   # 200ms for data packets
var max_data_queue_size: int = 10

# Player movement packets - EXCLUDED from rate limiting
var movement_packets_this_second: int = 0
var movement_second_counter: int = 0
var max_movement_packets_per_second: int = 60  # Allow high frequency for smooth movement

# General packet limiting
var general_packets_this_second: int = 0
var general_second_counter: int = 0
var max_general_packets_per_second: int = 10

var max_packet_size: int = 512

func _init() -> void:
	OS.set_environment("SteamAppID", str(STEAM_APP_ID))
	OS.set_environment("SteamGameID", str(STEAM_APP_ID))

func _ready() -> void:
	Steam.steamInit()
	
	STEAM_ID = Steam.getSteamID()
	STEAM_USERNAME = Steam.getPersonaName()
	print("Steam initialized for: ", STEAM_USERNAME)
	
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.p2p_session_request.connect(_on_p2p_session_request)

func _process(delta: float) -> void:
	var current_time = Time.get_unix_time_from_system()
	var current_time_second = int(current_time)
	
	# Reset counters every second
	if current_time_second != movement_second_counter:
		movement_second_counter = current_time_second
		movement_packets_this_second = 0
	
	if current_time_second != general_second_counter:
		general_second_counter = current_time_second
		general_packets_this_second = 0
	
	if lobby_id > 0:
		# Process voice packets more frequently
		if current_time - voice_last_send_time >= voice_send_interval and voice_queue.size() > 0:
			process_voice_queue()
			voice_last_send_time = current_time
		
		# Process data packets less frequently
		if current_time - data_last_send_time >= data_send_interval and data_queue.size() > 0:
			if can_send_general_packet():
				process_data_queue()
				data_last_send_time = current_time
		
		read_all_p2p_msg_packets()
		read_all_p2p_voice_packets()
	
	Steam.run_callbacks()

func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_id = this_lobby_id
		get_lobby_members()
		# Small delay for handshake
		await get_tree().create_timer(0.1).timeout
		make_p2p_handshake()

func _on_p2p_session_request(remote_id: int):
	Steam.acceptP2PSessionWithUser(remote_id)

func make_p2p_handshake():
	send_p2p_packet(0, {"message": "handshake", "steam_id": STEAM_ID, "username": STEAM_USERNAME})

func send_voice_data(voice_data: PackedByteArray):
	if voice_queue.size() >= max_voice_queue_size:
		voice_queue.pop_front()  # Remove oldest instead of skipping
	
	queue_voice_packet({"voice_data": voice_data, "steam_id": STEAM_ID, "username": STEAM_USERNAME})

# Special function for movement packets - bypasses general rate limiting
func send_movement_packet(packet_data: Dictionary) -> bool:
	if movement_packets_this_second >= max_movement_packets_per_second:
		return false
	
	var this_data: PackedByteArray = var_to_bytes(packet_data)
	if this_data.size() > max_packet_size:
		return false
	
	var success = send_packet_immediate(this_data, Steam.P2P_SEND_UNRELIABLE_NO_DELAY, 0)
	if success:
		movement_packets_this_second += 1
	return success

func can_send_general_packet() -> bool:
	return general_packets_this_second < max_general_packets_per_second

func queue_voice_packet(packet_data: Dictionary):
	var this_data: PackedByteArray = var_to_bytes(packet_data)
	
	if this_data.size() > max_packet_size:
		return
	
	voice_queue.append({
		"data": this_data,
		"timestamp": Time.get_unix_time_from_system()
	})

func process_voice_queue():
	if voice_queue.size() > 0:
		var packet = voice_queue.pop_front()
		send_packet_immediate(packet.data, Steam.P2P_SEND_UNRELIABLE_NO_DELAY, 1)

func process_data_queue():
	if data_queue.size() > 0:
		var packet = data_queue.pop_front()
		var success = send_packet_immediate(packet.data, Steam.P2P_SEND_RELIABLE, 0)
		if success:
			general_packets_this_second += 1

func send_p2p_packet(this_target: int, packet_data: Dictionary, send_type: int = 0):
	var this_data: PackedByteArray = var_to_bytes(packet_data)
	
	if this_data.size() > max_packet_size:
		print("Packet too large (", this_data.size(), " bytes), dropping")
		return false
	
	# Check if this is a terrain seed packet - send immediately with high priority
	if packet_data.has("message") and packet_data["message"] == "terrain_seed":
		return send_packet_immediate(this_data, Steam.P2P_SEND_RELIABLE, 0)
	
	# Queue other data packets
	if data_queue.size() >= max_data_queue_size:
		data_queue.pop_front()  # Remove oldest
	
	data_queue.append({
		"data": this_data,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	return true

func send_packet_immediate(packet_data: PackedByteArray, send_type: int, channel: int) -> bool:
	var sent_successfully = false
	
	if lobby_members.size() > 1:
		for member in lobby_members:
			if member["steam_id"] != STEAM_ID:
				var result = Steam.sendP2PPacket(member["steam_id"], packet_data, send_type, channel)
				
				if is_send_successful(result):
					sent_successfully = true
				else:
					print("Send failed to ", member["steam_name"], ": ", result)
	
	return sent_successfully

func is_send_successful(result) -> bool:
	if typeof(result) == TYPE_BOOL:
		return result
	elif typeof(result) == TYPE_INT:
		return result == Steam.RESULT_OK
	else:
		return false

func get_lobby_members():
	lobby_members.clear()
	
	var num_of_lobby_members: int = Steam.getNumLobbyMembers(lobby_id)
	
	for member in range(0, num_of_lobby_members):
		var member_steam_id: int = Steam.getLobbyMemberByIndex(lobby_id, member)
		var member_steam_name: String = Steam.getFriendPersonaName(member_steam_id)
		
		lobby_members.append({
			"steam_id": member_steam_id,
			"steam_name": member_steam_name
		})

func read_all_p2p_msg_packets(read_count: int = 0):
	if read_count >= PACKET_READ_LIMIT:
		return
	
	if Steam.getAvailableP2PPacketSize() > 0:
		read_p2p_msg_packet()
		read_all_p2p_msg_packets(read_count + 1)

func read_all_p2p_voice_packets(read_count: int = 0):
	if read_count >= PACKET_READ_LIMIT:
		return
	
	if Steam.getAvailableP2PPacketSize(1) > 0:
		read_p2p_voice_packet()
		read_all_p2p_voice_packets(read_count + 1)

func read_p2p_msg_packet():
	var packet_size: int = Steam.getAvailableP2PPacketSize(0)
	if packet_size > 0:
		var this_packet: Dictionary = Steam.readP2PPacket(packet_size, 0)
		var packet_sender: int = this_packet["remote_steam_id"]
		var packet_code: PackedByteArray = this_packet["data"]
		
		var result = bytes_to_var(packet_code)
		if not result is Dictionary:
			return
		
		var readable_data: Dictionary = result
		
		if readable_data.has("message"):
			var main_scene = get_tree().get_first_node_in_group("main")
			if main_scene == null:
				main_scene = get_node("/root/Main")
			
			if main_scene == null:
				return
			
			match readable_data["message"]:
				"handshake":
					print("PLAYER: ", readable_data.get("username", "Unknown"), " joined!")
					get_lobby_members()
					
					# Send terrain seed immediately to new player if we're host
					if is_lobby_host and main_scene.terrain_seed != -1:
						print("Sending terrain seed to new player: ", readable_data.get("username", "Unknown"))
						# Send directly to this player
						var seed_data = {
							"message": "terrain_seed",
							"seed": main_scene.terrain_seed,
							"steam_id": STEAM_ID,
							"username": STEAM_USERNAME
						}
						var seed_packet = var_to_bytes(seed_data)
						Steam.sendP2PPacket(packet_sender, seed_packet, Steam.P2P_SEND_RELIABLE, 0)
				
				"terrain_seed":
					print("Terrain seed received: ", readable_data.get("seed", "Unknown"), " from ", readable_data.get("username", "Unknown"))
					main_scene.handle_terrain_seed(readable_data)
				
				"spawn_word":
					main_scene.handle_word_spawn(readable_data)
				
				"spawn_word_batch":
					main_scene.handle_word_batch_spawn(readable_data)
				
				"terrain_destruction":
					main_scene.handle_terrain_destruction(readable_data)
				
				"challenge_start":
					if main_scene.has_method("handle_challenge_start"):
						main_scene.handle_challenge_start(readable_data)
				
				"challenge_end":
					if main_scene.has_method("handle_challenge_end"):
						main_scene.handle_challenge_end(readable_data)
				
				"counting_progress":
					if main_scene.has_method("handle_counting_progress"):
						main_scene.handle_counting_progress(readable_data)
				
				"player_stats_sync":
					if main_scene.has_method("handle_player_stats_sync"):
						main_scene.handle_player_stats_sync(readable_data)
				
				"chest_spawn":
					if main_scene.has_method("handle_chest_spawn"):
						main_scene.handle_chest_spawn(readable_data)
					
				"chest_opened":
					if main_scene.has_method("handle_chest_opened"):
						main_scene.handle_chest_opened(readable_data)

func read_p2p_voice_packet():
	var packet_size: int = Steam.getAvailableP2PPacketSize(1)
	if packet_size > 0:
		var this_packet: Dictionary = Steam.readP2PPacket(packet_size, 1)
		var packet_sender: int = this_packet["remote_steam_id"]
		var packet_code: PackedByteArray = this_packet["data"]
		
		var result = bytes_to_var(packet_code)
		if not result is Dictionary:
			return
			
		var readable_data: Dictionary = result
		if readable_data.has("voice_data"):
			var players_in_scene: Array = get_tree().get_nodes_in_group("players")
			for player in players_in_scene:
				if player.steam_id == packet_sender:
					player.process_voice_data(readable_data, "network")
					break
