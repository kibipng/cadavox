extends MultiplayerSpawner

@export var letter_scene : PackedScene

var letters = {}

func _ready() -> void:
	spawn_function = spawn_player
		#call_deferred("spawn_host")

#func spawn_host():
	#if is_multiplayer_authority():
		#spawn(1)

func spawn_player(data):
	var p = letter_scene.instantiate()
	return p

func kill_letter(letter):
	print("byeee")
	letter.queue_free()

func print_3d(stri: String,loc: Vector3) -> void:
	if !is_multiplayer_authority():
		return
	var i = 0
	var new_node = Node3D.new()
	add_child(new_node)
	for chr in stri:
		var txt = letter_scene.instantiate()
		new_node.add_child(txt)
		txt.get_node("MeshInstance3D").mesh.text = chr
		txt.global_position=Vector3(float(i)*0.8,0,0)
		#txt.global_position.x-=(stri.length()/2.0+(i*(txt.get_node("MeshInstance3D").mesh.font_size)+0.25))
		i+=1
		#print("what",i)
	new_node.global_position = loc
	new_node.rotation.y = randf_range(-360,360)
