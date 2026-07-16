extends Node3D

# === EKSPORTY – podłącz w Inspectorze ===
@export var camera: Camera3D
@export var teleport_points: Array[Marker3D] = []   # P0_Center, P1_Pionek, ... P6_Krol
@export var figures: Array[Node3D] = []              # Pionek, Wieża, Goniec, Skoczek, Hetman, Król
@export var env_distant: Node3D                      # L2_Distant
@export var env_main: Node3D                         # L1_Main
@export var world_env: WorldEnvironment
@export var fps_label: Label

# === STAN ===
var current_point: int = 0
var is_rotating: bool = false
var fade_overlay: ColorRect
var pano_sky: PanoramaSkyMaterial
var solid_sky: ProceduralSkyMaterial
var using_pano: bool = true

# === FPS LOGGING ===
var log_file: FileAccess
var logging: bool = false
var log_filepath: String = ""

func _ready():
	# Przygotuj nakładkę przyciemnienia (fade)
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color.BLACK
	fade_overlay.color.a = 0
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(fade_overlay)
	
	# Zapisz referencje do skyboxów
	pano_sky = world_env.environment.sky.sky_material
	solid_sky = ProceduralSkyMaterial.new()
	
	# === WebXR initialization ===
	var xr_interface = XRServer.find_interface("WebXR")
	if xr_interface and xr_interface.initialize():
		get_viewport().use_xr = true
		$XROrigin3D.visible = true
		camera.visible = false
		print("WebXR initialized — VR mode")
	else:
		$XROrigin3D.visible = false
		print("WebXR not available — desktop mode")
	
	# === VR controller signals ===
	$XROrigin3D/LeftController.button_pressed.connect(_on_vr_button)
	$XROrigin3D/RightController.button_pressed.connect(_on_vr_button)
	
	# Ustaw początkowy punkt
	_teleport_to(0)

func _process(delta):
	# Aktualizuj FPS
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	
	# Logowanie FPS (jeśli włączone)
	if logging and log_file:
		var cfg = _current_config_string()
		log_file.store_line("%.3f,%d,%d,%s" % [
			Time.get_ticks_msec() / 1000.0,
			Engine.get_frames_per_second(),
			current_point,
			cfg
		])

func _current_config_string() -> String:
	var s = "P%d" % current_point
	for i in range(figures.size()):
		s += "_F%d=%d" % [i+1, int(figures[i].visible)]
	s += "_E=%d" % int(env_distant.visible)
	s += "_T=%d" % int(env_main.visible)
	s += "_R=%d" % int(using_pano)
	return s

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _toggle_figure(0)
			KEY_2: _toggle_figure(1)
			KEY_3: _toggle_figure(2)
			KEY_4: _toggle_figure(3)
			KEY_5: _toggle_figure(4)
			KEY_6: _toggle_figure(5)
			KEY_E: _toggle_tlo()
			KEY_T: _toggle_scena()
			KEY_R: _toggle_skybox()
			KEY_SPACE: _teleport_next()
			KEY_ESCAPE: _teleport_to(0)
			KEY_L: _toggle_logging()

func _toggle_figure(index: int):
	if index < figures.size():
		figures[index].visible = !figures[index].visible

func _toggle_skybox():
	if using_pano:
		world_env.environment.sky.sky_material = solid_sky
		using_pano = false
	else:
		world_env.environment.sky.sky_material = pano_sky
		using_pano = true

func _toggle_tlo():
	env_distant.visible = !env_distant.visible

func _toggle_scena():
	env_main.visible = !env_main.visible

func _teleport_to(point_idx: int):
	if point_idx < 0 or point_idx >= teleport_points.size():
		return
	# Płynne przyciemnienie i przeskok
	var tween = create_tween()
	tween.tween_property(fade_overlay, "color:a", 1.0, 0.3)
	tween.tween_callback(_do_teleport.bind(point_idx))
	tween.tween_property(fade_overlay, "color:a", 0.0, 0.3)

func _do_teleport(point_idx: int):
	# Zatrzymaj poprzednią animację
	if current_point > 0 and current_point <= figures.size():
		var prev_fig = figures[current_point - 1]
		if prev_fig.has_node("AnimationPlayer"):
			prev_fig.get_node("AnimationPlayer").stop()
	
	# Ustaw kamerę (lub XROrigin3D w VR)
	if get_viewport().use_xr:
		$XROrigin3D.global_position = teleport_points[point_idx].global_position
		$XROrigin3D.global_rotation = teleport_points[point_idx].global_rotation
	else:
		camera.global_position = teleport_points[point_idx].global_position
		camera.global_rotation = teleport_points[point_idx].global_rotation
	
	current_point = point_idx
	
	# Odtwórz animację dla nowej figury
	if point_idx > 0 and point_idx <= figures.size():
		var fig = figures[point_idx - 1]
		if fig.has_node("AnimationPlayer"):
			var anim_player = fig.get_node("AnimationPlayer")
			anim_player.play("Rotate_360")
			is_rotating = true
		else:
			is_rotating = false

func _teleport_next():
	var next_p = (current_point + 1) % teleport_points.size()
	_teleport_to(next_p)

func _toggle_logging():
	if not logging:
		log_filepath = "user://fps_log_%d.csv" % Time.get_ticks_msec()
		log_file = FileAccess.open(log_filepath, FileAccess.WRITE)
		log_file.store_line("timestamp,fps,point,config")
		logging = true
		print("Logging STARTED: " + log_filepath)
	else:
		logging = false
		if log_file:
			log_file.close()
		print("Logging STOPPED: " + log_filepath)

# === OBSŁUGA PRZYCISKÓW KONTROLERÓW VR ===
func _on_vr_button(name: String):
	if name == "trigger_click":
		_teleport_next()

# === OBSŁUGA PRZYCISKÓW UI ===
func _on_btn_next_pressed():
	_teleport_next()

func _on_btn_center_pressed():
	_teleport_to(0)

func _on_btn_fig1_pressed():
	_toggle_figure(0)

func _on_btn_fig2_pressed():
	_toggle_figure(1)

func _on_btn_fig3_pressed():
	_toggle_figure(2)

func _on_btn_fig4_pressed():
	_toggle_figure(3)

func _on_btn_fig5_pressed():
	_toggle_figure(4)

func _on_btn_fig6_pressed():
	_toggle_figure(5)

func _on_btn_sky_pressed():
	_toggle_skybox()

func _on_btn_tlo_pressed():
	_toggle_tlo()

func _on_btn_scena_pressed():
	_toggle_scena()

# === Kliknięcia myszką (desktop) ===
func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_viewport().get_mouse_position()
		var from = camera.project_ray_origin(mouse_pos)
		var to = from + camera.project_ray_normal(mouse_pos) * 100
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to)
		var result = space_state.intersect_ray(query)
		if result:
			var hit = result.collider
			for i in range(figures.size()):
				if hit == figures[i] or figures[i].is_ancestor_of(hit):
					_teleport_to(i + 1)
					return
