extends MultiplayerSpawner

@export var letter_scene : PackedScene

var letters = {}

func _ready() -> void:
	spawn_function = spawn_player
		#call_deferred("spawn_host")

func spawn_host():
	if is_multiplayer_authority():
		spawn(1)

func spawn_player(data):
	var p = letter_scene.instantiate()
	return p

func kill_letter(letter):
	print("byeee")
	letter.queue_free()
