# chest.gd - ENHANCED VERSION with custom meshes and floating text
extends StaticBody3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var cost_label: Label3D = $FloatingText

var chest_id: int = -1
var chest_type: String = ""
var cost: int = 0
var is_opened: bool = false
var is_near_player: bool = false

func _ready():
	# Connect interaction
	interaction_area.body_entered.connect(_on_interaction_area_entered)
	interaction_area.body_exited.connect(_on_interaction_area_exited)
	
	# Hide floating text initially
	cost_label.visible = false

func setup_chest(chest_properties: Dictionary):
	cost = chest_properties["cost"]
	
	# Load custom mesh if available
	var mesh_path = chest_properties.get("mesh_path", "")
	if mesh_path != "" and ResourceLoader.exists(mesh_path):
		var custom_mesh = load(mesh_path)
		if custom_mesh:
			mesh_instance.mesh = custom_mesh
			print("Loaded custom mesh for ", chest_type, " chest: ", mesh_path)
	else:
		# Fallback to default box mesh
		setup_default_mesh()
	
	# Set chest material color
	var material = StandardMaterial3D.new()
	material.albedo_color = chest_properties.get("material_color", Color.WHITE)
	material.metallic = 0.2
	material.roughness = 0.3
	mesh_instance.material_override = material
	
	# Setup floating text
	cost_label.text = str(cost) + " COINS\nPress E to Open"
	cost_label.modulate = Color.YELLOW
	cost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cost_label.font_size = 24

func setup_default_mesh():
	# Create a treasure chest-like shape
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2.0, 1.5, 1.5)  # Wider chest
	mesh_instance.mesh = box_mesh
	
	# Set up collision to match
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(2.0, 1.5, 1.5)
	collision_shape.shape = box_shape
	
	# Set up interaction area (larger)
	var interaction_collision = interaction_area.get_child(0)
	var interaction_shape = BoxShape3D.new()
	interaction_shape.size = Vector3(3.0, 2.5, 2.5)
	interaction_collision.shape = interaction_shape

func _on_interaction_area_entered(body: Node3D):
	if body.is_in_group("players") and body.is_multiplayer_authority():
		is_near_player = true
		show_interaction_ui()

func _on_interaction_area_exited(body: Node3D):
	if body.is_in_group("players") and body.is_multiplayer_authority():
		is_near_player = false
		hide_interaction_ui()

func show_interaction_ui():
	if not is_opened:
		cost_label.visible = true
		# Make text float up and down
		animate_floating_text()

func hide_interaction_ui():
	cost_label.visible = false

func animate_floating_text():
	if not cost_label.visible:
		return
	
	var tween = create_tween()
	tween.set_loops()
	var original_pos = cost_label.position
	
	# Float up and down gently
	tween.tween_to(cost_label, "position", original_pos + Vector3(0, 0.3, 0), 1.0)
	tween.tween_to(cost_label, "position", original_pos - Vector3(0, 0.3, 0), 1.0)

func _input(event: InputEvent):
	if event.is_action_pressed("interact") and is_near_player and not is_opened:
		attempt_open()

func attempt_open():
	if is_opened:
		return
	
	# Get chest system
	var chest_system = get_tree().get_first_node_in_group("chest_system")
	if chest_system:
		var success = chest_system.attempt_open_chest(chest_id, SteamManager.STEAM_ID)
		if success:
			if chest_type == "mimic":
				activate_mimic()
			else:
				open_chest()

func open_chest():
	is_opened = true
	
	# Visual feedback - change to opened state
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.GRAY
	material.metallic = 0.1
	material.roughness = 0.8
	mesh_instance.material_override = material
	
	# Change floating text
	cost_label.text = "OPENED"
	cost_label.modulate = Color.GREEN
	
	# Hide after a delay
	await get_tree().create_timer(2.0).timeout
	cost_label.visible = false
	
	print("Chest opened successfully!")

func activate_mimic():
	is_opened = true
	print("MIMIC CHEST EXPLODING!")
	
	# Change appearance to show it's a mimic
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.RED
	material.emission = Color.RED * 0.5
	mesh_instance.material_override = material
	
	# Change text to warning
	cost_label.text = "IT'S A MIMIC!"
	cost_label.modulate = Color.RED
	cost_label.font_size = 32
	
	# Shake the chest
	var original_pos = global_position
	for i in range(10):
		global_position = original_pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
		await get_tree().create_timer(0.1).timeout
	
	global_position = original_pos
	
	# Remove the chest after explosion
	await get_tree().create_timer(1.0).timeout
	queue_free()
