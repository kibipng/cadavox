# challenge_ui.gd - FIXED VERSION with delayed initialization

extends Control

@onready var challenge_label: Label = $ChallengePanel/VBoxContainer/ChallengeLabel
@onready var description_label: Label = $ChallengePanel/VBoxContainer/DescriptionLabel
@onready var timer_label: Label = $ChallengePanel/VBoxContainer/TimerLabel
@onready var counting_label: Label = $ChallengePanel/VBoxContainer/CountingLabel
@onready var challenge_panel: PanelContainer = $ChallengePanel
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var challenge_manager: Node
var challenge_timer: float = 0.0

func _ready():
	print("ChallengeUI: Starting _ready()")
	
	# Hide panel initially
	challenge_panel.visible = false
	counting_label.visible = false
	
	# Wait for managers to be created, then initialize
	call_deferred("initialize_ui")

func initialize_ui():
	print("ChallengeUI: Initializing UI (deferred)")
	
	# Find the challenge manager (should exist now)
	challenge_manager = get_tree().get_first_node_in_group("challenge_manager")
	
	print("ChallengeUI: Found challenge_manager: ", challenge_manager != null)
	
	if challenge_manager:
		print("ChallengeUI: Connecting signals...")
		challenge_manager.challenge_started.connect(_on_challenge_started)
		challenge_manager.challenge_ended.connect(_on_challenge_ended)
		print("ChallengeUI: Signals connected!")
		print("ChallengeUI: Setup complete")
	else:
		print("ChallengeUI: ERROR - Still could not find challenge_manager!")
		# Try again in a bit
		await get_tree().create_timer(0.1).timeout
		initialize_ui()

func _process(delta):
	if challenge_timer > 0:
		challenge_timer -= delta
		timer_label.text = "Time: %.1f" % challenge_timer
		
		# Change color based on remaining time
		if challenge_timer < 5.0:
			timer_label.modulate = Color.RED
		elif challenge_timer < 10.0:
			timer_label.modulate = Color.YELLOW
		else:
			timer_label.modulate = Color.WHITE
	
	# Update counting progress for counting challenge
	if challenge_manager and challenge_manager.is_challenge_running():
		var current_challenge = challenge_manager.get_current_challenge()
		if current_challenge.get("id") == "count_to_20":
			var current_count = challenge_manager.get_counting_progress()
			counting_label.text = "Count: %d/20" % current_count
			counting_label.visible = true
		else:
			counting_label.visible = false

func _on_challenge_started(challenge_data: Dictionary):
	print("ChallengeUI: Challenge started: ", challenge_data)
	
	challenge_label.text = challenge_data.get("name", "Challenge!")
	description_label.text = challenge_data.get("description", "")
	challenge_timer = challenge_manager.challenge_duration
	
	print("ChallengeUI: Set challenge text to: ", challenge_label.text)
	print("ChallengeUI: Set description to: ", description_label.text)
	
	# Show counting label for counting challenge
	if challenge_data.get("id") == "count_to_20":
		counting_label.visible = true
		counting_label.text = "Count: 0/20"
		print("ChallengeUI: Enabled counting label")
	else:
		counting_label.visible = false
	
	# Show panel with animation
	challenge_panel.visible = true
	print("ChallengeUI: Made challenge panel visible")
	
	if animation_player.has_animation("challenge_appear"):
		animation_player.play("challenge_appear")
		print("ChallengeUI: Playing appear animation")

func _on_challenge_ended():
	print("ChallengeUI: Challenge ended")
	challenge_timer = 0.0
	counting_label.visible = false
	
	# Hide panel with animation
	if animation_player.has_animation("challenge_disappear"):
		animation_player.play("challenge_disappear")
		print("ChallengeUI: Playing disappear animation")
	else:
		challenge_panel.visible = false
		print("ChallengeUI: Hiding challenge panel")
