extends Node

var sounds: Dictionary = {
	"select": preload("res://resources/sounds/Retro1.mp3"),
	"error": preload("res://resources/sounds/Modern16.mp3"),
	"popup": preload("res://resources/sounds/Modern8.mp3"),
	"generate": preload("res://resources/sounds/Modern2.mp3")
}
var player: AudioStreamPlayer

func _ready() -> void:
	player = AudioStreamPlayer.new()
	get_tree().current_scene.add_child(player)


	
func play(sound: String) -> void:
	if player == null:
		return
	if !sounds.has(sound):
		return
	
	player.stream = sounds[sound]
	player.play()
