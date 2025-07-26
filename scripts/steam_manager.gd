extends Node

const PACKET_READ_LIMIT: int = 16  # Reduced from 32

var STEAM_APP_ID : int = 480
var STEAM_USERNAME : String = ""
var STEAM_ID : int = 0

var is_lobby_host : bool
var lobby_id : int
var lobby_members : Array

var peer : SteamMultiplayerPeer = SteamMultiplayerPeer.new()

# Very conservative packet management
var packet_queue: Array = []
var last_packet_time: float = 0.0
var packet_interval: float = 0.2  # Increased to 200ms between packets
var max_packet_size: int = 512    # Much smaller packets
var packets_sent_this_second: int = 0
var current_second: int = 0
var max_packets_per_second: int = 5  # Very conservative limit

# Separate queues with smaller limits
var voice_queue: Array = []
var data_queue: Array = []
var max_voice_queue_size: int = 3
var max_data_queue_size: int = 10

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
	
	# Add this to see packet send rate
	print("Packets sent this second: ", packets_sent_this_second, "/", max_packets_per_second)
	
	if lobby_id > 0:
		# Very conservative processing - only one type per frame
		if can_send_packet():
			if voice_queue.size() > 0:
				process_voice_queue()
			elif data_queue.size() > 0:
				process_data_queue()
		
		read_all_p2p_msg_packets()
		read_all_p2p_voice_packets()
	
	Steam.run_callbacks()

func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_id = this_lobby_id
		get_lobby_members()
		# Delay handshake to avoid immediate packet spam
		await get_tree().create_timer(0.5).timeout
		make_p2p_handshake()

func _on_p2p_session_request(remote_id: int):
	Steam.acceptP2PSessionWithUser(remote_id)

func make_p2p_handshake():
	send_p2p_packet(0, {"message": "handshake", "steam_id": STEAM_ID, "username": STEAM_USERNAME})

func send_voice_data(voice_data: PackedByteArray):
	# Skip voice if queue is full to prevent buildup
	if voice_queue.size() >= max_voice_queue_size:
		return
	
	queue_voice_packet({"voice_data": voice_data, "steam_id": STEAM_ID, "username": STEAM_USERNAME})

func queue_voice_packet(packet_data: Dictionary):
	var this_data: PackedByteArray = var_to_bytes(packet_data)
	
	if this_data.size() > max_packet_size:
		print("Voice packet too large, skipping")
		return
	
	voice_queue.append({
		"data": this_data,
		"timestamp": Time.get_unix_time_from_system()
	})

func process_voice_queue():
	if voice_queue.size() > 0:
		var packet = voice_queue.pop_front()
		send_voice_packet_immediate(packet.data)

func process_data_queue():
	var current_time = Time.get_unix_time_from_system()
	
	if current_time - last_packet_time >= packet_interval and data_queue.size() > 0:
		var packet = data_queue.pop_front()
		send_data_packet_immediate(packet.data)
		last_packet_time = current_time

func can_send_packet() -> bool:
	return packets_sent_this_second < max_packets_per_second

func send_p2p_packet(this_target: int, packet_data: Dictionary, send_type: int = 0):
	var this_data: PackedByteArray = var_to_bytes(packet_data)
	
	# Much stricter size checking
	if this_data.size() > max_packet_size:
		print("Packet too large (", this_data.size(), " bytes), dropping")
		return false
	
	# Drop packets if queue is full
	if data_queue.size() >= max_data_queue_size:
		print("Data queue full, dropping packet")
		data_queue.pop_front()  # Remove oldest
	
	data_queue.append({
		"data": this_data,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	return true

func send_voice_packet_immediate(packet_data: PackedByteArray) -> bool:
	if not can_send_packet():
		return false
	
	# Only send to one member at a time to reduce load
	if lobby_members.size() > 1:
		for member in lobby_members:
			if member["steam_id"] != STEAM_ID:
				var result = Steam.sendP2PPacket(member["steam_id"], packet_data, Steam.P2P_SEND_UNRELIABLE_NO_DELAY, 1)
				packets_sent_this_second += 1
				
				if not is_send_successful(result):
					print("Voice send failed: ", result)
				
				# Only send to first available member to reduce packet spam
				break
	
	return true

func send_data_packet_immediate(packet_data: PackedByteArray) -> bool:
	if not can_send_packet():
		return false
	
	var sent_successfully = false
	
	if lobby_members.size() > 1:
		for member in lobby_members:
			if member["steam_id"] != STEAM_ID:
				var result = Steam.sendP2PPacket(member["steam_id"], packet_data, Steam.P2P_SEND_RELIABLE, 0)
				
				if is_send_successful(result):
					sent_successfully = true
				else:
					print("Data send failed to ", member["steam_name"], ": ", result)
				
		packets_sent_this_second += 1
	
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
					
					if is_lobby_host and main_scene.terrain_seed != -1:
						# Delay seed broadcast to avoid packet collision
						await get_tree().create_timer(0.3).timeout
						main_scene.broadcast_terrain_seed()
				
				"terrain_seed":
					print("Terrain seed received: ", readable_data.get("seed", "Unknown"))
					main_scene.handle_terrain_seed(readable_data)
				
				"spawn_word":
					main_scene.handle_word_spawn(readable_data)
				
				"spawn_word_batch":
					main_scene.handle_word_batch_spawn(readable_data)
				
				"terrain_destruction":
					main_scene.handle_terrain_destruction(readable_data)

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
