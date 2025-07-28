# item_system.gd - Add this as a new script
extends Node

# Item definitions
var item_definitions = {
	"word_gun": {
		"name": "Word Gun",
		"description": "Loads with letters from spoken words",
		"mesh_path": "res://models/word_gun.obj",  # Your custom mesh
		"hold_position": Vector3(0.3, -0.2, -0.5),  # Relative to camera
		"hold_rotation": Vector3(-10, 5, 0),  # Degrees
		"type": "weapon"
	},
	"blue_shell": {
		"name": "Blue Turtle Shell",
		"description": "Targets the richest player",
		"mesh_path": "res://models/blue_shell.obj",  # Your custom mesh
		"hold_position": Vector3(0.2, -0.3, -0.4),
		"hold_rotation": Vector3(0, 0, 0),
		"type": "consumable"
	}
}

# Update chest rewards in chest_manager.gd - add these to the rewards arrays:
# {"type": "item", "item_id": "word_gun"}
# {"type": "item", "item_id": "blue_shell"}

func get_item_definition(item_id: String) -> Dictionary:
	return item_definitions.get(item_id, {})
