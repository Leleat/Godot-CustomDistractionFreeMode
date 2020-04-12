"""
The first 3 items in the list are non-dock items (here docks are = all editor docks + bottom panel). Then come the docks for the 2D/3D viewport followed by a separator (non-dock item).
After that, all docks will be listed again for the Script viewport. That means in total there are 4 non-dock items. So the PopupMenu's structure looks like size (top to bottom): 
(3 x non-dock items) + (dock_count x dock items) + (non-dock separator) + (dock_count x dock items)
"""

tool
extends MenuButton


var BASE_CONTROL_VBOX : VBoxContainer
var INTERFACE : EditorInterface
var DFM_BUTTON : ToolButton
var settings_updated : bool = false
var dock_count : int = 0 # includes bottom panel
var current_main_screen : String
var first_change_to_script_view : bool = true
var dfm_enabled_on_scene : bool
var dfm_enabled_on_script : bool
var docks : Dictionary # set via plugin.gd => {dock_position : [tabcontainer, visibility]}
const UTIL = preload("res://addons/CustomDFM/util.gd")


func _ready() -> void:
	get_popup().connect("index_pressed", self, "_on_PopupMenu_index_pressed")
	get_popup().connect("hide", self, "_on_PopupMenu_hide")
	get_popup().hide_on_checkable_item_selection = false
	icon = get_icon("Collapse", "EditorIcons")


func _on_PopupMenu_index_pressed(index : int) -> void:
	get_popup().toggle_item_checked(index)
	settings_updated = true


func _on_PopupMenu_hide() -> void:
	if settings_updated:
		save_settings()
		DFM_BUTTON.emit_signal("pressed")
		yield(get_tree(), "idle_frame")
		DFM_BUTTON.emit_signal("pressed")
		settings_updated = false


func _on_MenuButton_pressed() -> void:
	load_settings()


func _on_DFM_BUTTON_pressed() -> void:
	yield(get_tree(), "idle_frame") 
	match current_main_screen: # setup for node selection/script opening via SceneTreeDock
		"2D", "3D": 
			dfm_enabled_on_scene = true if DFM_BUTTON.pressed else false
		"Script":
			dfm_enabled_on_script = true if DFM_BUTTON.pressed else false
	
	update_dock_visibility()


func _on_main_screen_changed(new_screen : String) -> void:
	if first_change_to_script_view and get_popup().get_item_count() > 2: # to autoswitch to DFM when switching to "Script" view the first time, if it is enabled
		if get_popup().is_item_checked(1):
			if new_screen == "Script":
				DFM_BUTTON.emit_signal("pressed")
				first_change_to_script_view = false
		else:
			first_change_to_script_view = false
	
	current_main_screen = new_screen
	
	if not dfm_enabled_on_scene and DFM_BUTTON.pressed and current_main_screen in ["2D", "3D"]: # for node selection via SceneTreeDock
		DFM_BUTTON.pressed = false # does not trigger signal
	if dfm_enabled_on_script and not DFM_BUTTON.pressed and current_main_screen == "Script": # for script opening via SceneTreeDock
		DFM_BUTTON.pressed = true # does not trigger signal
	
	yield(get_tree(), "idle_frame") 
	update_dock_visibility()


func update_dock_visibility(tab : int = -1) -> void: # called via signals on DFM button press or tab change of dock
	if (current_main_screen in ["2D", "3D"] and dfm_enabled_on_scene) or (current_main_screen == "Script" and dfm_enabled_on_script):
		# reset tabcontainer visibility property
		for tabcontainer in docks:
			docks[tabcontainer][1] = false
		
		# setup for visibility and disable dock
		for index in dock_count - 1: 
			var idx = 3 + index  if current_main_screen in ["2D", "3D"] else 3 + index + dock_count + 1
			var dock = UTIL.get_dock(get_popup().get_item_text(idx), BASE_CONTROL_VBOX) # dock_slot_position set as meta via UTIL.get_dock()
			if get_popup().is_item_checked(idx):
				docks[dock.get_meta("pos")][1] = true
				dock.get_parent().set_tab_disabled(dock.get_index(), false)
			else:
				dock.get_parent().set_tab_disabled(dock.get_index(), true)
		
		# set tabcontainer visibility
		for tabcontainer in docks:
			if docks[tabcontainer][1] == true:
				docks[tabcontainer][0].show()
				# switch to first active tab
				if docks[tabcontainer][0].get_tab_disabled(docks[tabcontainer][0].current_tab): 
					for idx in docks[tabcontainer][0].get_tab_count():
						if not docks[tabcontainer][0].get_tab_disabled(idx):
							docks[tabcontainer][0].current_tab = idx
							break
			else:
				docks[tabcontainer][0].hide()
		
		# set vsplit visibilities
		for tabcontainer in docks.size() / 2:
			if docks[tabcontainer * 2][1] == false and docks[tabcontainer * 2 + 1][1] == false:
				docks[tabcontainer * 2][0].get_parent().hide()
			else:
				docks[tabcontainer * 2][0].get_parent().show()
		
		# set rhsplitcontainer visibility
		if docks[EditorPlugin.DOCK_SLOT_RIGHT_UL][0].get_parent().visible == false and docks[EditorPlugin.DOCK_SLOT_RIGHT_UR][0].get_parent().visible == false:
			docks[EditorPlugin.DOCK_SLOT_RIGHT_UL][0].get_parent().get_parent().hide()
		else:
			docks[EditorPlugin.DOCK_SLOT_RIGHT_UL][0].get_parent().get_parent().show()
		
		# set bottom panel visibility
		var idx = get_popup().get_item_count() - 1 if current_main_screen == "Script" else 3 + dock_count - 1
		if get_popup().is_item_checked(idx):
			BASE_CONTROL_VBOX.get_child(1).get_child(1).get_child(1).get_child(0).get_child(0).get_child(1).show()
	
	else:
		for index in dock_count - 1:
			var dock = UTIL.get_dock(get_popup().get_item_text(index + 3), BASE_CONTROL_VBOX)
			dock.get_parent().set_tab_disabled(dock.get_index(), false)
			dock.get_parent().show()
			dock.get_parent().get_parent().show()
			dock.get_parent().get_parent().get_parent().show() 


func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("Usage", get_popup().get_item_text(0).replace(" ", "_"), "true" if get_popup().is_item_checked(0) else "")
	config.set_value("Usage", get_popup().get_item_text(1).replace(" ", "_"), "true" if get_popup().is_item_checked(1) else "")
	for index in dock_count: 
		# scene editor
		config.set_value("Scene_Editor", get_popup().get_item_text(3 + index).replace(" ", "_"), "true" if get_popup().is_item_checked(3 + index) else "")
		# script editor
		config.set_value("Script_Editor", get_popup().get_item_text(3 + index + dock_count + 1).replace(" ", "_"), "true" if get_popup().is_item_checked(3 + index + dock_count + 1) else "")
	config.save("user://custom_dfm_settings.cfg")


func load_settings() -> void:
	get_popup().clear()
	get_popup().rect_size = Vector2(1, 1)
	get_popup().add_check_item("Use DFM in scene viewport on editor start")
	get_popup().add_check_item("Use DFM in script viewport on editor start")
	get_popup().add_separator("  2D/3D Settings  ")
	
	for tabcontainer in BASE_CONTROL_VBOX.get_child(1).get_child(0).get_children(): # LEFT left
		for dock in tabcontainer.get_children():
			get_popup().add_check_item(dock.get_class() if dock.get_class().findn("Dock") != -1 else dock.name)
	
	for tabcontainer in BASE_CONTROL_VBOX.get_child(1).get_child(1).get_child(0).get_children(): # LEFT right
		for dock in tabcontainer.get_children():
			get_popup().add_check_item(dock.get_class() if dock.get_class().findn("Dock") != -1 else dock.name)
	
	for tabcontainer in BASE_CONTROL_VBOX.get_child(1).get_child(1).get_child(1).get_child(1).get_child(0).get_children(): # RIGHT left
		for dock in tabcontainer.get_children():
			get_popup().add_check_item(dock.get_class() if dock.get_class().findn("Dock") != -1 else dock.name)
	
	for tabcontainer in BASE_CONTROL_VBOX.get_child(1).get_child(1).get_child(1).get_child(1).get_child(1).get_children(): # RIGHT right
		for dock in tabcontainer.get_children():
			get_popup().add_check_item(dock.get_class() if dock.get_class().findn("Dock") != -1 else dock.name)
	
	get_popup().add_check_item("Bottom Panel")
	
	get_popup().add_separator("  Script Settings  ")
	for index in get_popup().get_item_count() - 4: 
		get_popup().add_check_item(get_popup().get_item_text(index + 3))
	
	dock_count = (get_popup().get_item_count() - 4) / 2
	
	var config = ConfigFile.new()
	var error = config.load("user://custom_dfm_settings.cfg")
	if error == OK:
		get_popup().set_item_checked(0, config.get_value("Usage", get_popup().get_item_text(0).replace(" ", "_"), false) as bool)
		get_popup().set_item_checked(1, config.get_value("Usage", get_popup().get_item_text(1).replace(" ", "_"), false) as bool)
		for index in dock_count:
			get_popup().set_item_checked(3 + index, config.get_value("Scene_Editor", get_popup().get_item_text(index + 3).replace(" ", "_"), false) as bool)
			get_popup().set_item_checked(3 + index + dock_count + 1, config.get_value("Script_Editor", get_popup().get_item_text(index + 3).replace(" ", "_"), false) as bool)
