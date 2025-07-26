extends MultiplayerSpawner

@export var letter_scene: PackedScene

var letters = {}

func _ready() -> void:
	spawn_function = spawn_player

func spawn_player(data):
	var p = letter_scene.instantiate()
	return p

func kill_letter(letter):
	print("byeee")
	letter.queue_free()

# Updated to accept rotation parameter for synchronization
func print_3d(stri: String, loc: Vector3, rotation_y: float = 0.0) -> void:
	var i = 0
	var new_node = Node3D.new()
	add_child(new_node)
	for chr in stri:
		var txt = letter_scene.instantiate()
		new_node.add_child(txt)
		txt.get_node("MeshInstance3D").mesh.text = chr
		txt.global_position = Vector3(float(i) * 0.8, 0, 0)
		i += 1
	new_node.global_position = loc
	new_node.rotation.y = deg_to_rad(rotation_y)  # Use synchronized rotation
