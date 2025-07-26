extends MultiplayerSpawner

@export var letter_scene: PackedScene

var letters = {}
var next_letter_id = 0

func _ready() -> void:
	spawn_function = spawn_player

func spawn_player(data):
	var p = letter_scene.instantiate()
	# Set proper multiplayer authority
	if is_multiplayer_authority():
		p.set_multiplayer_authority(1)  # Server authority
	return p

func kill_letter(letter):
	print("byeee")
	if letter and is_instance_valid(letter):
		letter.safe_free()

# Updated to accept rotation parameter for synchronization
func print_3d(stri: String, loc: Vector3, rotation_y: float = 0.0) -> void:
	var i = 0
	var new_node = Node3D.new()
	new_node.name = "WordGroup_" + str(next_letter_id)
	next_letter_id += 1
	
	add_child(new_node)
	
	for chr in stri:
		var txt = letter_scene.instantiate()
		new_node.add_child(txt)
		
		# Set proper authority for each letter
		if is_multiplayer_authority():
			txt.set_multiplayer_authority(1)
		
		txt.get_node("MeshInstance3D").mesh.text = chr
		txt.global_position = Vector3(float(i) * 0.8, 0, 0)
		i += 1
	
	new_node.global_position = loc
	new_node.rotation.y = deg_to_rad(rotation_y)  # Use synchronized rotation
