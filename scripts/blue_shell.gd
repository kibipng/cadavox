# blue_shell.gd - Create this as a new script
extends RigidBody3D

var target_steam_id: int = -1
var launcher_steam_id: int = -1
var target_player: Node3D = null
var speed: float = 15.0
var damage_amount: int = 20
var homing_strength: float = 5.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var particles: GPUParticles3D = $TrailParticles
@onready var timer: Timer = $Timer

func _ready():
	# Load your custom blue shell mesh
	var shell_mesh = load("res://models/blue_shell.obj")  # Replace with your mesh path
	if shell_mesh:
		mesh_instance.mesh = shell_mesh
	else:
		# Fallback to basic shape
		var sphere = SphereMesh.new()
		sphere.radius = 0.3
		sphere.height = 0.6
		mesh_instance.mesh = sphere
		
		# Blue material
		var material = StandardMaterial3D.new()
		material.albedo_color = Color.BLUE
		material.emission_enabled = true
		material.emission = Color.CYAN * 0.3
		mesh_instance.material_override = material
	
	# Set up collision
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.3
	collision_shape.shape = sphere_shape
	
	# Physics properties
	gravity_scale = 0.1  # Floats in air
	
	# Find target player
	find_target_player()
	
	# Trail particles
	if particles:
		particles.emitting = true
	
	# Self-destruct after 15 seconds
	timer.wait_time = 15.0
	timer.timeout.connect(_on_timer_timeout)
	timer.start()
	
	# Connect collision
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if target_player and is_instance_valid(target_player):
		# Homing behavior
		var direction_to_target = (target_player.global_position - global_position).normalized()
		
		# Apply homing force
		var current_velocity = linear_velocity
		var desired_velocity = direction_to_target * speed
		var steering_force = (desired_velocity - current_velocity) * homing_strength * delta
		
		linear_velocity += steering_force
		linear_velocity = linear_velocity.normalized() * speed
		
		# Rotate to face movement direction
		if linear_velocity.length() > 0.1:
			look_at(global_position + linear_velocity.normalized(), Vector3.UP)
	else:
		# Target lost, try to find again
		find_target_player()

func find_target_player():
	for player in get_tree().get_nodes_in_group("players"):
		if player.steam_id == target_steam_id:
			target_player = player
			print("Blue shell locked onto target: ", player.player_name)
			return
	
	print("Blue shell target not found!")

func _on_body_entered(body: Node):
	# Check if hit the target player
	if body.is_in_group("players") and body.steam_id == target_steam_id:
		# Deal damage
		var player_stats = get_tree().get_first_node_in_group("player_stats")
		if player_stats:
			player_stats.damage_player(body.steam_id, damage_amount)
			print("Blue shell hit target for ", damage_amount, " damage!")
		
		# Explosion effect
		create_explosion_effect()
		
		# Destroy shell
		queue_free()
	
	# Hit wrong player or obstacle
	elif body.is_in_group("players"):
		# Still explode but less damage
		var player_stats = get_tree().get_first_node_in_group("player_stats")
		if player_stats:
			player_stats.damage_player(body.steam_id, damage_amount / 2)
			print("Blue shell hit wrong player for ", damage_amount / 2, " damage!")
		
		create_explosion_effect()
		queue_free()
	
	# Hit terrain - explode
	elif not body.is_in_group("players"):
		create_explosion_effect()
		queue_free()

func create_explosion_effect():
	# Create explosion particles/effects
	print("BOOM! Blue shell explosion!")
	
	# Spawn explosion word
	var main = get_node("/root/Main")
	if main and main.has_method("spawn_word_locally"):
		main.spawn_word_locally("BOOM!", global_position, 0.0)

func _on_timer_timeout():
	print("Blue shell timed out")
	queue_free()
