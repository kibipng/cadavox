# word_gun.gd - Add this to your player.gd or create separate script
extends Node

# Word Gun System Variables
var word_gun_active: bool = false
var word_gun_ammo: Array = []  # Array of individual letters
var current_word_ammo_display: String = ""

# Word Gun UI references
var word_gun_ui: Control
var ammo_display: Label
var crosshair: Control

signal word_gun_fired(letter: String, position: Vector3, direction: Vector3)

func _ready():
	# Create word gun UI
	setup_word_gun_ui()

func enable_word_gun_mode():
	word_gun_active = true
	print("Word Gun activated! Speak a word to load ammo.")
	show_word_gun_ui()

func disable_word_gun_mode():
	word_gun_active = false
	word_gun_ammo.clear()
	current_word_ammo_display = ""
	hide_word_gun_ui()

func load_word_ammo(word: String):
	if not word_gun_active:
		return
	
	# Clear previous ammo
	word_gun_ammo.clear()
	
	# Split word into individual letters
	for i in range(word.length()):
		var letter = word[i].to_upper()
		word_gun_ammo.append(letter)
	
	current_word_ammo_display = word.to_upper()
	update_ammo_display()
	
	print("Word Gun loaded with: ", current_word_ammo_display, " (", word_gun_ammo.size(), " shots)")

func fire_word_gun():
	if not word_gun_active or word_gun_ammo.is_empty():
		return
	
	# Get the next letter
	var letter = word_gun_ammo.pop_front()
	
	# Get firing position and direction from camera
	var player = get_parent()  # Assuming this is attached to player
	var camera = player.camera_3d
	var fire_position = camera.global_position
	var fire_direction = -camera.global_transform.basis.z  # Forward direction
	
	# Create letter projectile
	create_letter_projectile(letter, fire_position, fire_direction)
	
	# Update UI
	current_word_ammo_display = ""
	for remaining_letter in word_gun_ammo:
		current_word_ammo_display += remaining_letter
	
	update_ammo_display()
	
	# Emit signal for networking
	word_gun_fired.emit(letter, fire_position, fire_direction)
	
	print("Fired letter: ", letter, " | Remaining ammo: ", current_word_ammo_display)
	
	# Auto-disable if out of ammo
	if word_gun_ammo.is_empty():
		print("Word Gun empty! Speak another word to reload.")

func create_letter_projectile(letter: String, start_pos: Vector3, direction: Vector3):
	# Create a letter projectile using your existing text system
	var main = get_node("/root/Main")
	if main and main.has_method("spawn_word_locally"):
		# Spawn the letter with initial velocity
		var letter_pos = start_pos + direction * 2.0  # Spawn slightly forward
		main.spawn_word_locally(letter, letter_pos, 0.0)
		
		# Get the spawned letter and modify its physics
		# We'll need to modify the text_character script to handle word gun bullets
		var letter_objects = get_tree().get_nodes_in_group("text_characters")
		if letter_objects.size() > 0:
			var newest_letter = letter_objects[-1]  # Get the last spawned
			if newest_letter.has_method("set_as_word_gun_bullet"):
				newest_letter.set_as_word_gun_bullet(direction * 20.0)  # High speed

func setup_word_gun_ui():
	# Create UI elements for word gun
	word_gun_ui = Control.new()
	word_gun_ui.name = "WordGunUI"
	word_gun_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Ammo display (top center)
	ammo_display = Label.new()
	ammo_display.text = ""
	ammo_display.add_theme_font_size_override("font_size", 24)
	ammo_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_display.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ammo_display.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ammo_display.position.y = 50
	word_gun_ui.add_child(ammo_display)
	
	# Crosshair (center)
	crosshair = Control.new()
	var crosshair_label = Label.new()
	crosshair_label.text = "+"
	crosshair_label.add_theme_font_size_override("font_size", 32)
	crosshair_label.add_theme_color_override("font_color", Color.RED)
	crosshair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_child(crosshair_label)
	word_gun_ui.add_child(crosshair)
	
	# Instructions (bottom)
	var instructions = Label.new()
	instructions.text = "WORD GUN ACTIVE\nSpeak to load ammo • Left Click to fire"
	instructions.add_theme_font_size_override("font_size", 16)
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	instructions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	instructions.position.y = -80
	word_gun_ui.add_child(instructions)
	
	# Add to scene but hide initially
	get_tree().current_scene.add_child(word_gun_ui)
	word_gun_ui.visible = false

func show_word_gun_ui():
	if word_gun_ui:
		word_gun_ui.visible = true

func hide_word_gun_ui():
	if word_gun_ui:
		word_gun_ui.visible = false

func update_ammo_display():
	if ammo_display:
		ammo_display.text = "AMMO: " + current_word_ammo_display

func _input(event: InputEvent):
	if not word_gun_active:
		return
	
	# Fire on left click
	if event.is_action_pressed("fire"):  # You'll need to add this input action
		fire_word_gun()
	
	# Toggle word gun with 'G' key or another key
	if event.is_action_pressed("toggle_word_gun"):
		if word_gun_active:
			disable_word_gun_mode()
		else:
			enable_word_gun_mode()

# Handle incoming word gun shots from other players
func handle_word_gun_shot(shot_data: Dictionary):
	var letter = shot_data["letter"]
	var pos_array = shot_data["position"]
	var dir_array = shot_data["direction"]
	var shooter_id = shot_data["steam_id"]
	
	var position = Vector3(pos_array[0], pos_array[1], pos_array[2])
	var direction = Vector3(dir_array[0], dir_array[1], dir_array[2])
	
	# Create the projectile on this client
	create_letter_projectile(letter, position, direction)
	
	print("Player ", shooter_id, " fired word gun letter: ", letter)
