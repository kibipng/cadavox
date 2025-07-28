# treasure_chest.gd
extends StaticBody3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var cost_label: Label3D = $CostLabel
#@onready var glow_light: OmniLight3D = $GlowLight
#@onready var particles: GPUParticles3D = $OpenParticles

# Chest properties
var chest_id: int = -1
var chest_type: String = "common"
var unlock_cost: int = 10
var is_opened: bool = false
var chest_manager: Node

# Player interaction
var nearby_players: Array = []

func _ready():
	add_to_group("treasure_chests")
	
	# Connect interaction area
	interaction_area.body_entered.connect(_on_player_entered)
	interaction_area.body_exited.connect(_on_player_exited)
	
	# Setup visual appearance based on chest type
	setup_chest_appearance()
	
	# Update cost label
	cost_label.text = str(unlock_cost) + " coins"

func setup_chest_appearance():
	# Create chest mesh (simple box for now, you can replace with a proper model)
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1.5, 1.0, 1.0)
	mesh_instance.mesh = box_mesh
	
	# Create material based on chest type
	var material = StandardMaterial3D.new()
	
	match chest_type:
		"common":
			material.albedo_color = Color.SADDLE_BROWN
			#glow_light.light_color = Color.ORANGE
		"rare":
			material.albedo_color = Color.STEEL_BLUE
			material.metallic = 0.7
			#glow_light.light_color = Color.CYAN
		"legendary":
			material.albedo_color = Color.GOLD
			material.metallic = 0.9
			material.roughness = 0.1
			#glow_light.light_color = Color.YELLOW
	
	# Add emission for magical glow
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.3
	
	mesh_instance.material_override = material
	
	# Setup collision
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1.5, 1.0, 1.0)
	collision_shape.shape = box_shape

func _on_player_entered(body: Node3D):
	if body.is_in_group("players") and not is_opened:
		nearby_players.append(body)
		# Show interaction prompt (you could add a UI element here)
		print("Press E to open chest for ", unlock_cost, " coins")

func _on_player_exited(body: Node3D):
	if body in nearby_players:
		nearby_players.erase(body)

func _input(event):
	if event.is_action_pressed("interact") and nearby_players.size() > 0 and not is_opened:
		# Find the local player
		var local_player = null
		for player in nearby_players:
			if player.is_multiplayer_authority():
				local_player = player
				break
		
		if local_player and chest_manager:
			attempt_open_chest(local_player.steam_id)

func attempt_open_chest(player_steam_id: int):
	if chest_manager and chest_manager.attempt_open_chest(chest_id, player_steam_id):
		# Success! Chest opened
		set_opened_state()
		play_open_animation()
	else:
		# Failed - not enough coins or other issue
		play_error_feedback()

func set_opened_state():
	is_opened = true
	
	# Change appearance to opened chest
	var material = mesh_instance.material_override.duplicate()
	material.albedo_color = material.albedo_color.darkened(0.5)
	material.emission = Color.BLACK
	mesh_instance.material_override = material
	
	# Hide cost label
	cost_label.visible = false
	
	# Dim the glow
	#glow_light.light_energy = 0.1

func play_open_animation():
	# Simple scale animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Scale up briefly then back down
	tween.tween_property(self, "scale", Vector3(1.2, 1.2, 1.2), 0.2)
	tween.tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.3).set_delay(0.2)
	
	# Spin the chest
	tween.tween_property(self, "rotation:y", rotation.y + PI * 2, 0.5)
	
	# Play particles
	#if particles:
		#particles.emitting = true

func play_error_feedback():
	# Red flash to indicate insufficient coins
	#var original_color = glow_light.light_color
	#glow_light.light_color = Color.RED
	
	# Flash back to original color
	#await get_tree().create_timer(0.2).timeout
	#glow_light.light_color = original_color
	
	# Shake animation
	var tween = create_tween()
	var original_pos = global_position
	tween.tween_method(shake_chest, 0.0, 1.0, 0.3)

func shake_chest(progress: float):
	var shake_strength = 0.1 * sin(progress * PI * 8) * (1.0 - progress)
	global_position.x += randf_range(-shake_strength, shake_strength)
	global_position.z += randf_range(-shake_strength, shake_strength)
