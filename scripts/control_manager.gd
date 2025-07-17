extends Node
class_name ControlManger

var noise_gen: NoiseGen

func _ready() -> void:
	noise_gen = get_tree().current_scene

func color_control_updated(new_col: Color, id: int) -> void:
	noise_gen.update_color(new_col, id)
