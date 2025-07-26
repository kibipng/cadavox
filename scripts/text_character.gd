extends RigidBody3D


var broken = false

#func _on_body_entered(body: Node) -> void:
	#
#
#
##func _on_body_shape_entered(body_rid: RID, body: Node, body_shape_index: int, local_shape_index: int) -> void:
	##


func _on_timer_timeout() -> void:
	self.queue_free()


func _on_area_3d_body_entered(body: Node3D) -> void:
	if broken:
		return
	if body.name == "Terrain":
		var i = body.get_voxel_tool()
		i.mode = VoxelTool.MODE_REMOVE
		i.do_sphere(global_position,3)
		print("poops :DD")
		broken=true
		$Timer.start()
