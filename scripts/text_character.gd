extends RigidBody3D

var broken = false
var spawner_id: int = -1
var is_being_freed = false

# Word gun bullet properties
var is_word_gun_bullet: bool = false
var bullet_velocity: Vector3 = Vector3.ZERO

@export var grass_mat : StandardMaterial3D
@export var grassy_dirt_mat : StandardMaterial3D
@export var dirt_mat : StandardMaterial3D
@export var aerial_rocks_mat : StandardMaterial3D
@export var stone_mat : StandardMaterial3D

func _ready():
	spawner_id = SteamManager.STEAM_ID
	add_to_group("text_characters")

func set_as_word_gun_bullet(velocity: Vector3):
	is_word_gun_bullet = true
	bullet_velocity = velocity
	
	# Make it faster and less affected by gravity
	set_gravity_scale(0.3) 
	
	# Set initial velocity
	linear_velocity = velocity
	
	print("Created word gun bullet with velocity: ", velocity)

func _on_timer_timeout() -> void:
	safe_free()

func _on_area_3d_body_entered(body: Node3D) -> void:
	if broken or is_being_freed:
		return
	
	# Handle player collision
	if body.is_in_group("players"):
		var damage = 20 if not is_word_gun_bullet else 15  # Word gun bullets do less damage
		var player_stats = get_tree().get_first_node_in_group("player_stats")
		if player_stats:
			player_stats.damage_player(body.steam_id, damage)
		
		broken = true
		$Timer.start()
		return
	
	# Handle terrain collision
	if body.name == "Terrain":
		if spawner_id == SteamManager.STEAM_ID:
			var radius = 3.0 if not is_word_gun_bullet else 1.5  # Smaller craters for bullets
			destroy_terrain_at_position(global_position, radius)
		
		broken = true
		$Timer.start()

func destroy_terrain_at_position(pos: Vector3, radius: float = 3.0):
	var destruction_data = {
		"message": "terrain_destruction",
		"position": [pos.x, pos.y, pos.z],
		"radius": radius,
		"steam_id": SteamManager.STEAM_ID,
		"username": SteamManager.STEAM_USERNAME
	}
	SteamManager.send_p2p_packet(0, destruction_data)
	
	apply_terrain_destruction(pos, radius)

func apply_terrain_destruction(pos: Vector3, radius: float):
	var terrain = get_node("/root/Main/Terrain")
	if terrain:
		var voxel_tool = terrain.get_voxel_tool()
		voxel_tool.mode = VoxelTool.MODE_REMOVE
		voxel_tool.do_sphere(pos, radius)

func safe_free():
	if is_being_freed:
		return
	
	is_being_freed = true
	call_deferred("queue_free")
