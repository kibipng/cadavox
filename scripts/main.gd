extends Node3D

@onready var lobbies_list: VBoxContainer = $MultiplayerUI/VBoxContainer/LobbiesScrollContainer/LobbiesList
@onready var multiplayer_ui: Control = $MultiplayerUI
@onready var player_spawner: MultiplayerSpawner = $Players/PlayerSpawner

const TEXT_CHARACTER = preload("res://scenes/text_character.tscn")

var lobby_id = 0

var previous_sentence:String = ""

var lobby_created:bool = false

var peer = SteamMultiplayerPeer
var word_bank = []

func _ready() -> void:
	peer = SteamManager.peer
	
	peer.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)

func _on_host_btn_pressed() -> void:
	if lobby_created:
		return 
	
	peer.create_lobby(SteamMultiplayerPeer.LOBBY_TYPE_PUBLIC)
	multiplayer.multiplayer_peer = peer

func remove_punctuation(text:String) -> String:
	var  unwanted_chars = [".", ",", ":", ";", "!", "?", "'", "(", ")"]
	var cleaned_text = ""
	for char in text:
		if not char in unwanted_chars:
			cleaned_text+=char
	return cleaned_text

func _on_join_btn_pressed() -> void:
	var lobbies_btns = lobbies_list.get_children()
	for i in lobbies_btns:
		i.queue_free()
	
	open_lobby_list()

func open_lobby_list():
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

func _on_lobby_created(connect: int, _lobby_id: int):
	if connect:
		lobby_id = _lobby_id
		Steam.setLobbyData(lobby_id,"name",str(SteamManager.STEAM_USERNAME+"'s lobby -312-"))
		Steam.setLobbyJoinable(lobby_id,true)
		
		SteamManager.lobby_id = lobby_id
		SteamManager.is_lobby_host = true
		
		hide_menu()
		
		player_spawner.spawn_host()

func _on_lobby_match_list(lobbies: Array):
	var i = 0
	for lobby in lobbies:
		var lobby_name = Steam.getLobbyData(lobby,"name")
		var member_count = Steam.getNumLobbyMembers(lobby)
		var max_players = Steam.getLobbyMemberLimit(lobby)
		
		if lobby_name.contains("-312-"):
			var but := Button.new()
			but.set_text("{0} | {1}/{2}".format([lobby_name.replace(" -312-",""),member_count,max_players]))
			but.set_size(Vector2(400,50))
			but.pressed.connect(join_lobby.bind(lobby))
			lobbies_list.add_child(but)
			i+=1
	
	if i<=0:
		var but := Button.new()
		but.set_text("no lobbies found :( (maybe try refreshing?)")
		but.set_size(Vector2(400,50))
		lobbies_list.add_child(but)

func join_lobby(_lobby_id):
	peer.connect_lobby(_lobby_id)
	multiplayer.multiplayer_peer = peer
	lobby_id = _lobby_id
	hide_menu()

func hide_menu():
	multiplayer_ui.hide()

func print_3d(stri: String,loc: Vector3) -> void:
	var i = 0
	var new_node = Node3D.new()
	add_child(new_node)
	for chr in stri:
		var txt = TEXT_CHARACTER.instantiate()
		new_node.add_child(txt)
		txt.get_node("MeshInstance3D").mesh.text = chr
		txt.global_position=Vector3(float(i)*0.8,0,0)
		#txt.global_position.x-=(stri.length()/2.0+(i*(txt.get_node("MeshInstance3D").mesh.font_size)+0.25))
		i+=1
		#print("what",i)
	new_node.global_position = loc
	new_node.rotation.y = randf_range(-360,360)

func find_differences_in_sentences(og_sentence : String, new_sentence : String) -> Array[String]:
	var og = og_sentence.split(" ")
	var new = new_sentence.split(" ")
	var diff : Array[String] = []
	
	for word in new:
		if !og.has(word):
			diff.append(word)
	
	#var diff_string = ""
	#for word in diff:
		#diff_string+=word+" "
	
	return diff



func _on_speech_to_text_transcribed_msg(is_partial: Variant, new_text: Variant) -> void:
	if !is_partial:
		var new = remove_punctuation(new_text)
		for word in find_differences_in_sentences(previous_sentence,new):
			if !word_bank.has(word.to_lower()):
				print_3d(word,Vector3(randf_range(-20,20),50,randf_range(-20,20)))
				word_bank.append(word.to_lower())
		previous_sentence=new
