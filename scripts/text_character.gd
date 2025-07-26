extends RigidBody3D


var broken = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await get_tree().create_timer(7).timeout
	self.queue_free()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_body_entered(body: Node) -> void:
	if broken:
		return
	if body.name == "Terrain":
		body.get_voxel_tool().do_sphere(global_position,3)
		broken=true
