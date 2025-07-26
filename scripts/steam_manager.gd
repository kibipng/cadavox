extends Node

const PACKET_READ_LIMIT: int = 32

var STEAM_APP_ID : int = 480
var STEAM_USERNAME : String = ""
var STEAM_ID : int = 0

var is_lobby_host : bool
var lobby_id : int
var lobby_members : Array

var peer : SteamMultiplayerPeer = SteamMultiplayerPeer.new()

# Enhanced packet optimization variables
var packet_queue: Array = []
var last_packet_time: float = 0.0
var packet_interval: float = 0.05  # Reduced to 50ms for better responsiveness
var max_packet_size: int = 800     # Reduced from 1200 to be safer
var packets_sent_this_second: int = 0
var current_second: int = 0
var max_packets_per_second: int = 20  # Steam's typical limit

# Separate queues for different packet types
var voice_queue: Array = []
var data_queue: Array = []

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
	# Reset packet counter every second
	var current_time_second = int(Time.get_unix_time_from_system())
	if current_time_second != current_second:
		current_second = current_time_second
		packets_sent_this_second = 0
	
	if lobby_id > 0:
		# Process packet queues with priority (voice first, then data)
		process_voice_queue()
		process_data_queue()
		
		read_all_p2p_msg_packets()
		read_all_p2p_voice_packets()
	
	Steam.run_callbacks()

func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_id = this_lobby_id
		get_lobby_members()
		make_p2p_handshake()

func _on_p2p_session_request(remote_id: int):
	Steam.acceptP2PSessionWithUser(remote_id)

func make_p2p_handshake():
	send_p2p_packet(0, {"message": "handshake", "steam_id": STEAM_ID, "username": STEAM_USERNAME})

func send_voice_data(voice_data: PackedByteArray):
	# Voice data gets priority queue
	queue_voice_packet({"voice_data": voice_data, "steam_id": STEAM_ID, "username": STEAM_USERNAME})

func queue_voice_packet(packet_data: Dictionary):
	var this_data: PackedByteArray = var_to_bytes(packet_data)
	
	if this_data.size() > max_packet_size:
		print("Warning: Voice packet too large (", this_data.size(), " bytes), skipping")
		return
	
	voice_queue.append({
		"data": this_data,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	# Keep voice queue from getting too large
	if voice_queue.size() > 10:
		voice_queue.pop_front()

func process_voice_queue():
	var current_time = Time.get_unix_time_from_system()
	
	if voice_queue.size() > 0 and can_send_packet():
		var packet = voice_queue.pop_front()
		send_voice_packet_immediate(packet.data)

func process_data_queue():
	var current_time = Time.get_unix_time_from_system()
	
	if current_time - last_packet_time >= packet_interval and data_queue.size() > 0 and can_send_packet():
		var packet = data_queue.pop_front()
		send_data_packet_immediate(packet.data)
		last_packet_time = current_time

func can_send_packet() -> bool:
	return packets_sent_this_second < max_packets_per_second

func send_p2p_packet(this_target: int, packet_data: Dictionary, send_type: int = 0):
	var this_data: PackedByteArray = var_to_bytes(packet_data)
	
	# Check packet size
	if this_data.size() > max_packet_size:
		print("Warning: Packet too large (", this_data.size(), " bytes), splitting or skipping")
		# For large packets, you might want to implement packet splitting here
		return false
	
	# Add to appropriate queue
	data_queue.append({
		"data": this_data,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	# Keep data queue reasonable size
	if data_queue.size() > 50:
		data_queue.pop_front()  # Remove oldest packet if queue is full
	
	return true

func send_voice_packet_immediate(packet_data: PackedByteArray):
	if not can_send_packet():
		return false
	
	var success_count = 0
	var total_attempts = 0
	
	if lobby_members.size() > 1:
		for member in lobby_members:
			if member["steam_id"] != STEAM_ID:
				total_attempts += 1
				var result = Steam.sendP2PPacket(member["steam_id"], packet_data, Steam.P2P_SEND_UNRELIABLE_NO_DELAY, 1)
				
				if is_send_successful(result):
					success_count += 1
				else:
					print("Failed to send voice packet to ", member["steam_name"], " - Result: ", result)
	
	if total_attempts > 0:
		packets_sent_this_second += 1
	
	return success_count == total_attempts

func send_data_packet_immediate(packet_data: PackedByteArray):
	if not can_send_packet():
		return false
	
	var success_count = 0
	var total_attempts = 0
	
	if lobby_members.size() > 1:
		for member in lobby_members:
			if member["steam_id"] != STEAM_ID:
				total_attempts += 1
				var result = Steam.sendP2PPacket(member["steam_id"], packet_data, Steam.P2P_SEND_RELIABLE, 0)
				
				if is_send_successful(result):
					success_count += 1
				else:
					print("Failed to send data packet to ", member["steam_name"], " - Result: ", result)
	
	if total_attempts > 0:
		packets_sent_this_second += 1
	
	return success_count == total_attempts

func is_send_successful(result) -> bool:
	# Handle both boolean and integer return types
	if typeof(result) == TYPE_BOOL:
		return result
	elif typeof(result) == TYPE_INT:
		return result == Steam.RESULT_OK
	else:
		print("Unknown result type: ", typeof(result))
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
		
		# Add error handling for packet deserialization
		var readable_data: Dictionary
		var error = false
		
		# Try to deserialize the packet
		var result = bytes_to_var(packet_code)
		if result is Dictionary:
			readable_data = result
		else:
			print("Failed to deserialize packet from ", packet_sender)
			error = true
		
		if not error and readable_data.has("message"):
			var main_scene = get_tree().get_first_node_in_group("main")
			if main_scene == null:
				main_scene = get_node("/root/Main")
			
			match readable_data["message"]:
				"handshake":
					print("PLAYER: ", readable_data.get("username", "Unknown"), " has joined!")
					get_lobby_members()
					
					if is_lobby_host and main_scene != null and main_scene.terrain_seed != -1:
						main_scene.broadcast_terrain_seed()
				
				"terrain_seed":
					print("Received terrain seed from ", readable_data.get("username", "Unknown"), ": ", readable_data.get("seed", "Unknown"))
					if main_scene != null:
						main_scene.handle_terrain_seed(readable_data)
				
				"spawn_word":
					if main_scene != null:
						main_scene.handle_word_spawn(readable_data)
				
				"spawn_word_batch":
					if main_scene != null:
						main_scene.handle_word_batch_spawn(readable_data)
				
				"terrain_destruction":
					if main_scene != null:
						main_scene.handle_terrain_destruction(readable_data)

func read_p2p_voice_packet():
	var packet_size: int = Steam.getAvailableP2PPacketSize(1)
	if packet_size > 0:
		var this_packet: Dictionary = Steam.readP2PPacket(packet_size, 1)
		var packet_sender: int = this_packet["remote_steam_id"]
		var packet_code: PackedByteArray = this_packet["data"]
		
		var result = bytes_to_var(packet_code)
		if result is Dictionary:
			var readable_data: Dictionary = result
			if readable_data.has("voice_data"):
				var players_in_scene: Array = get_tree().get_nodes_in_group("players")
				for player in players_in_scene:
					if player.steam_id == packet_sender:
						player.process_voice_data(readable_data, "network")
						break
