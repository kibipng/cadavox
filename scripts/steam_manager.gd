extends Node

const PACKET_READ_LIMIT: int = 32

var STEAM_APP_ID : int = 480
var STEAM_USERNAME : String = ""
var STEAM_ID : int = 0

var is_lobby_host : bool
var lobby_id : int
var lobby_members : Array

var peer : SteamMultiplayerPeer = SteamMultiplayerPeer.new()

# Packet optimization variables
var packet_queue: Array = []
var last_packet_time: float = 0.0
var packet_interval: float = 0.1  # Send packets every 100ms max
var max_packet_size: int = 1200   # Steam's recommended max packet size

func _init() -> void:
	OS.set_environment("SteamAppID", str(STEAM_APP_ID))
	OS.set_environment("SteamGameID", str(STEAM_APP_ID))

func _ready() -> void:
	Steam.steamInit()
	
	STEAM_ID = Steam.getSteamID()
	
	STEAM_USERNAME = Steam.getPersonaName()
	print(STEAM_USERNAME)
	
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.p2p_session_request.connect(_on_p2p_session_request)

func _process(delta: float) -> void:
	if lobby_id > 0:
		# Process packet queue first
		process_packet_queue()
		
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
	send_p2p_packet(1, {"voice_data": voice_data, "steam_id": STEAM_ID, "username": STEAM_USERNAME})

# Process packet queue with rate limiting
func process_packet_queue():
	var current_time = Time.get_unix_time_from_system()
	
	if current_time - last_packet_time >= packet_interval and packet_queue.size() > 0:
		var packet = packet_queue.pop_front()
		send_packet_immediate(packet.target, packet.data, packet.send_type, packet.channel)
		last_packet_time = current_time

# Modified send_p2p_packet function with rate limiting
func send_p2p_packet(this_target: int, packet_data: Dictionary, send_type: int = 0):
	var channel: int = 0
	
	var this_data: PackedByteArray
	this_data.append_array(var_to_bytes(packet_data))
	
	# Check packet size
	if this_data.size() > max_packet_size:
		print("Warning: Packet too large (", this_data.size(), " bytes), skipping")
		return false
	
	# Add to queue instead of sending immediately
	packet_queue.append({
		"target": this_target,
		"data": this_data,
		"send_type": send_type,
		"channel": channel
	})
	
	return true

func send_packet_immediate(this_target: int, this_data: PackedByteArray, send_type: int, channel: int):
	if this_target == 0:
		if lobby_members.size() > 1:
			for member in lobby_members:
				if member["steam_id"] != STEAM_ID:
					var result = Steam.sendP2PPacket(member["steam_id"], this_data, send_type, channel)
					if (typeof(result) == TYPE_BOOL and not result) or (typeof(result) == TYPE_INT and result != Steam.RESULT_OK):
						print("Failed to send P2P packet to ", member["steam_name"], " - Result: ", result)
	elif this_target == 1:
		if lobby_members.size() > 1:
			for member in lobby_members:
				if member["steam_id"] != STEAM_ID:
					var result = Steam.sendP2PPacket(member["steam_id"], this_data, send_type, 1)
					if (typeof(result) == TYPE_BOOL and not result) or (typeof(result) == TYPE_INT and result != Steam.RESULT_OK):
						print("Failed to send P2P packet to ", member["steam_name"], " - Result: ", result)
	else:
		var result = Steam.sendP2PPacket(this_target, this_data, send_type, channel)
		if result != Steam.RESULT_OK:
			print("Failed to send P2P packet to ", this_target, " - Result: ", result)

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
		var readable_data: Dictionary = bytes_to_var(packet_code)
		
		if readable_data.has("message"):
			# Get main scene reference once
			var main_scene = get_tree().get_first_node_in_group("main")
			if main_scene == null:
				main_scene = get_node("/root/Main")
			
			match readable_data["message"]:
				"handshake":
					print("PLAYER: ", readable_data["username"], " has joined!")
					get_lobby_members()
					
					# If we're the host and have a terrain seed, send it to the new player
					if is_lobby_host and main_scene != null and main_scene.terrain_seed != -1:
						main_scene.broadcast_terrain_seed()
				
				"terrain_seed":
					# Handle terrain seed messages
					print("Received terrain seed from ", readable_data["username"], ": ", readable_data["seed"])
					if main_scene != null:
						main_scene.handle_terrain_seed(readable_data)
				
				"spawn_word":
					# Handle word spawn messages
					print("Received word spawn from ", readable_data["username"], ": ", readable_data["word"])
					if main_scene != null:
						main_scene.handle_word_spawn(readable_data)
				
				"spawn_word_batch":
					# Handle batched word spawn messages
					print("Received word batch from ", readable_data["username"], " with ", readable_data["words"].size(), " words")
					if main_scene != null:
						main_scene.handle_word_batch_spawn(readable_data)
				
				"terrain_destruction":
					# Handle terrain destruction messages
					print("Received terrain destruction from ", readable_data["username"], " at position ", readable_data["position"])
					if main_scene != null:
						main_scene.handle_terrain_destruction(readable_data)

func read_p2p_voice_packet():
	var packet_size: int = Steam.getAvailableP2PPacketSize(1)
	if packet_size > 0:
		var this_packet: Dictionary = Steam.readP2PPacket(packet_size, 1)
		var packet_sender: int = this_packet["remote_steam_id"]
		var packet_code: PackedByteArray = this_packet["data"]
		var readable_data: Dictionary = bytes_to_var(packet_code)
		if readable_data.has("voice_data"):
			print("reading ", readable_data["username"], "'s voice data.")
			var players_in_scene: Array = get_tree().get_nodes_in_group("players")
			for player in players_in_scene:
				if player.steam_id == packet_sender:
					player.process_voice_data(readable_data, "network")
				else:
					pass
