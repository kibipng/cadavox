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
const JUMP_VELOCITY = 9.0 #4.5
const GRAVITY = 19 #9.8
const SENSITIVITY = 0.015

#bob variables
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
var t_bob = 0.0

#fov variables
const BASE_FOV = 75.0 #75
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
		# Disable movement and hide player
		set_physics_process(false)
		visible = false

func _on_player_revived(revived_steam_id: int):
	if revived_steam_id == steam_id:
		is_dead = false
		# Re-enable movement and show player
		set_physics_process(true)
		visible = true

# Method called by main scene to set terrain seed
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
	
	# FALL DAMAGE CHECK - AFTER move_and_slide()
	handle_fall_damage(delta)

func handle_fall_damage(delta):
	# Simple logic: if we're on the ground and weren't falling, we're safe
	if is_on_floor():
		if is_falling:
			# We just landed!
			var fall_distance = fall_start_y - global_position.y
			print(">>> LANDED! Fell ", fall_distance, " meters")
			
			if fall_distance > FALL_DAMAGE_THRESHOLD:
				var damage = int((fall_distance - FALL_DAMAGE_THRESHOLD) * FALL_DAMAGE_MULTIPLIER)
				print(">>> FALL DAMAGE: ", damage, " HP")
				
				if player_stats_manager:
					player_stats_manager.damage_player(steam_id, damage)
				
				add_fall_damage_effect(damage,delta)
			else:
				print(">>> Safe landing")
			
			# Reset
			is_falling = false
			fall_start_y = 0.0
	else:
		# We're in the air
		if not is_falling and velocity.y < -2.0:  # Only start tracking if falling fast enough
			# Start tracking the fall
			is_falling = true
			fall_start_y = global_position.y
			print(">>> Started falling from ", fall_start_y)

# Also add this debug version of add_fall_damage_effect:
func add_fall_damage_effect(damage: int,delta):
	print("OUCH! Took ", damage, " fall damage!")
	
	# Much more noticeable camera shake
	var original_pos = camera_3d.transform.origin
	var shake_strength = min(damage * 0.01, 0.3)  # Stronger shake, capped at 0.3
	var shake_duration = min(damage * 0.05, 1.0)  # Longer shake for more damage
	var shake_frequency = 0.01  # Faster shaking
	
	print(">>> Screen shake - strength: ", shake_strength, " duration: ", shake_duration)
	
	# Create a more intense shake effect
	var shake_timer = 0.0
	while shake_timer < shake_duration:
		# Random shake in all directions
		var shake_offset = Vector3(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength * 0.5, shake_strength * 0.5)  # Less Z-axis shake
		)
		
		camera_3d.transform.origin = original_pos + shake_offset #lerp(camera_3d.transform.origin, original_pos + shake_offset,delta*20)
		
		await get_tree().create_timer(shake_frequency).timeout
		shake_timer += shake_frequency
		
		# Gradually reduce shake intensity
		shake_strength *= 0.95
	
	# Reset camera position smoothly
	camera_3d.transform.origin = original_pos
	print(">>> Screen shake complete")


func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ/2) * BOB_AMP
	return pos

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
		
		# Process in chunks of 2 bytes (16-bit samples)
		for i in range(0, min(frames_available * 2, voice_buffer.size() - 1), 2):
			if i + 1 >= voice_buffer.size():
				break
				
			# Extract 16-bit sample from two bytes
			var raw_value: int = voice_buffer[i] | (voice_buffer[i + 1] << 8)
			raw_value = (raw_value + 32768) & 0xffff
			var amplitude: float = float(raw_value - 32768) / 32768.0
			
			# Push frame to audio buffer
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

# Optional: Add this function if you want to connect the player hitbox signal
func _on_player_hitbox_body_entered(body: Node3D) -> void:
	# Only process hits for our own player (multiplayer authority)
	if not is_multiplayer_authority():
		return
	
	# Check if it's a falling word that hit us
	if body.is_in_group("text_characters") or body.has_method("safe_free"):
		# Get player stats manager
		var player_stats = get_tree().get_first_node_in_group("player_stats")
		if player_stats:
			# Deal 20 damage to this player
			player_stats.damage_player(steam_id, 20)
			print("Player ", steam_id, " hit by word for 20 damage!")
		
		# The word will handle its own cleanup in text_character.gd
