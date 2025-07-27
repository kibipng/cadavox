extends RigidBody3D

var broken = false
var spawner_id: int = -1
var is_being_freed = false

@export var grass_mat : StandardMaterial3D
@export var grassy_dirt_mat : StandardMaterial3D
@export var dirt_mat : StandardMaterial3D
@export var aerial_rocks_mat : StandardMaterial3D
@export var stone_mat : StandardMaterial3D

func _ready():
	# Set the spawner ID to the current player's Steam ID
	spawner_id = SteamManager.STEAM_ID

func _on_timer_timeout() -> void:
	safe_free()

func _on_area_3d_body_entered(body: Node3D) -> void:
	if broken or is_being_freed:
		return
	
	# Check if hit a player and deal damage
	if body.is_in_group("players"):
		var player_stats = get_tree().get_first_node_in_group("player_stats")
		if player_stats:
			player_stats.damage_player(body.steam_id, 20)  # Deal 20 damage
		
		# Mark as broken and start cleanup timer
		broken = true
		$Timer.start()
		return
	
	# Original terrain collision code
	if body.name == "Terrain":
		# Only the original spawner should handle terrain destruction
		if spawner_id == SteamManager.STEAM_ID:
			destroy_terrain_at_position(global_position)
		
		broken = true
		$Timer.start()

func destroy_terrain_at_position(pos: Vector3):
	# Send terrain destruction data via Steam P2P
	var destruction_data = {
		"message": "terrain_destruction",
		"position": [pos.x, pos.y, pos.z],
		"radius": 3.0,
		"steam_id": SteamManager.STEAM_ID,
		"username": SteamManager.STEAM_USERNAME
	}
	SteamManager.send_p2p_packet(0, destruction_data)
	
	# Also apply locally immediately for responsiveness
	apply_terrain_destruction(pos, 3.0)

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
