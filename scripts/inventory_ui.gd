# inventory_ui.gd - Single slot inventory display
extends Control

@onready var inventory_slot: Panel = $InventoryPanel/InventorySlot
@onready var item_icon: TextureRect = $InventoryPanel/InventorySlot/ItemIcon
@onready var item_name: Label = $InventoryPanel/InventorySlot/ItemName
@onready var empty_label: Label = $InventoryPanel/InventorySlot/EmptyLabel
#@onready var use_button: Button = $InventoryPanel/UseButton
#@onready var drop_button: Button = $InventoryPanel/DropButton

var inventory_system: Node
var my_steam_id: int
var current_item: String = ""

# Item icons (you can replace with actual textures)
var item_icons = {
	"word_gun": "🔫",
	"blue_turtle_shell": "🟦", 
	"health_potion": "🧪",
	"max_hp_boost": "💪"
}

func _ready():
	# Get inventory system
	inventory_system = get_tree().get_first_node_in_group("inventory_system")
	my_steam_id = SteamManager.STEAM_ID
	
	if inventory_system:
		inventory_system.item_added.connect(_on_item_added)
		inventory_system.item_removed.connect(_on_item_removed)
		inventory_system.inventory_full.connect(_on_inventory_full)
	
	# Connect buttons
	#use_button.pressed.connect(_on_use_button_pressed)
	#drop_button.pressed.connect(_on_drop_button_pressed)
	
	# Initialize display
	update_inventory_display()

func _on_item_added(steam_id: int, item_type: String):
	if steam_id == my_steam_id:
		current_item = item_type
		update_inventory_display()
		show_pickup_notification(item_type)

func _on_item_removed(steam_id: int, item_type: String):
	if steam_id == my_steam_id:
		current_item = ""
		update_inventory_display()

func _on_inventory_full(steam_id: int, attempted_item: String):
	if steam_id == my_steam_id:
		show_inventory_full_message(attempted_item)

func update_inventory_display():
	if current_item == "":
		# Empty inventory
		item_icon.visible = false
		item_name.visible = false
		empty_label.visible = true
		empty_label.text = "EMPTY\n(1 slot only)"
		#use_button.disabled = true
		#drop_button.disabled = true
		
		# Style empty slot
		var empty_style = StyleBoxFlat.new()
		empty_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		empty_style.border_color = Color.GRAY
		empty_style.border_width_top = 2
		empty_style.border_width_bottom = 2
		empty_style.border_width_left = 2
		empty_style.border_width_right = 2
		inventory_slot.add_theme_stylebox_override("panel", empty_style)
	else:
		# Has item
		item_icon.visible = true
		item_name.visible = true
		empty_label.visible = false
		#use_button.disabled = false
		#drop_button.disabled = false
		
		# Set item info
		var item_def = inventory_system.item_definitions.get(current_item, {})
		item_name.text = item_def.get("name", current_item.capitalize())
		
		# Set icon (using emoji for now - you can replace with actual textures)
		var icon_text = item_icons.get(current_item, "❓")
		var icon_label = Label.new()
		icon_label.text = icon_text
		icon_label.add_theme_font_size_override("font_size", 32)
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# Clear previous icon and add new one
		for child in item_icon.get_children():
			child.queue_free()
		item_icon.add_child(icon_label)
		
		# Style filled slot
		var filled_style = StyleBoxFlat.new()
		filled_style.bg_color = Color(0.1, 0.3, 0.1, 0.9)  # Green tint
		filled_style.border_color = Color.GREEN
		filled_style.border_width_top = 3
		filled_style.border_width_bottom = 3
		filled_style.border_width_left = 3
		filled_style.border_width_right = 3
		inventory_slot.add_theme_stylebox_override("panel", filled_style)

func _on_use_button_pressed():
	if inventory_system and current_item != "":
		inventory_system.use_item(my_steam_id)

func _on_drop_button_pressed():
	if inventory_system and current_item != "":
		inventory_system.drop_item(my_steam_id)

func show_pickup_notification(item_type: String):
	# Create a temporary notification
	var notification = Label.new()
	var item_def = inventory_system.item_definitions.get(item_type, {})
	notification.text = "PICKED UP: " + item_def.get("name", item_type.capitalize())
	notification.add_theme_font_size_override("font_size", 18)
	notification.add_theme_color_override("font_color", Color.GREEN)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.position = Vector2(0, -50)
	
	add_child(notification)
	
	# Animate and remove
	var tween = create_tween()
	tween.parallel().tween_property(notification, "position:y", -100, 1.0)
	tween.parallel().tween_property(notification, "modulate:a", 0.0, 1.0)
	tween.tween_callback(notification.queue_free)

func show_inventory_full_message(attempted_item: String):
	# Create warning message
	var warning = Label.new()
	var item_def = inventory_system.item_definitions.get(attempted_item, {})
	warning.text = "INVENTORY FULL!\nCan't pick up: " + item_def.get("name", attempted_item.capitalize()) + "\nDrop current item first!"
	warning.add_theme_font_size_override("font_size", 16)
	warning.add_theme_color_override("font_color", Color.RED)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.position = Vector2(0, -80)
	
	add_child(warning)
	
	# Flash effect and remove
	var tween = create_tween()
	tween.set_loops(3)
	tween.tween_property(warning, "modulate", Color.TRANSPARENT, 0.2)
	tween.tween_property(warning, "modulate", Color.WHITE, 0.2)
	tween.tween_callback(warning.queue_free)

func _input(event: InputEvent):
	# Quick use item with number key
	if event.is_action_pressed("use_item") and current_item != "":  # You can bind this to "1" key
		_on_use_button_pressed()
	
	# Quick drop item
	if event.is_action_pressed("drop_item") and current_item != "":  # You can bind this to "Q" key
		_on_drop_button_pressed()
