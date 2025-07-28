# letter_projectile.gd - Create this as a new script
extends RigidBody3D

var letter_text: String = "A"
var shooter_id: int = -1
var damage_amount: int = 15

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var timer: Timer = $Timer

func _ready():
	# Set up the letter mesh
	var text_mesh = TextMesh.new()
	text_mesh.text = letter_text
	text_mesh.font_size = 64
	text_mesh.depth = 0.1
	mesh_instance.mesh = text_mesh
	
	# Set up collision
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(0.5, 0.5, 0.2)
	collision_shape.shape = box_shape
	
	# Set projectile properties
	gravity_scale = 0.3  # Less gravity for projectiles
	
	# Self-destruct after 5 seconds
	timer.wait_time = 5.0
	timer.timeout.connect(_on_timer_timeout)
	timer.start()
	
	# Connect collision
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node):
	# Check if hit a player
	if body.is_in_group("players") and body.steam_id != shooter_id:
		# Deal damage
		var player_stats = get_tree().get_first_node_in_group("player_stats")
		if player_stats:
			player_stats.damage_player(body.steam_id, damage_amount)
			print("Letter projectile hit player ", body.steam_id, " for ", damage_amount, " damage!")
		
		# Destroy projectile
		queue_free()
	
	# Hit terrain or other objects - destroy
	elif not body.is_in_group("players"):
		queue_free()

func _on_timer_timeout():
	queue_free()
