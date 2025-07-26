extends Node3D

@onready var lobbies_list: VBoxContainer = $MultiplayerUI/VBoxContainer/LobbiesScrollContainer/LobbiesList
@onready var multiplayer_ui: Control = $MultiplayerUI
@onready var player_spawner: MultiplayerSpawner = $Players/PlayerSpawner
@onready var letter_spawner: MultiplayerSpawner = $Letters/LetterSpawner

const TEXT_CHARACTER = preload("res://scenes/text_character.tscn")

var lobby_id = 0

var previous_sentence:String = ""

var lobby_created:bool = false

var peer = SteamMultiplayerPeer
var word_bank = []
var main_player


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

func spawn_word(new_text:String):
	for word in find_differences_in_sentences(previous_sentence,remove_punctuation(new_text)):
		if !word_bank.has(word.to_lower()):
			var pos = Vector3(randf_range(-20,20),50,randf_range(-20,20))
			letter_spawner.print_3d(word,pos)
			word_bank.append(word.to_lower())
			if main_player==null:
				main_player=get_tree().get_nodes_in_group("players")[0]
			main_player.spawn_text.append([word.to_lower(),pos])

func _on_speech_to_text_transcribed_msg(is_partial: Variant, new_text: Variant) -> void:
	if !is_partial:
		spawn_word(new_text)
		previous_sentence=remove_punctuation(new_text)
