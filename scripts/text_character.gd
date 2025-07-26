extends RigidBody3D

var broken = false

@export var grass_mat : StandardMaterial3D
@export var grassy_dirt_mat : StandardMaterial3D
@export var dirt_mat : StandardMaterial3D
@export var aerial_rocks_mat : StandardMaterial3D
@export var stone_mat : StandardMaterial3D

func _on_timer_timeout() -> void:
	self.queue_free()

func _on_area_3d_body_entered(body: Node3D) -> void:
	if broken:
		return
	if body.name == "Terrain":
		# Only the authority (original spawner) should handle terrain destruction
		# to prevent duplicate destruction calls
		if is_multiplayer_authority():
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
	
	# Also apply locally
	apply_terrain_destruction(pos, 3.0)

func apply_terrain_destruction(pos: Vector3, radius: float):
	var terrain = get_node("/root/Main/Terrain")
	if terrain:
		var voxel_tool = terrain.get_voxel_tool()
		voxel_tool.mode = VoxelTool.MODE_REMOVE
		voxel_tool.do_sphere(pos, radius)
