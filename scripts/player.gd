extends CharacterBody3D

#voxel
var main 
var voxel_terrain : VoxelTerrain
var voxel_tool : VoxelTool
const VOXEL_VIEWER = preload("res://scenes/voxel_viewer.tscn")

@onready var head = $Head
@onready var camera_3d : Camera3D = $Head/Camera3D
@export var player_name : String = "kris deltarune"
var steam_id : int = 0
@onready var player_name_label: Label3D = $PlayerNameLabel

@onready var prox_network: AudioStreamPlayer3D = $ProxNetwork
@onready var prox_local: AudioStreamPlayer3D = $ProxLocal
@export var seed : int = -1

var current_sample_rate: int = 48000
var has_loopback: bool = true
var local_playback: AudioStreamGeneratorPlayback = null
var local_voice_buffer: PackedByteArray = PackedByteArray()
var network_playback: AudioStreamGeneratorPlayback = null
var network_voice_buffer: PackedByteArray = PackedByteArray()
var packet_read_limit: int = 5

var speed 
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 9.0
const GRAVITY = 19
const SENSITIVITY = 0.015

#bob variables
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
var t_bob = 0.0

#fov variables
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5

@export var spawn_text = [["pp",Vector3(0,0,0)]]
@export var instanced_alr = ["pp"]

# Challenge and stats tracking
var challenge_manager: Node
var player_stats_manager: Node
var is_dead: bool = false

# Fall damage system
var fall_start_y: float = 0.0
var is_falling: bool = false
const FALL_DAMAGE_THRESHOLD: float = 10.0
const FALL_DAMAGE_MULTIPLIER: float = 2.0

# Word gun system
var word_gun_system: Node

func _ready() -> void:
	main=get_node("/root/Main/")
	
	voxel_terrain=get_node("/root/Main/Terrain")
	voxel_tool=voxel_terrain.get_voxel_tool()
	
	prox_local.stream.mix_rate=current_sample_rate
	prox_local.play()
	local_playback = prox_local.get_stream_playback()
	
	prox_network.stream.mix_rate=current_sample_rate
	prox_network.play()
	network_playback = prox_network.get_stream_playback()
	
	add_to_group("players")
	
	if is_multiplayer_authority():
		camera_3d.set_current(true)
		player_name = SteamManager.STEAM_USERNAME
		steam_id = SteamManager.STEAM_ID
		main.main_player = self
	else:
		steam_id = multiplayer.multiplayer_peer.get_steam64_from_peer_id(get_multiplayer_authority())
		player_name = Steam.getFriendPersonaName(steam_id)
		player_name_label.text = player_name    
	
	# Get references to managers
	challenge_manager = get_tree().get_first_node_in_group("challenge_manager")
	player_stats_manager = get_tree().get_first_node_in_group("player_stats")
	
	# Initialize word gun system
	word_gun_system = preload("res://scripts/word_gun.gd").new()
	add_child(word_gun_system)
	word_gun_system.name = "WordGunSystem"
	
	# Initialize player stats
	if player_stats_manager and is_multiplayer_authority():
		player_stats_manager.initialize_player(steam_id)
	
	# Connect to death/revive signals
	if player_stats_manager:
		player_stats_manager.player_died.connect(_on_player_died)
		player_stats_manager.player_revived.connect(_on_player_revived)
	
	#get rid of mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_player_died(died_steam_id: int):
	if died_steam_id == steam_id:
		is_dead = true
		set_physics_process(false)
		visible = false

func _on_player_revived(revived_steam_id: int):
	if revived_steam_id == steam_id:
		is_dead = false
		set_physics_process(true)
		visible = true

func set_terrain_seed(terrain_seed: int):
	seed = terrain_seed
	if voxel_terrain:
		voxel_terrain.generator.noise.seed = terrain_seed

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority() or is_dead:
		return
	
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	# handle sprint
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x,direction.x*speed,delta*7.0)
			velocity.z = lerp(velocity.z,direction.z*speed,delta*7.0)
	else:
		velocity.x = lerp(velocity.x,direction.x*speed,delta*3.0)
		velocity.z = lerp(velocity.z,direction.z*speed,delta*3.0)
	
	#head bob
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera_3d.transform.origin = _headbob(t_bob)
	
	# FOV
	var velocity_clamped = clamp(velocity.length(),0.5,SPRINT_SPEED*2)
	var target_fov = BASE_FOV+FOV_CHANGE*velocity_clamped
	camera_3d.fov = lerp(camera_3d.fov,target_fov,delta*9.0)
	
	move_and_slide()
	
	# FALL DAMAGE CHECK
	handle_fall_damage()

func handle_fall_damage():
	if is_on_floor():
		if is_falling:
			var fall_distance = fall_start_y - global_position.y
			print(">>> LANDED! Fell ", fall_distance, " meters")
			
			if fall_distance > FALL_DAMAGE_THRESHOLD:
				var damage = int((fall_distance - FALL_DAMAGE_THRESHOLD) * FALL_DAMAGE_MULTIPLIER)
				print(">>> FALL DAMAGE: ", damage, " HP")
				
				if player_stats_manager:
					player_stats_manager.damage_player(steam_id, damage)
				
				add_fall_damage_effect(damage)
			
			is_falling = false
			fall_start_y = 0.0
	else:
		if not is_falling and velocity.y < -2.0:
			is_falling = true
			fall_start_y = global_position.y
			print(">>> Started falling from ", fall_start_y)

func add_fall_damage_effect(damage: int):
	print("OUCH! Took ", damage, " fall damage!")
	
	var original_pos = camera_3d.transform.origin
	var shake_strength = min(damage * 0.02, 0.3)
	var shake_duration = min(damage * 0.05, 1.0)
	var shake_frequency = 0.03
	
	var shake_timer = 0.0
	while shake_timer < shake_duration:
		var shake_offset = Vector3(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength * 0.5, shake_strength * 0.5)
		)
		
		camera_3d.transform.origin = original_pos + shake_offset
		
		await get_tree().create_timer(shake_frequency).timeout
		shake_timer += shake_frequency
		shake_strength *= 0.95
	
	camera_3d.transform.origin = original_pos

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ/2) * BOB_AMP
	return pos

# WORD GUN FUNCTIONS
func enable_word_gun_mode():
	if word_gun_system:
		word_gun_system.enable_word_gun_mode()

func load_word_gun_ammo(word: String):
	if word_gun_system:
		word_gun_system.load_word_ammo(word)

func process_voice_data(voice_data:Dictionary, voice_source:String) -> void:
	get_sample_rate()
	
	var decompressed_voice:Dictionary
	if voice_source == "local":
		decompressed_voice = Steam.decompressVoice(voice_data['buffer'], current_sample_rate)
	elif voice_source == "network":
		decompressed_voice = Steam.decompressVoice(voice_data['voice_data'], current_sample_rate)
	
	if decompressed_voice['result'] == Steam.VOICE_RESULT_OK and decompressed_voice['uncompressed'].size() > 0:
		var playback_to_use = local_playback if voice_source == "local" else network_playback
		var voice_buffer = decompressed_voice['uncompressed']
		voice_buffer.resize(decompressed_voice['size'])
		
		var frames_available = playback_to_use.get_frames_available()
		
		for i in range(0, min(frames_available * 2, voice_buffer.size() - 1), 2):
			if i + 1 >= voice_buffer.size():
				break
				
			var raw_value: int = voice_buffer[i] | (voice_buffer[i + 1] << 8)
			raw_value = (raw_value + 32768) & 0xffff
			var amplitude: float = float(raw_value - 32768) / 32768.0
			
			playback_to_use.push_frame(Vector2(amplitude, amplitude))

func _input(event: InputEvent) -> void:
	if !is_multiplayer_authority() or is_dead:
		return
	
	if event is InputEventMouseMotion and !is_dead and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera_3d.rotate_x(-event.relative.y * SENSITIVITY)
		camera_3d.rotation.x = clamp(camera_3d.rotation.x,deg_to_rad(-90),deg_to_rad(90))
	
	if Input.is_action_just_pressed("exit_mouse"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if Input.is_action_just_pressed("voice_record"):
		record_voice(true)
	elif Input.is_action_just_released("voice_record"):
		record_voice(false)
	
	# WORD GUN CONTROLS
	if Input.is_action_just_pressed("fire") and word_gun_system:  # Left click
		word_gun_system.fire_word_gun()
	
	if Input.is_action_just_pressed("toggle_word_gun"):  # G key
		var inventory = get_tree().get_first_node_in_group("inventory_system")
		if inventory and inventory.has_item(steam_id, "word_gun"):
			if word_gun_system.word_gun_active:
				word_gun_system.disable_word_gun_mode()
			else:
				word_gun_system.enable_word_gun_mode()
	
	# INVENTORY CONTROLS
	if Input.is_action_just_pressed("use_item"):  # 1 key
		var inventory = get_tree().get_first_node_in_group("inventory_system")
		if inventory:
			inventory.use_item(steam_id)
	
	if Input.is_action_just_pressed("drop_item"):  # Q key
		var inventory = get_tree().get_first_node_in_group("inventory_system")
		if inventory:
			inventory.drop_item(steam_id)

func _process(delta: float) -> void:
	if is_multiplayer_authority() and !is_dead:
		check_for_voice()

func record_voice(is_recording:bool) -> void:
	if is_dead:
		return
		
	Steam.setInGameVoiceSpeaking(SteamManager.STEAM_ID,is_recording)
	
	if is_recording:
		Steam.startVoiceRecording()
	else:
		Steam.stopVoiceRecording()

func check_for_voice() -> void:
	var available_voice : Dictionary = Steam.getAvailableVoice()
	if available_voice['result'] == Steam.VOICE_RESULT_OK and available_voice['buffer'] > 0:
		var voice_data:Dictionary = Steam.getVoice()
		if voice_data['result'] == Steam.VOICE_RESULT_OK:
			SteamManager.send_voice_data(voice_data['buffer'])
			
			if has_loopback:
				process_voice_data(voice_data,"local")

func get_sample_rate(is_toggled:bool = true) -> void:
	if is_toggled:
		current_sample_rate = Steam.getVoiceOptimalSampleRate()
	else:
		current_sample_rate = 48000
	prox_network.stream.mix_rate = current_sample_rate
	prox_local.stream.mix_rate = current_sample_rate

func _on_player_hitbox_body_entered(body: Node3D) -> void:
	if not is_multiplayer_authority():
		return
	
	if body.is_in_group("text_characters") or body.has_method("safe_free"):
		var player_stats = get_tree().get_first_node_in_group("player_stats")
		if player_stats:
			player_stats.damage_player(steam_id, 20)
			print("Player ", steam_id, " hit by word for 20 damage!")
