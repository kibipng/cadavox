# blue_shell.gd - Homing projectile script
extends RigidBody3D

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape = $CollisionShape3D
@onready var trail_particles = $TrailParticles
@onready var explosion_area = $ExplosionArea

var target_position: Vector3
var target_steam_id: int
var sender_steam_id: int
var speed: float = 15.0
var homing_strength: float = 5.0
var max_lifetime: float = 20.0
var lifetime: float = 0.0

# Flight phases
enum FlightPhase { ASCENDING, HOMING, EXPLODING }
var current_phase = FlightPhase.ASCENDING
var ascend_height: float = 25.0
var has_exploded: bool = false

func _ready():
	# Set up the shell appearance
	setup_shell_visual()
	
	# Set up collision detection
	explosion_area.body_entered.connect(_on_explosion_area_entered)
	
	# Start ascending phase
	linear_velocity = Vector3(0, 10, 0)  # Go up first
	
	print("Blue shell created - targeting player ", target_steam_id)

func setup_shell_visual():
	# Create a blue shell-like appearance
	var shell_mesh = SphereMesh.new()
	shell_mesh.radius = 0.3
	shell_mesh.height = 0.6
	mesh_instance.mesh = shell_mesh
	
	# Blue material with glow
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.BLUE
	material.emission = Color.CYAN * 0.5
	material.metallic = 0.7
	material.roughness = 0.2
	mesh_instance.material_override = material
	
	# Set up collision
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.3
	collision_shape.shape = sphere_shape
	
	# Set up explosion area (larger)
	var explosion_collision = explosion_area.get_child(0)
	var explosion_shape = SphereShape3D.new()
	explosion_shape.radius = 2.0
	explosion_collision.shape = explosion_shape

func _physics_process(delta):
	lifetime += delta
	
	# Destroy after max lifetime
	if lifetime > max_lifetime:
		explode()
		return
	
	match current_phase:
		FlightPhase.ASCENDING:
			handle_ascending_phase(delta)
		FlightPhase.HOMING:
			handle_homing_phase(delta)

func handle_ascending_phase(delta):
	# Continue ascending until we reach desired height
	if global_position.y >= ascend_height:
		current_phase = FlightPhase.HOMING
		print("Blue shell entering homing phase")
		
		# Add some forward momentum toward general target area
		var direction_to_target = (target_position - global_position).normalized()
		linear_velocity = direction_to_target * speed + Vector3(0, 2, 0)

func handle_homing_phase(delta):
	# Update target position if player is still alive
	update_target_position()
	
	# Calculate homing direction
	var direction_to_target = (target_position - global_position).normalized()
	
	# Apply homing force
	var homing_force = direction_to_target * homing_strength - linear_velocity * 0.1
	apply_central_force(homing_force)
	
	# Limit speed
	if linear_velocity.length() > speed:
		linear_velocity = linear_velocity.normalized() * speed
	
	# Check if we're close to target
	var distance_to_target = global_position.distance_to(target_position)
	if distance_to_target < 3.0:
		explode()

func update_target_position():
	# Find the target player and update position
	for player in get_tree().get_nodes_in_group("players"):
		if player.steam_id == target_steam_id:
			target_position = player.global_position
			return
	
	# If target not found, keep current target position

func _on_explosion_area_entered(body: Node3D):
	if has_exploded:
		return
	
	# Check if we hit a player
	if body.is_in_group("players"):
		# Check if it's our target or close enough
		if body.steam_id == target_steam_id or global_position.distance_to(body.global_position) < 3.0:
			explode()

func explode():
	if has_exploded:
		return
	
	has_exploded = true
	current_phase = FlightPhase.EXPLODING
	
	print("Blue shell exploding at ", global_position)
	
	# Deal damage to nearby players
	damage_nearby_players()
	
	# Create explosion effects
	create_explosion_effects()
	
	# Destroy terrain
	destroy_terrain()
	
	# Sync explosion to other clients
	sync_explosion()
	
	# Remove the shell after effects
	await get_tree().create_timer(2.0).timeout
	queue_free()

func damage_nearby_players():
	var explosion_radius = 5.0
	var damage_amount = 35
	
	var player_stats = get_tree().get_first_node_in_group("player_stats")
	if not player_stats:
		return
	
	# Find all players within explosion radius
	for player in get_tree().get_nodes_in_group("players"):
		var distance = global_position.distance_to(player.global_position)
		if distance <= explosion_radius:
			# Scale damage by distance (closer = more damage)
			var scaled_damage = int(damage_amount * (1.0 - distance / explosion_radius))
			player_stats.damage_player(player.steam_id, scaled_damage)
			
			print("Blue shell damaged player ", player.steam_id, " for ", scaled_damage, " HP")

func create_explosion_effects():
	# Create visual explosion
	var main = get_node("/root/Main")
	if main and main.has_method("spawn_word_locally"):
		# Spawn explosion words
		main.spawn_word_locally("💥", global_position, 0.0)
		main.spawn_word_locally("BOOM", global_position + Vector3(1, 0, 0), 0.0)
		main.spawn_word_locally("SHELL", global_position + Vector3(-1, 0, 0), 0.0)
	
	# Change shell appearance to explosion
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	material.emission = Color.YELLOW
	mesh_instance.material_override = material
	
	# Scale up the shell briefly
	var tween = create_tween()
	tween.parallel().tween_property(self, "scale", Vector3(3, 3, 3), 0.3)
	tween.parallel().tween_property(mesh_instance, "transparency", 1.0, 1.0)

func destroy_terrain():
	# Destroy terrain in explosion radius
	var terrain = get_node("/root/Main/Terrain")
	if terrain:
		var voxel_tool = terrain.get_voxel_tool()
		voxel_tool.mode = VoxelTool.MODE_REMOVE
		voxel_tool.do_sphere(global_position, 4.0)

func sync_explosion():
	# Sync explosion to other clients
	var explosion_data = {
		"message": "blue_shell_exploded",
		"position": [global_position.x, global_position.y, global_position.z],
		"sender_id": sender_steam_id,
		"target_id": target_steam_id
	}
	SteamManager.send_p2p_packet(0, explosion_data)

# Handle explosion sync on other clients
func handle_explosion_sync(explosion_data: Dictionary):
	var pos_array = explosion_data["position"]
	var position = Vector3(pos_array[0], pos_array[1], pos_array[2])
	
	# Create explosion effects at the synced position
	create_explosion_effects_at_position(position)

func create_explosion_effects_at_position(position: Vector3):
	# Create visual effects for other clients
	var main = get_node("/root/Main")
	if main and main.has_method("spawn_word_locally"):
		main.spawn_word_locally("💥", position, 0.0)
		main.spawn_word_locally("BOOM", position + Vector3(1, 0, 0), 0.0)
	
	# Destroy terrain
	var terrain = get_node("/root/Main/Terrain")
	if terrain:
		var voxel_tool = terrain.get_voxel_tool()
		voxel_tool.mode = VoxelTool.MODE_REMOVE
		voxel_tool.do_sphere(position, 4.0)
