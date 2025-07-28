# player_subtitle_overlay.gd - Individual floating subtitle for each player
extends Control

@onready var player_name_bg: NinePatchRect = $PlayerPanel/PlayerNameBG
@onready var player_name_label: Label = $PlayerPanel/PlayerNameBG/PlayerNameLabel
@onready var subtitle_bg: NinePatchRect = $PlayerPanel/SubtitleBG
@onready var subtitle_label: RichTextLabel = $PlayerPanel/SubtitleBG/SubtitleLabel

var target_player: Node3D
var target_steam_id: int
var subtitle_timer: float = 0.0
var subtitle_duration: float = 4.0
var max_distance: float = 20.0

# Visual properties
var player_color: Color
var base_font_size: int = 14

func _ready():
	# Hide subtitle initially, show name always
	subtitle_bg.visible = false
	player_name_bg.visible = true
	
	# Setup visual style
	setup_visual_style()

func setup_for_player(player: Node3D):
	target_player = player
	target_steam_id = player.steam_id
	player_color = get_player_color(target_steam_id)
	
	# Set player name
	player_name_label.text = player.player_name
	player_name_label.add_theme_color_override("font_color", player_color)
	
	print("Setup subtitle overlay for player: ", player.player_name)

func setup_visual_style():
	# Player name background - always visible, compact
	var name_style = StyleBoxFlat.new()
	name_style.bg_color = Color(0, 0, 0, 0.7)
	name_style.corner_radius_top_left = 8
	name_style.corner_radius_top_right = 8
	name_style.corner_radius_bottom_left = 8
	name_style.corner_radius_bottom_right = 8
	name_style.content_margin_left = 8
	name_style.content_margin_right = 8
	name_style.content_margin_top = 4
	name_style.content_margin_bottom = 4
	player_name_bg.add_theme_stylebox_override("panel", name_style)
	
	# Subtitle background - larger, only when speaking
	var subtitle_style = StyleBoxFlat.new()
	subtitle_style.bg_color = Color(0, 0, 0, 0.8)
	subtitle_style.corner_radius_top_left = 12
	subtitle_style.corner_radius_top_right = 12
	subtitle_style.corner_radius_bottom_left = 12
	subtitle_style.corner_radius_bottom_right = 12
	subtitle_style.content_margin_left = 12
	subtitle_style.content_margin_right = 12
	subtitle_style.content_margin_top = 8
	subtitle_style.content_margin_bottom = 8
	subtitle_bg.add_theme_stylebox_override("panel", subtitle_style)
	
	# Player name label styling
	player_name_label.add_theme_font_size_override("font_size", 12)
	player_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Subtitle label styling
	subtitle_label.fit_content = true
	subtitle_label.scroll_active = false
	subtitle_label.add_theme_font_size_override("normal_font_size", base_font_size)

func _process(delta):
	if not target_player or not is_instance_valid(target_player):
		queue_free()
		return
	
	# Update position to follow player
	update_screen_position()
	
	# Update subtitle timer
	if subtitle_timer > 0:
		subtitle_timer -= delta
		if subtitle_timer <= 0:
			hide_subtitle()

func update_screen_position():
	if not target_player:
		return
	
	# Get camera
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	# Calculate distance and visibility
	var my_player = get_my_player()
	if not my_player:
		return
	
	var distance = my_player.global_position.distance_to(target_player.global_position)
	
	# Hide if too far away
	if distance > max_distance:
		visible = false
		return
	else:
		visible = true
	
	# Convert 3D position to screen position
	var player_head_pos = target_player.global_position + Vector3(0, 2.5, 0)  # Above player's head
	var screen_pos = camera.unproject_position(player_head_pos)
	
	# Check if position is valid (in front of camera)
	if camera.is_position_behind(player_head_pos):
		visible = false
		return
	
	# Position the UI element
	position = screen_pos - size * 0.5  # Center the panel
	
	# Scale based on distance (closer = larger)
	var scale_factor = clamp(1.0 - (distance / max_distance), 0.3, 1.0)
	scale = Vector2(scale_factor, scale_factor)

func get_my_player():
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_multiplayer_authority():
			return player
	return null

func show_subtitle(text: String):
	# Don't show subtitle for yourself
	var my_player = get_my_player()
	if my_player and my_player.steam_id == target_steam_id:
		return
	
	# Format text with player color
	var colored_text = "[color=%s]%s[/color]" % [player_color.to_html(), text]
	subtitle_label.text = colored_text
	
	# Show subtitle background
	subtitle_bg.visible = true
	subtitle_timer = subtitle_duration
	
	# Animate appearance
	var tween = create_tween()
	subtitle_bg.modulate.a = 0.0
	tween.tween_property(subtitle_bg, "modulate:a", 1.0, 0.2)
	
	print("Showing subtitle for ", target_player.player_name, ": ", text)

func hide_subtitle():
	if not subtitle_bg.visible:
		return
	
	# Animate disappearance
	var tween = create_tween()
	tween.tween_property(subtitle_bg, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): subtitle_bg.visible = false)

func get_player_color(steam_id: int) -> Color:
	# Generate consistent color per player
	var hue = float(steam_id % 360) / 360.0
	return Color.from_hsv(hue, 0.8, 0.9)

# ===== MAIN SUBTITLE SYSTEM MANAGER =====
# subtitle_system_manager.gd - Manages all player subtitle overlays
class SubtitleSystemManager extends Node:
	
	var player_subtitle_overlays = {}  # steam_id -> overlay instance
	var subtitle_scene = preload("res://scenes/player_subtitle_overlay.tscn")
	
	func _ready():
		add_to_group("subtitle_system")
		
		# Connect to player join/leave events
		# You'll need to call these when players join/leave
		
	func add_player_overlay(player: Node3D):
		var steam_id = player.steam_id
		
		if player_subtitle_overlays.has(steam_id):
			return  # Already exists
		
		# Create overlay
		var overlay = subtitle_scene.instantiate()
		overlay.setup_for_player(player)
		
		# Add to UI layer (you'll need a CanvasLayer for UI)
		var ui_layer = get_node("/root/Main/UILayer")  # Adjust path as needed
		if ui_layer:
			ui_layer.add_child(overlay)
			player_subtitle_overlays[steam_id] = overlay
			print("Added subtitle overlay for player: ", player.player_name)
	
	func remove_player_overlay(steam_id: int):
		if player_subtitle_overlays.has(steam_id):
			var overlay = player_subtitle_overlays[steam_id]
			if overlay and is_instance_valid(overlay):
				overlay.queue_free()
			player_subtitle_overlays.erase(steam_id)
	
	func show_player_subtitle(steam_id: int, text: String):
		if player_subtitle_overlays.has(steam_id):
			var overlay = player_subtitle_overlays[steam_id]
			if overlay and is_instance_valid(overlay):
				overlay.show_subtitle(text)
	
	func handle_player_speech(speech_data: Dictionary):
		var steam_id = speech_data["steam_id"]
		var text = speech_data["text"]
		
		show_player_subtitle(steam_id, text)
	
	# Call this when players join the game
	func on_player_joined(player: Node3D):
		add_player_overlay(player)
	
	# Call this when players leave the game
	func on_player_left(steam_id: int):
		remove_player_overlay(steam_id)
