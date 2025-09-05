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


const MIN_RES: Vector2i = Vector2i(1,1)
const MAX_RES: Vector2i = Vector2i(4096, 4096)
const MAX_COLORS: int = 12
const MIN_COLORS: int = 2

var user_preview_scale: float = 0.5
var preview_scale_factor: float = 1.4

@export var preview_margin: Vector2 = Vector2(0.4, 0.8) # Horizontal, Vertical margin
@export var target_resolution: Vector2i = Vector2(1024, 1024)
@export var file_path: String
@export var auto_file_path: String

var auto_time: int
var max_photo_limit: int
var background: bool = false
var auto_save_num: int

## Color picker
const COLOR_PICKER = preload("res://scenes/color picker.tscn")

@onready var _color_container: VBoxContainer = $HBoxContainer2/Controls/Colors
@onready var _img: TextureRect = $HBoxContainer2/NoisePreview/img
@onready var _timer: Timer = $Timer
@onready var _option_button: OptionButton = $HBoxContainer2/Controls/VBoxContainer/HBoxContainer/VBoxContainer/OptionButton
@onready var _check_button: CheckButton = $HBoxContainer2/Controls/VBoxContainer/CheckButton
@onready var _file_dialog: FileDialog = $HBoxContainer2/Controls/VBoxContainer/CheckButton/FileDialog
@onready var _confirmation_dialog: ConfirmationDialog = $HBoxContainer2/Controls/VBoxContainer/CheckButton/ConfirmationDialog
@onready var _popup_menu: PopupMenu = $HBoxContainer2/Controls/VBoxContainer/CheckButton/PopupMenu
@onready var _gradient_button: CheckButton = $HBoxContainer2/Controls/Colors/gradient
@onready var _image_x: LineEdit = $HBoxContainer2/Controls/VBoxContainer/VBoxContainer/HBoxContainer2/imageX
@onready var _image_y: LineEdit = $HBoxContainer2/Controls/VBoxContainer/VBoxContainer/HBoxContainer2/imageY
@onready var _add_color: Button = $HBoxContainer2/Controls/Colors/AddColor
@onready var _remove_color: Button = $HBoxContainer2/Controls/Colors/RemoveColor
@onready var _preview_slider: HSlider = $VBoxContainer/VBoxContainer/previewSlider
@onready var _resize_debounce_timer: Timer = Timer.new()

#region rendering
var _rd: RenderingDevice = null
var _shader: RID = RID()
var _pipeline: RID = RID()

# Store the actual RIDs of the dynamically created resources
var _current_input_tex_rid: RID = RID()
var _current_output_tex_rid: RID = RID()
var _current_color_buffer_rid: RID = RID()
var _current_uniform_set_rid: RID = RID()
var _current_param_buffer_rid: RID = RID()

var _format: RDTextureFormat
var _view: RDTextureView
#endregion
#region Sliders
@onready var _seed: LineEdit = $HBoxContainer2/Controls/Sliders/Seed/Seed
@onready var _frequency: HSlider = $HBoxContainer2/Controls/Sliders/Frequency/Frequency
@onready var _offset_x: LineEdit = $HBoxContainer2/Controls/Sliders/Offset/HBoxContainer/X
@onready var _offset_y: LineEdit = $HBoxContainer2/Controls/Sliders/Offset/HBoxContainer/Y
@onready var _noise_type: OptionButton = $HBoxContainer2/Controls/Sliders/NoiseType/NoiseType
@onready var _fractal_type: OptionButton = $HBoxContainer2/Controls/Sliders/FractalType/FractalType
@onready var _cellular_dist_func: OptionButton = $HBoxContainer2/Controls/Sliders/CellularDistanceFunction/CellularDistFunc
@onready var _cellular_return_type: OptionButton = $HBoxContainer2/Controls/Sliders/CellularRetType/CellularReturnType
@onready var _fractal_octaves: HSlider = $"HBoxContainer2/Controls/Sliders/Fractal Octaves/Fractal Octaves"
@onready var _fractal_gain: HSlider = $"HBoxContainer2/Controls/Sliders/Fractal Gain/Fractal Gain"
@onready var _fractal_lacunarity: HSlider = $"HBoxContainer2/Controls/Sliders/Fractal Lacunarity/Fractal Lacunarity"
@onready var _cellular_jitter: HSlider = $HBoxContainer2/Controls/Sliders/CellularJitter/CellularJitter
#endregion
#region Noise controls
## Whether or not the image has a smooth look with interpolated colors or sharper look with discrete color banding
@export var gradient: bool = false
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
#region virtual
func _ready():
	#region === Rendering Device Initialization ===
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
	_format.set_usage_bits(
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	_view = RDTextureView.new()
	#endregion
	
	#region === System Tray Setup ===
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
	
	#region === Loading Preferences and UI Setup ===
	var save: Dictionary = SaveManager.load_prefs()
	auto_file_path = save["auto-save-file"]
	file_path = save["save-file"]
	auto_time = save["auto-save-time"]
	max_photo_limit = save["max-photo-limit"]

	var new_string: String = save["output-resolution"]
	new_string = new_string.erase(0, 1)
	new_string = new_string.erase(new_string.length() - 1, 1)
	var array: Array = new_string.split(", ")
	target_resolution = Vector2i(int(array[0]), int(array[1]))

	$HBoxContainer2/Controls/VBoxContainer/VBoxContainer/HBoxContainer2/imageX.text = str(target_resolution.x)
	$HBoxContainer2/Controls/VBoxContainer/VBoxContainer/HBoxContainer2/imageY.text = str(target_resolution.y)
	#endregion

	#region === Initial Scale and Slider Setup ===
	preview_scale_factor = calculate_scale_factor(target_resolution, user_preview_scale)
	_preview_slider.max_value = calculate_max_preview_scale(target_resolution)

	if auto_time >= 0:
		_option_button.selected = _option_button.get_item_index(auto_time)
	#endregion

	set_process(true)  # Start processing for the free queue
	refresh_image()  # Initial refresh
	
	#region === Resize Debounce Timer Setup ===
	add_child(_resize_debounce_timer)
	_resize_debounce_timer.wait_time = 0.15
	_resize_debounce_timer.one_shot = true
	_resize_debounce_timer.connect("timeout", Callable(self, "_on_resize_debounce_timeout"))
	#endregion


func _exit_tree():
	set_process(false) # Stop _process before cleanup

	if _rd != null:
		# Free the current RIDs that were not yet queued (or are the very last ones)
		if _current_uniform_set_rid.is_valid():
			_rd.free_rid(_current_uniform_set_rid)
		if _current_input_tex_rid.is_valid():
			_rd.free_rid(_current_input_tex_rid)
		if _current_output_tex_rid.is_valid():
			_rd.free_rid(_current_output_tex_rid)
		if _current_color_buffer_rid.is_valid():
			_rd.free_rid(_current_color_buffer_rid)
		if _current_param_buffer_rid.is_valid():
			_rd.free_rid(_current_param_buffer_rid)
		
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
		if _shader.is_valid():
			_rd.free_rid(_shader)
		
		_rd.free()
		_rd = null
#endregion
func calculate_scale_factor(_target_resolution: Vector2i, _user_scale: float, _margin: Vector2 = preview_margin) -> float:
	var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
	window_size.x *= _margin.x
	window_size.y *= _margin.y

	var desired_size: Vector2 = _target_resolution * _user_scale
	var scale_to_fit_window = min(window_size.x / desired_size.x, window_size.y / desired_size.y, 1.0)
	return _user_scale * scale_to_fit_window


func calculate_max_preview_scale(_target_resolution: Vector2i, _margin: Vector2 = preview_margin, _desired_cap: float = 4.0, _auto_refresh: bool = true) -> float:
	var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
	window_size.x *= _margin.x
	window_size.y *= _margin.y

	var scale_x = window_size.x / _target_resolution.x
	var scale_y = window_size.y / _target_resolution.y
	var max_scale = min(scale_x, scale_y, _desired_cap)

	_preview_slider.max_value = max_scale

	if _preview_slider.value > max_scale:
		_preview_slider.value = max_scale
		preview_scale_factor = calculate_scale_factor(_target_resolution, user_preview_scale, _margin)
		if _auto_refresh:
			refresh_image()

	return max_scale

func recalculate_image_sizing() -> void:
	# Define the margin (assuming you have this exported or hardcoded)
	var margin = preview_margin

	# Recalculate the max scale and update the slider max value
	var max_scale := calculate_max_preview_scale(target_resolution, margin)
	_preview_slider.max_value = max_scale

	# Clamp slider value if it exceeds max scale
	if _preview_slider.value > max_scale:
		_preview_slider.value = max_scale

	# Update the user scale from slider value
	user_preview_scale = _preview_slider.value

	# Recalculate effective preview scale factor for new resolution and margin
	preview_scale_factor = calculate_scale_factor(target_resolution, user_preview_scale, margin)

	# Update image preview size accordingly
	_img.size = ceil(target_resolution * preview_scale_factor)

	# Optionally refresh the image texture if required
	#refresh_image()


func add_color() -> void:
	if colors.size() >= MAX_COLORS:
		wrong_input_tween(_add_color)
		return
	var color_picker: NoiseColorPicker = COLOR_PICKER.instantiate()
	_color_container.add_child(color_picker)
	colors.append(color_picker.color)
	var label: Label = color_picker.get_child(0)
	label.text = "Color " + str(colors.size())
	refresh_image()

func remove_color() -> void:
	if colors.size() <= MIN_COLORS:
		wrong_input_tween(_remove_color)
		return

	colors.remove_at(colors.size() - 1)
	remove_last_child_node(_color_container)
	refresh_image()

func remove_last_child_node(node: Node) -> void:
	if node.get_child_count() > 0:
		var last_child = node.get_child(node.get_child_count() - 1)
		node.remove_child(last_child)
		last_child.queue_free()

func update_color(new_col: Color, id: int) -> void:
	colors[id] = new_col
	refresh_image()

func refresh_image(dimensions: Vector2i = target_resolution * preview_scale_factor) -> ImageTexture:
	if _rd == null:
		push_error("RenderingDevice not initialized. Cannot refresh image.")
		return null
	
	dimensions.x = clamp(dimensions.x, MIN_RES.x, MAX_RES.x)
	dimensions.y = clamp(dimensions.y, MIN_RES.y, MAX_RES.y)
	_format.width = int(dimensions.x)
	_format.height = int(dimensions.y)

	var fnl := FastNoiseLite.new()
	fnl.seed = noise_seed
	fnl.noise_type = noise_type
	
	# Check if we're generating a preview or final image
	var default_preview_res: Vector2i = target_resolution * preview_scale_factor
	var is_preview = (dimensions.x == clamp(default_preview_res.x, MIN_RES.x, MAX_RES.x) && 
					  dimensions.y == clamp(default_preview_res.y, MIN_RES.y, MAX_RES.y))
	
	# Only scale frequency for preview, use base frequency for final output
	if is_preview:
		fnl.frequency = frequency / preview_scale_factor
	else:
		fnl.frequency = frequency
	
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
		_rd.free_rid(_current_input_tex_rid)
	if _current_output_tex_rid.is_valid():
		_rd.free_rid(_current_output_tex_rid)
	if _current_color_buffer_rid.is_valid():
		_rd.free_rid(_current_color_buffer_rid)
	if _current_uniform_set_rid.is_valid():
		_current_uniform_set_rid = RID()

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
	
	var params := PackedByteArray()
	params.resize(4)
	params.encode_s32(0, int(gradient))

	_current_param_buffer_rid = _rd.storage_buffer_create(params.size(), params)
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
	
	var uniform_param := RDUniform.new()
	uniform_param.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_param.binding = 3
	uniform_param.add_id(_current_param_buffer_rid)
	
	_current_uniform_set_rid = _rd.uniform_set_create([uniform_input, uniform_output, uniform_colors, uniform_param], _shader, 0)
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
	
	if is_preview:
		_img.texture = img_texture
		AudioManager.play("generate")

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
	frequency = clamp(rand.randfn(0.1, 0.1), 0.0001, 1.0)
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
	var _pressed: bool = bool(rand.randi_range(0,1))
	_gradient_button.set_pressed_no_signal(_pressed)
	gradient = _pressed
	
	var color_pickers := _color_container.get_children()
	for i in range(colors.size() - 1, -1, -1):
		colors[i] = Color(rand.randf(), rand.randf(), rand.randf())
		color_pickers[i+4].get_child(1).color = colors[i]
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
	if time >= 0:
		_timer.start(time + 0.01)

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

func count_photos_in_directory(directory_path: String) -> int:
	var count = 0
	var dir = DirAccess.open(directory_path)

	if dir:
		dir.list_dir_begin() # Start listing directory contents
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				# Skip subdirectories, we only care about files for this count
				pass
			else:
				if file_name.contains("AUTO-SAVE_") and (file_name.contains(".png") or file_name.contains(".jpg")):
					count += 1
			file_name = dir.get_next()
		dir.list_dir_end() # End listing directory contents
	else:
		push_error("Could not open directory: %s" % directory_path)
	return count

func wrong_input_tween(parent: Node) -> void:
	AudioManager.play("error")
	if !parent.has_node("Panel"):
		return
	var panel: Panel = parent.get_child(0)
	if panel is not Panel:
		return
	
	panel.position = Vector2.ZERO
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(panel, "modulate", Color.WHITE, 0.05)

	var tween1: Tween = get_tree().create_tween()
	var shake_amounts = [Vector2(-10, 0), Vector2(10, 0), Vector2(-7, 0), Vector2(7, 0), Vector2(-4, 0), Vector2(4, 0), Vector2(0, 0)]
	var duration_per_shake = 0.05
	for o in shake_amounts:
		tween1.tween_property(panel, "position", o, duration_per_shake).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween1.tween_property(panel, "position", Vector2.ZERO, duration_per_shake).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	await tween1.finished
	panel.position = Vector2.ZERO
	var tween2: Tween = get_tree().create_tween()
	tween2.tween_property(panel, "modulate", Color.TRANSPARENT, 0.05)
#region events
func _on_resize_debounce_timeout() -> void:
	recalculate_image_sizing()
	refresh_image()


func _on_menu_item_pressed(id: int) -> void:
	match id:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_window().show()
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_window().show()
			$HBoxContainer2/Controls/VBoxContainer/CheckButton/PopupMenu.popup_centered()
			AudioManager.play("popup")
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
	#AudioManager.play("select")
	@warning_ignore("int_as_enum_without_cast")
	noise_type = id
	refresh_image()

func _on_fractal_type_pressed(id: int) -> void:
	#AudioManager.play("select")
	@warning_ignore("int_as_enum_without_cast")
	fractal_type = id
	refresh_image()

func _on_cellular_dist_func_pressed(id: int) -> void:
	#AudioManager.play("select")
	@warning_ignore("int_as_enum_without_cast")
	cellular_distance_function = id
	refresh_image()

func _on_cellular_return_type_pressed(id: int) -> void:
	#AudioManager.play("select")
	@warning_ignore("int_as_enum_without_cast")
	cellular_return_type = id
	refresh_image()

func _on_add_color_pressed() -> void:
	#AudioManager.play("select")
	add_color()

func _on_remove_color_pressed() -> void:
	#AudioManager.play("select")
	remove_color()

func _on_randomise_pressed() -> void:
	#AudioManager.play("select")
	randomise_sliders()

func _on_randomise_col_pressed() -> void:
	#AudioManager.play("select")
	randomise_colors()

func _on_save_pressed() -> void:
	#AudioManager.play("select")
	$HBoxContainer2/Controls/VBoxContainer/Save/FileDialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	$HBoxContainer2/Controls/VBoxContainer/Save/FileDialog.popup()
	AudioManager.play("popup")

func _on_file_dialog_file_selected(path: String) -> void:
	file_path = path
	SaveManager.save_prefs({"save-file": file_path, "auto-save-file": auto_file_path, "auto-save-time": auto_time, "max-photo-limit": max_photo_limit, "output-resolution": target_resolution})
	var final_img: Image = refresh_image(target_resolution).get_image()
	save_to_file(final_img, file_path)

func _on_apply_pressed() -> void:
	#AudioManager.play("select")
	refresh_image()

func _on_check_button_toggled(toggled_on: bool) -> void:
	#AudioManager.play("select")
	if toggled_on:
		_confirmation_dialog.popup_centered()
		AudioManager.play("popup")
		$HBoxContainer2/Controls/VBoxContainer/HBoxContainer.visible = true
	else:
		$HBoxContainer2/Controls/VBoxContainer/HBoxContainer.visible = false
		background = false
		_timer.stop()
		get_tree().set_auto_accept_quit(true)

func _on_texture_button_pressed() -> void:
	#AudioManager.play("select")
	_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	_file_dialog.popup()
	AudioManager.play("popup")


func _on_option_button_item_selected(index: int) -> void:
	#AudioManager.play("select")
	auto_time = _option_button.get_item_id(index)
	start_timer(auto_time)

func _on_file_dialog_dir_selected(dir: String) -> void:
	auto_file_path = dir
	SaveManager.save_prefs({"save-file": file_path, "auto-save-file": auto_file_path, "auto-save-time": auto_time, "max-photo-limit": max_photo_limit, "output-resolution": target_resolution})

	if auto_file_path != "" and auto_time >= 0:
		start_timer(auto_time)

func _on_timer_timeout() -> void:
	if auto_file_path != "" and auto_time >= 0:
		if _file_dialog.is_visible() and _confirmation_dialog.is_visible() and _popup_menu.is_visible(): # Wait for user to exit
			start_timer(auto_time)
			return
		
		var num_images: int = count_photos_in_directory(auto_file_path)
		if num_images >= max_photo_limit: # stop generating
			_check_button.set_pressed(false)
			return
		randomise_colors()
		randomise_sliders()
		save_to_file(refresh_image(target_resolution).get_image(), auto_file_path + "/AUTO-SAVE_" + str(num_images+1).pad_zeros(3) + ".png")
		start_timer(auto_time)

func _on_confirmation_dialog_confirmed() -> void:
	#AudioManager.play("select")
	background = true
	get_tree().auto_accept_quit = false
	start_timer(auto_time)

func _on_confirmation_dialog_canceled() -> void:
	#AudioManager.play("select")
	background = false
	get_tree().auto_accept_quit = true

func _on_popup_menu_id_pressed(id: int) -> void:
	#AudioManager.play("select")
	max_photo_limit = id
	SaveManager.save_prefs({"save-file": file_path, "auto-save-file": auto_file_path, "auto-save-time": auto_time, "max-photo-limit": max_photo_limit, "output-resolution": target_resolution})

func _on_cog_pressed() -> void:
	#AudioManager.play("select")
	_popup_menu.popup_centered()
	AudioManager.play("popup")

func _on_image_x_text_changed(new_text: String) -> void:
	if new_text.is_valid_int():
		var i := clampi(new_text.to_int(), MIN_RES.x, MAX_RES.x)
		if i != target_resolution.x:
			target_resolution.x = i
			_on_target_resolution_changed()
		if i != new_text.to_int():
			_image_x.text = str(i)
			wrong_input_tween(_image_x)

func _on_image_y_text_changed(new_text: String) -> void:
	if new_text.is_valid_int():
		var i := clampi(new_text.to_int(), MIN_RES.y, MAX_RES.y)
		if i != target_resolution.y:
			target_resolution.y = i
			_on_target_resolution_changed()
		if i != new_text.to_int():
			_image_y.text = str(i)
			wrong_input_tween(_image_y)

func _on_gradient_button_toggled(toggled_on: bool) -> void:
	#AudioManager.play("select")
	if gradient == toggled_on:
		return
	
	gradient = toggled_on
	refresh_image()

func _on_resized() -> void:
	if _resize_debounce_timer == null:
		return
	_resize_debounce_timer.start()

func _on_preview_slider_value_changed(value: float) -> void:
	user_preview_scale = value

func _on_preview_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		preview_scale_factor = calculate_scale_factor(target_resolution, user_preview_scale)
		refresh_image()

func _on_target_resolution_changed() -> void:
	# Clamp to valid bounds
	target_resolution.x = clampi(target_resolution.x, MIN_RES.x, MAX_RES.x)
	target_resolution.y = clampi(target_resolution.y, MIN_RES.y, MAX_RES.y)
	
	recalculate_image_sizing()
	
	# Persist preferences with updated resolution
	SaveManager.save_prefs({
		"save-file": file_path,
		"auto-save-file": auto_file_path,
		"auto-save-time": auto_time,
		"max-photo-limit": max_photo_limit,
		"output-resolution": target_resolution
	})

	# Refresh image with updated sizing
	refresh_image()

func _on_fit_pressed() -> void:
	_preview_slider.set_value(4.0)
	_on_preview_slider_drag_ended(true)
	
#endregion
