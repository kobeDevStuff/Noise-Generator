extends VBoxContainer
class_name NoiseColorPicker

var color: Color = Color.BLACK
@onready var id: int = get_index() - 4

func _on_colour_color_changed(col: Color) -> void:
	color = col

func _on_colour_popup_closed() -> void:
	ControlManager.color_control_updated(color, id)
