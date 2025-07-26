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
		var i = body.get_voxel_tool()
		i.mode = VoxelTool.MODE_REMOVE
		i.do_sphere(global_position,3)
		i.mode = VoxelTool.MODE_TEXTURE_PAINT
		#i.paint
		
		
		broken=true
		$Timer.start()
		
