extends Node

const save_file_name: String = "user://prefs.json" # You can change this to be whatever you want (save_game.txt, game.save etc.), just don't change the 'user://' at the front
const default_dictionary: Dictionary = {"save-file": "", "auto-save-file": "", "auto-save-time": -1, "max-photo-limit": 50, "output-resolution": Vector2i(1024, 1024)}

## Stores data to a save file to be loaded from later
func save_prefs(data: Dictionary) -> void:
	var save_file: FileAccess = FileAccess.open(save_file_name, FileAccess.WRITE)
	if save_file == null:
		push_error("Failed to open file for saving: ", FileAccess.get_open_error())
		return
	var json_string: String = JSON.stringify(data) # Converts dictionary to one long string "{...}"
	save_file.store_line(json_string)
	save_file.close()

## Loads data from a save file
func load_prefs() -> Dictionary:
	if FileAccess.file_exists(save_file_name): # i.e. The game has been saved before
		var save_file = FileAccess.open(save_file_name, FileAccess.READ)
		if save_file == null:
			push_error("Failed to open file for loading: ", FileAccess.get_open_error())
			return default_dictionary # Return default if file exists but can't be opened

		var json = JSON.new()
		var json_string = save_file.get_line()
		
		save_file.close() # Close the file immediately after getting the line

		if json.parse(json_string) == OK:
			var loaded_data = json.get_data()
			# Merge loaded data with defaults to ensure all keys exist
			var merged_data = default_dictionary.duplicate(true) # Deep copy default
			for key in loaded_data:
				merged_data[key] = loaded_data[key]
			return merged_data # Successful retrieval
		else:
			push_error("Corrupted data: " + json.get_error_message())
			return default_dictionary # Return default on corruption

	return default_dictionary

func reset_save() -> void:
	save_prefs(default_dictionary)
