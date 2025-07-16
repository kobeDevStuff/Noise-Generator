extends Control
class_name NoiseGen

var rand = RandomNumberGenerator.new()

## The different colors in the scene 
var colors: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.75, 0.75, 0.75),
	Color(0.5, 0.5, 0.5),
	Color(0.25, 0.25, 0.25),
	Color(0.0, 0.0, 0.0)
]

const PREVIEW_RESOLUTION: Vector2 = Vector2(512, 512)
@export var target_resolution: Vector2 = Vector2(3413, 1920) #1.333333333333 * DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()) Dynamic way
@export var file_path: String
@export var auto_file_path: String
var auto_time: int
var max_photo_limit: int
var background: bool = false

## Color picker
const COLOR_PICKER = preload("res://scenes/color picker.tscn")

@onready var color_container: VBoxContainer = $CanvasLayer/HBoxContainer2/Controls/Colors
@onready var img: TextureRect = $CanvasLayer/HBoxContainer2/NoisePreview/img
@onready var timer: Timer = $Timer
@onready var option_button: OptionButton = $CanvasLayer/HBoxContainer2/Controls/VBoxContainer/HBoxContainer/VBoxContainer/OptionButton
@onready var check_button: CheckButton = $CanvasLayer/HBoxContainer2/Controls/VBoxContainer/CheckButton

#region rendering
var _rd: RenderingDevice = null
var _shader: RID = RID()
var _pipeline: RID = RID()

# Store the actual RIDs of the dynamically created resources
var _current_input_tex_rid: RID = RID()
var _current_output_tex_rid: RID = RID()
var _current_color_buffer_rid: RID = RID()
var _current_uniform_set_rid: RID = RID()

var _format: RDTextureFormat
var _view: RDTextureView

# Queue for RIDs to be freed in a later frame
var _rid_free_queue: Array[RID] = []
#endregion
#region Sliders
@onready var _seed: LineEdit = $CanvasLayer/HBoxContainer2/Controls/Sliders/Seed/Seed
@onready var _frequency: HSlider = $CanvasLayer/HBoxContainer2/Controls/Sliders/Frequency/Frequency
@onready var _offset_x: LineEdit = $CanvasLayer/HBoxContainer2/Controls/Sliders/Offset/HBoxContainer/X
@onready var _offset_y: LineEdit = $CanvasLayer/HBoxContainer2/Controls/Sliders/Offset/HBoxContainer/Y
@onready var _noise_type: OptionButton = $CanvasLayer/HBoxContainer2/Controls/Sliders/NoiseType/NoiseType
@onready var _fractal_type: OptionButton = $CanvasLayer/HBoxContainer2/Controls/Sliders/FractalType/FractalType
@onready var _cellular_dist_func: OptionButton = $CanvasLayer/HBoxContainer2/Controls/Sliders/CellularDistanceFunction/CellularDistFunc
@onready var _cellular_return_type: OptionButton = $CanvasLayer/HBoxContainer2/Controls/Sliders/CellularRetType/CellularReturnType
@onready var _fractal_octaves: HSlider = $"CanvasLayer/HBoxContainer2/Controls/Sliders/Fractal Octaves/Fractal Octaves"
@onready var _fractal_gain: HSlider = $"CanvasLayer/HBoxContainer2/Controls/Sliders/Fractal Gain/Fractal Gain"
@onready var _fractal_lacunarity: HSlider = $"CanvasLayer/HBoxContainer2/Controls/Sliders/Fractal Lacunarity/Fractal Lacunarity"
@onready var _cellular_jitter: HSlider = $CanvasLayer/HBoxContainer2/Controls/Sliders/CellularJitter/CellularJitter
#endregion
#region Noise controls
## The random number seed for all noise types.
@export var noise_seed: int = 0

## The noise algorithm used.
@export var noise_type: FastNoiseLite.NoiseType = FastNoiseLite.NoiseType.TYPE_SIMPLEX

## The frequency for all noise types. Low frequency results in smooth noise while high frequency results in rougher, more granular noise.
@export var frequency: float = 0.01

## Translate the noise input coordinates by the given Vector3.
@export var offset: Vector2 = Vector2(0,0)

## Method for combining octaves into a fractal. See FractalType for options.
@export var fractal_type: FastNoiseLite.FractalType = FastNoiseLite.FractalType.FRACTAL_NONE

## The number of noise layers that are sampled to get the final value for fractal noise types.
@export_range(1, 12, 1) var fractal_octaves: int = 1

## Determines the strength of each subsequent layer of noise in fractal noise.
@export_range(0.0, 2.0, 0.01) var fractal_gain: float = 0.01

## Frequency multiplier between subsequent octaves in fractal noise.
@export_range(0.0, 5.0, 0.01) var fractal_lacunarity: float = 0.01

## Determines how the distance to the nearest/second-nearest point is computed. See CellularDistanceFunction for options.
@export var cellular_distance_function: FastNoiseLite.CellularDistanceFunction = FastNoiseLite.CellularDistanceFunction.DISTANCE_EUCLIDEAN

## Maximum distance a point can move off of its grid position. Set to 0 for an even grid.
@export_range(0.0, 2.0, 0.01) var cellular_jitter: float = 0.01

## Return type from cellular noise calculations. See CellularReturnType for options.
@export var cellular_return_type: FastNoiseLite.CellularReturnType = FastNoiseLite.CellularReturnType.RETURN_CELL_VALUE
#endregion
##region Advanced mode controls
#@export var advanced_mode: bool
#
### Sets the strength of the fractal ping pong type.
#@export var fractal_ping_pong_strength: float = 2.0
#
### Higher weighting means higher octaves have less impact if lower octaves have a large impact.
#@export var fractal_weighted_strength: float = 0.0
#
### If enabled, another FastNoiseLite instance is used to warp the space, resulting in a distortion of the noise.
#@export var domain_warp_enabled: bool = false
#
### Sets the maximum warp distance from the origin.
#@export var domain_warp_amplitude: float = 30.0
#
### Determines the strength of each subsequent layer of the noise which is used to warp the space.
#@export var domain_warp_fractal_gain: float = 0.5
#
### Octave lacunarity of the fractal noise which warps the space.
#@export var domain_warp_fractal_lacunarity: float = 6.0
#
### The number of noise layers that are sampled to get the final value for the fractal noise which warps the space.
#@export var domain_warp_fractal_octaves: int = 5
#
### The method for combining octaves into a fractal which is used to warp the space. See DomainWarpFractalType for options.
#@export var domain_warp_fractal_type: FastNoiseLite.DomainWarpFractalType = FastNoiseLite.DomainWarpFractalType.DOMAIN_WARP_FRACTAL_PROGRESSIVE
#
### Frequency of the noise which warps the space.
#@export var domain_warp_frequency: float = 0.05
#
### Sets the warp algorithm. See DomainWarpType for options.
#@export var domain_warp_type: FastNoiseLite.DomainWarpType = FastNoiseLite.DomainWarpType.DOMAIN_WARP_SIMPLEX
##endregion
#region virtual
func _ready():
	#region system tray
	var si: StatusIndicator = StatusIndicator.new()
	si.icon = load("res://resources/Icon.png")
	si.tooltip = "Noise Generator"
	si.pressed.connect(_on_status_indicator_pressed)
	add_child(si)
	 
	var menu: PopupMenu = PopupMenu.new()
	add_child(menu)
	menu.add_item("Show Window", 1)
	menu.add_item("Settings", 2)
	menu.add_separator()
	menu.add_item("Quit", 3)
	si.menu = menu.get_path()
	menu.id_pressed.connect(_on_menu_item_pressed)
	
	get_window().close_requested.connect(_on_window_closed)
	#endregion

	var save: Dictionary = SaveManager.load_prefs()
	auto_file_path = save["auto-save-file"]
	file_path = save["save-file"]
	auto_time = save["auto-save-time"]
	max_photo_limit = save["max-photo-limit"]
	
	if auto_time > 0:
		option_button.selected = option_button.get_item_index(auto_time)
	
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		push_error("Failed to create local RenderingDevice!")
		set_process(false)
		return

	var shader_file = load("res://scripts/compute.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	if not _shader.is_valid():
		push_error("Failed to create shader RID!")
		_rd.free()
		_rd = null
		set_process(false)
		return

	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		push_error("Failed to create compute pipeline RID!")
		_rd.free_rid(_shader)
		_rd.free()
		_rd = null
		_shader = RID()
		set_process(false)
		return

	# Initialize format and view for textures once
	_format = RDTextureFormat.new()
	_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	_format.set_usage_bits(RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)
	_view = RDTextureView.new()

	set_process(true) # Start processing for the free queue
	refresh_image() # Initial refresh

func _process(_delta):
	if not _rid_free_queue.is_empty():
		# Iterate in reverse to safely remove elements while iterating
		for i in range(_rid_free_queue.size() - 1, -1, -1): # Corrected: goes down to -1 (includes 0)
			var rid_to_free = _rid_free_queue[i]
			if rid_to_free.is_valid():
				_rd.free_rid(rid_to_free)
			_rid_free_queue.remove_at(i) # Always remove, whether freed successfully or already invalid

func _exit_tree():
	set_process(false) # Stop _process before cleanup

	# Ensure anything in the queue is also freed on exit
	if _rd != null:
		for rid_to_free in _rid_free_queue:
			if rid_to_free.is_valid():
				_rd.free_rid(rid_to_free)
		_rid_free_queue.clear()

		# Free the current RIDs that were not yet queued (or are the very last ones)
		if _current_uniform_set_rid.is_valid():
			_rd.free_rid(_current_uniform_set_rid)
		if _current_input_tex_rid.is_valid():
			_rd.free_rid(_current_input_tex_rid)
		if _current_output_tex_rid.is_valid():
			_rd.free_rid(_current_output_tex_rid)
		if _current_color_buffer_rid.is_valid():
			_rd.free_rid(_current_color_buffer_rid)
		
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
		if _shader.is_valid():
			_rd.free_rid(_shader)
		
		_rd.free()
		_rd = null
#endregion

func add_color() -> void:
	var color_picker: NoiseColorPicker = COLOR_PICKER.instantiate()
	color_container.add_child(color_picker)
	colors.append(color_picker.color)
	var label: Label = color_picker.get_child(0)
	label.text = "Color " + str(colors.size())

func remove_color() -> void:
	colors.remove_at(colors.size() - 1)
	remove_last_child_node(color_container)

func remove_last_child_node(node: Node) -> void:
	if node.get_child_count() > 0:
		var last_child = node.get_child(node.get_child_count() - 1)
		node.remove_child(last_child)
		last_child.queue_free()

func update_color(new_col: Color, id: int) -> void:
	colors[id] = new_col
	refresh_image()

func refresh_image(dimensions: Vector2 = PREVIEW_RESOLUTION) -> ImageTexture:
	if _rd == null:
		push_error("RenderingDevice not initialized. Cannot refresh image.")
		return null

	_format.width = int(dimensions.x)
	_format.height = int(dimensions.y)

	var fnl := FastNoiseLite.new()
	fnl.seed = noise_seed
	fnl.noise_type = noise_type
	fnl.frequency = frequency * (PREVIEW_RESOLUTION.y/dimensions.y) # Fit height
	fnl.fractal_type = fractal_type
	fnl.fractal_octaves = fractal_octaves
	fnl.fractal_gain = fractal_gain
	fnl.fractal_lacunarity = fractal_lacunarity
	fnl.offset = Vector3(offset.x, offset.y, 0)
	fnl.cellular_distance_function = cellular_distance_function
	fnl.cellular_jitter = cellular_jitter
	fnl.cellular_return_type = cellular_return_type

	var noise_image = fnl.get_image(int(dimensions.x), int(dimensions.y))
	noise_image.convert(Image.FORMAT_RGBA8)
	var image_bytes: PackedByteArray = noise_image.get_data()

	# === Queue old RIDs for deferred freeing before creating new ones ===
	if _current_input_tex_rid.is_valid():
		_rid_free_queue.append(_current_input_tex_rid)
	if _current_output_tex_rid.is_valid():
		_rid_free_queue.append(_current_output_tex_rid)
	if _current_color_buffer_rid.is_valid():
		_rid_free_queue.append(_current_color_buffer_rid)
	if _current_uniform_set_rid.is_valid():
		_rid_free_queue.append(_current_uniform_set_rid)

	# --- Create NEW RIDs ---
	_current_input_tex_rid = _rd.texture_create(_format, _view, [image_bytes])
	_current_output_tex_rid = _rd.texture_create(_format, _view)

	var color_bytes := PackedByteArray()
	for c in colors:
		color_bytes += float_to_bytes(c.r)
		color_bytes += float_to_bytes(c.g)
		color_bytes += float_to_bytes(c.b)
		color_bytes += float_to_bytes(c.a)
	_current_color_buffer_rid = _rd.storage_buffer_create(color_bytes.size(), color_bytes)

	# === Create uniform set ===
	var uniform_input := RDUniform.new()
	uniform_input.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_input.binding = 0
	uniform_input.add_id(_current_input_tex_rid)

	var uniform_output := RDUniform.new()
	uniform_output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_output.binding = 1
	uniform_output.add_id(_current_output_tex_rid)

	var uniform_colors := RDUniform.new()
	uniform_colors.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_colors.binding = 2
	uniform_colors.add_id(_current_color_buffer_rid)

	_current_uniform_set_rid = _rd.uniform_set_create([uniform_input, uniform_output, uniform_colors], _shader, 0)
	if not _current_uniform_set_rid.is_valid():
		push_error("Failed to create uniform set RID!")
		return null

	# === Dispatch compute shader ===
	var compute_list = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _current_uniform_set_rid, 0)

	var groups_x = int(ceil(dimensions.x / 16.0))
	var groups_y = int(ceil(dimensions.y / 16.0))
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()

	# === Retrieve final image ===
	var packed_bytes = _rd.texture_get_data(_current_output_tex_rid, 0)
	var final_image = Image.create_from_data(int(dimensions.x), int(dimensions.y), false, Image.FORMAT_RGBA8, packed_bytes)
	var img_texture = ImageTexture.create_from_image(final_image)

	if dimensions == Vector2(512, 512):
		img.texture = img_texture

	return img_texture

func float_to_bytes(value: float) -> PackedByteArray:
	var arr = PackedByteArray()
	var spb = StreamPeerBuffer.new()
	spb.put_float(value)
	arr.resize(4)
	spb.seek(0)
	for i in range(4):
		arr[i] = spb.get_u8()
	return arr

func randomise_sliders() -> void:
	noise_seed = rand.randi()
	@warning_ignore("int_as_enum_without_cast")
	noise_type = rand.randi_range(0, 5)
	frequency = rand.randf_range(0, 0.1)
	offset = Vector2(rand.randi_range(-50, 50), rand.randi_range(-50, 50))
	@warning_ignore("int_as_enum_without_cast")
	fractal_type = rand.randi_range(0, 3)
	fractal_octaves = rand.randi_range(1, 12)
	fractal_gain = rand.randf_range(0, 2)
	fractal_lacunarity = rand.randf_range(0, 5)
	@warning_ignore("int_as_enum_without_cast")
	cellular_distance_function = rand.randi_range(0, 3)
	cellular_jitter = rand.randf_range(0, 2)
	@warning_ignore("int_as_enum_without_cast")
	cellular_return_type = rand.randi_range(0, 6)
	
	update_sliders()
	refresh_image()

func randomise_colors() -> void:
	var color_pickers := color_container.get_children()
	for i in range(colors.size() - 1, -1, -1):
		colors[i] = Color(rand.randf(), rand.randf(), rand.randf())
		color_pickers[i+3].get_child(1).color = colors[i]
	refresh_image()

func update_sliders() -> void:
	_seed.text = str(noise_seed)
	_frequency.value = frequency
	_offset_x.text = str(offset.x)
	_offset_y.text = str(offset.y)
	_fractal_octaves.value = fractal_octaves
	_fractal_gain.value = fractal_gain
	_fractal_lacunarity.value = fractal_lacunarity
	_cellular_jitter.value = cellular_jitter
	_noise_type.selected = noise_type
	_fractal_type.selected = fractal_type
	_cellular_dist_func.selected = cellular_distance_function
	_cellular_return_type.selected = cellular_return_type

func start_timer(time: int) -> void:
	if time > 0:
		timer.start(time)

func save_to_file(image: Image, path: String) -> void:
	if path == "" or path == null:
		push_error("Path is empty.")
		return
	
	if path.contains(".png"):
		var err:= image.save_png(path)
		if err == OK:
			print("Image saved to: " + path)
		else:
			push_error("Failed to save image: %s", % err)
	elif path.contains(".jpg"):
		var err:= image.save_jpg(path)
		if err == OK:
			print("Image saved to: " + path)
		else:
			push_error("Failed to save image: %s", % err)
	else:
		printerr("Incorrect file format, use .png or .jpg")
#region events
func _on_menu_item_pressed(id: int) -> void:
	match id:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_window().show()
		2:
			$CanvasLayer/HBoxContainer2/Controls/VBoxContainer/CheckButton/PopupMenu.popup_centered()
		3:
			get_tree().quit()

func _on_window_closed() -> void:
	# Check if the user has enabled the "minimize on close" feature
	if background:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	else:
		# If the option is not enabled, quit the application normally
		get_tree().quit()

func _on_status_indicator_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().show()

func _on_seed_text_changed(new_text: String) -> void:
	noise_seed = hash(new_text)
	refresh_image()

func _on_x_text_changed(new_text: String) -> void:
	if new_text.is_valid_float():
		offset.x = float(new_text)
		refresh_image()

func _on_y_text_changed(new_text: String) -> void:
	if new_text.is_valid_float():
		offset.y = float(new_text)
		refresh_image()

func _on_frequency_value_changed(value: float) -> void:
	frequency = value

func _on_fractal_octaves_value_changed(value: float) -> void:
	fractal_octaves = roundi(value)

func _on_fractal_gain_value_changed(value: float) -> void:
	fractal_gain = value

func _on_fractal_lacunarity_value_changed(value: float) -> void:
	fractal_lacunarity = value

func _on_cellular_jitter_value_changed(value: float) -> void:
	cellular_jitter = value

func _on_frequency_drag_ended(value_changed: bool) -> void:
	if value_changed:
		refresh_image()

func _on_fractal_octaves_drag_ended(value_changed: bool) -> void:
	if value_changed:
		refresh_image()

func _on_fractal_gain_drag_ended(value_changed: bool) -> void:
	if value_changed:
		refresh_image()

func _on_cellular_jitter_drag_ended(value_changed: bool) -> void:
	if value_changed:
		refresh_image()

func _on_fractal_lacunarity_drag_ended(value_changed: bool) -> void:
	if value_changed:
		refresh_image()

func _on_seed_text_submitted(new_text: String) -> void:
	if hash(new_text) != noise_seed:
		noise_seed = hash(new_text)
		refresh_image()

func _on_x_text_submitted(new_text: String) -> void:
	if new_text.is_valid_float() and absf(float(new_text) - offset.x) > 0.001:
		offset.x = float(new_text)
		refresh_image()

func _on_y_text_submitted(new_text: String) -> void:
	if new_text.is_valid_float() and absf(float(new_text) - offset.y) > 0.001:
		offset.y = float(new_text)
		refresh_image()

func _on_noise_type_pressed(id: int) -> void:
	@warning_ignore("int_as_enum_without_cast")
	noise_type = id
	refresh_image()

func _on_fractal_type_pressed(id: int) -> void:
	@warning_ignore("int_as_enum_without_cast")
	fractal_type = id
	refresh_image()

func _on_cellular_dist_func_pressed(id: int) -> void:
	@warning_ignore("int_as_enum_without_cast")
	cellular_distance_function = id
	refresh_image()

func _on_cellular_return_type_pressed(id: int) -> void:
	@warning_ignore("int_as_enum_without_cast")
	cellular_return_type = id
	refresh_image()

func _on_add_color_pressed() -> void:
	add_color()

func _on_remove_color_pressed() -> void:
	remove_color()

func _on_randomise_pressed() -> void:
	randomise_sliders()

func _on_randomise_col_pressed() -> void:
	randomise_colors()

func _on_save_pressed() -> void:
	$CanvasLayer/HBoxContainer2/Controls/VBoxContainer/Save/FileDialog.visible = true

func _on_file_dialog_file_selected(path: String) -> void:
	file_path = path
	print("Attempting to save...")
	SaveManager.save_prefs({"save-file": file_path, "auto-save-file": auto_file_path, "auto-save-time": auto_time, "max-photo-limit": max_photo_limit})
	var final_img: Image = refresh_image(target_resolution).get_image()
	save_to_file(final_img, file_path)

func _on_apply_pressed() -> void:
	refresh_image()

func _on_check_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		$CanvasLayer/HBoxContainer2/Controls/VBoxContainer/CheckButton/ConfirmationDialog.popup_centered()
		$CanvasLayer/HBoxContainer2/Controls/VBoxContainer/HBoxContainer.visible = true
	else:
		$CanvasLayer/HBoxContainer2/Controls/VBoxContainer/HBoxContainer.visible = false
		timer.stop()
		get_tree().set_auto_accept_quit(true)

func _on_texture_button_pressed() -> void:
	$CanvasLayer/HBoxContainer2/Controls/VBoxContainer/CheckButton/FileDialog.visible = true

func _on_option_button_item_selected(index: int) -> void:
	auto_time = option_button.get_item_id(index)
	start_timer(auto_time)

func _on_file_dialog_dir_selected(dir: String) -> void:
	auto_file_path = dir
	SaveManager.save_prefs({"save-file": file_path, "auto-save-file": auto_file_path, "auto-save-time": auto_time, "max-photo-limit": max_photo_limit})

	if auto_file_path != "" and auto_time > 0:
		start_timer(auto_time)

func _on_timer_timeout() -> void:
	if auto_file_path != "" and auto_time > 0:
		randomise_colors()
		randomise_sliders()
		save_to_file(refresh_image(target_resolution).get_image(), auto_file_path + "/AUTO-SAVE_" + Time.get_datetime_string_from_system(false, true).replace(":", "-") + ".png")
		start_timer(auto_time)

func _on_confirmation_dialog_confirmed() -> void:
	background = true
	get_tree().auto_accept_quit = false
	start_timer(auto_time)

func _on_confirmation_dialog_canceled() -> void:
	background = false
	get_tree().auto_accept_quit = true

func _on_popup_menu_id_pressed(id: int) -> void:
	max_photo_limit = id
	SaveManager.save_prefs({"save-file": file_path, "auto-save-file": auto_file_path, "auto-save-time": auto_time, "max-photo-limit": max_photo_limit})
#endregion
