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
	
	# Seed handling is now done by the main scene via Steam P2P
	# No need for complex seed synchronization logic here
	
	#get rid of mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Method called by main scene to set terrain seed
func set_terrain_seed(terrain_seed: int):
	seed = terrain_seed
	if voxel_terrain:
		voxel_terrain.generator.noise.seed = terrain_seed

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		return
	
	#if Input.is_action_just_pressed("dig"):
		#voxel_tool.mode = VoxelTool.MODE_REMOVE
		#voxel_tool.do_sphere($Head/Camera3D/Marker3D.global_position,2.0)
		#places_digged.append($Head/Camera3D/Marker3D.global_position)
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
	# As good practice, you should replace UI actions with custom gameplay actions.
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
	if !is_multiplayer_authority():
		return
	
	if Input.is_action_just_pressed("exit_mouse"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if Input.is_action_just_pressed("voice_record"):
		record_voice(true)
	elif Input.is_action_just_released("voice_record"):
		record_voice(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera_3d.rotate_x(-event.relative.y * SENSITIVITY)
		camera_3d.rotation.x = clamp(camera_3d.rotation.x,deg_to_rad(-90),deg_to_rad(90))

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		check_for_voice()

func record_voice(is_recording:bool) -> void:
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
