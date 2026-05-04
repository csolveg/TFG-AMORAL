extends Node2D

# =========================================================
# ESTADO PRINCIPAL (ánimo / gameplay)
# =========================================================

# Ánimo actual (0..100). Afecta a velocidad del jugador y activa el cierre al superar el umbral.
@export var mood: float = 40.0

# Ajuste fino para colocar al personaje dentro de la cama cuando se teletransporta
@export var bed_offset: Vector2 = Vector2.ZERO

# Duración por defecto del baile si no hay stream asignado a la música
@export var dance_fallback_seconds: float = 6.0

# =========================================================
# FINAL (cierre de la demo)
# =========================================================

# Umbral que activa la secuencia final (no hace falta llegar a 100)
@export var mood_max_value: float = 75.0

# Fade-out largo hacia la escena final
@export var ending_fade_out_duration: float = 7.0

# Ruta de la escena final (portada sin menú + texto final)
@export var ending_scene_path: String = "res://scenes/ending_scene.tscn"

# Tiempo que se deja sonar el tono de llamada antes de iniciar el fade-out
@export var call_sfx_lead_in: float = 0.9


# =========================================================
# HUD / UI
# =========================================================

@onready var mood_bar: ProgressBar = $HUD/MoodBar

# Panel de elección (bocadillo)
@onready var choice_panel: Panel = $HUD/ChoicePanel
@onready var prompt_label: Label = $HUD/ChoicePanel/PromptLabel
@onready var option_a: Button = $HUD/ChoicePanel/Options/OptionA
@onready var option_b: Button = $HUD/ChoicePanel/Options/OptionB

# Capa de fade (overlay en HUD)
@onready var fade_rect: ColorRect = $HUD/FadeRect


# =========================================================
# AUDIO
# =========================================================

@onready var breath_sfx: AudioStreamPlayer = get_node_or_null("BreathSfx") as AudioStreamPlayer
@onready var music_player: AudioStreamPlayer = get_node_or_null("MusicPlayer") as AudioStreamPlayer
@onready var sad_music_player: AudioStreamPlayer = get_node_or_null("SadMusicPlayer") as AudioStreamPlayer
@onready var call_sfx: AudioStreamPlayer = get_node_or_null("CallSfx") as AudioStreamPlayer
@onready var success_sfx: AudioStreamPlayer = get_node_or_null("SuccessSfx") as AudioStreamPlayer


# =========================================================
# PUNTOS DE ESCENA (markers)
# =========================================================

@onready var bed_spot: Node2D = get_node_or_null("BedSpot") as Node2D
@onready var door_return_spot: Node2D = get_node_or_null("DoorReturnSpot") as Node2D


# =========================================================
# FLAGS DE CONTROL
# =========================================================

# Hay una elección abierta (bloquea iniciar otras interacciones)
var choice_active: bool = false

# Bloqueo de jugador para secuencias (baile, cama, paseo, etc.)
var player_locked: bool = false

# Durante el minijuego de baile, se permiten animaciones aunque haya panel visible
var dance_minigame_active: bool = false

# Bloqueo final: ya no se permite interactuar ni mover al jugador
var ending_active: bool = false


# =========================================================
# INTERNOS
# =========================================================

# Datos de la elección actual (texto, acciones y cambios de ánimo)
var _pending: Dictionary = {}

# 0 = opción A, 1 = opción B (para control por teclado)
var _choice_index: int = 0

# Pequeño cooldown tras cerrar una elección (evita doble pulsación)
var _interaction_cooldown: float = 0.0

# Evita disparar varias veces la secuencia final
var _ending_triggered: bool = false


func _ready() -> void:
	_update_mood_bar()

	# El panel de elección empieza oculto
	if choice_panel:
		choice_panel.visible = false

	# Conexión de botones (también se puede disparar por teclado)
	if option_a:
		option_a.pressed.connect(func(): _apply_choice("a"))
	if option_b:
		option_b.pressed.connect(func(): _apply_choice("b"))

	# Por si el ánimo inicial ya supera el umbral
	_check_mood_max()


func _process(delta: float) -> void:
	# Control de cooldown tras cerrar una elección
	if _interaction_cooldown > 0.0:
		_interaction_cooldown = max(0.0, _interaction_cooldown - delta)


func _unhandled_input(event: InputEvent) -> void:
	# El control por teclado solo está activo cuando el panel de elección está visible
	if not choice_active:
		return

	# Si solo hay una opción visible, se acepta con ui_accept
	var only_one := option_b == null or not option_b.visible
	if only_one:
		if event.is_action_pressed("ui_accept"):
			_apply_choice("a")
			get_viewport().set_input_as_handled()
		return

	# Con dos opciones: flechas para escoger y ui_accept para confirmar
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_choice_index = 0
		_update_choice_highlight()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_choice_index = 1
		_update_choice_highlight()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept"):
		if _choice_index == 0:
			_apply_choice("a")
		else:
			_apply_choice("b")
		get_viewport().set_input_as_handled()


# =========================================================
# ÁNIMO
# =========================================================

func change_mood(delta: float) -> void:
	# Ajuste y clamp del ánimo
	mood = clamp(mood + delta, 0.0, 100.0)
	_update_mood_bar()
	_check_mood_max()


func _update_mood_bar() -> void:
	if mood_bar:
		mood_bar.value = mood

		var fill_style := mood_bar.get_theme_stylebox("fill")
		if fill_style is StyleBoxFlat:
			var style := fill_style.duplicate() as StyleBoxFlat

			if mood <= 25.0:
				style.bg_color = Color(0.85, 0.4, 0.4)
			elif mood <= 55.0:
				style.bg_color = Color(0.95, 0.8, 0.4)
			elif mood <= 75.0:
				style.bg_color = Color(0.6, 0.9, 0.5)
			else:
				style.bg_color = Color(0.45, 0.8, 1.0)

			mood_bar.add_theme_stylebox_override("fill", style)


# =========================================================
# SISTEMA DE ELECCIONES
# =========================================================

func show_choice(data: Dictionary) -> void:
	_pending = data
	choice_active = true
	_choice_index = 0

	if prompt_label:
		prompt_label.text = str(_pending.get("prompt", ""))

	# Opción A siempre visible
	if option_a:
		option_a.text = str(_pending.get("a_text", "Opción A"))
		option_a.visible = true

	# Opción B opcional (si viene vacía, se oculta)
	if option_b:
		var bt := str(_pending.get("b_text", ""))
		if bt.strip_edges() == "":
			option_b.visible = false
		else:
			option_b.text = bt
			option_b.visible = true

	# El panel se coloca cerca del jugador
	if choice_panel:
		choice_panel.visible = true
		position_choice_near_player()

	_update_choice_highlight()


# Mensaje “simple” reutilizando el sistema de elección (una sola opción)
func show_message(message: String, button_text: String = "Vale") -> void:
	show_choice({
		"prompt": message,
		"a_text": button_text,
		"b_text": "",
		"a_mood": 0.0,
		"b_mood": 0.0,
	})


func _update_choice_highlight() -> void:
	if option_a == null:
		return

	# Con una única opción visible, no hace falta resaltar nada
	if option_b == null or not option_b.visible:
		option_a.modulate = Color(1, 1, 1, 1)
		return

	# Con dos opciones, se “apaga” la que no está seleccionada
	if _choice_index == 0:
		option_a.modulate = Color(1, 1, 1, 1)
		option_b.modulate = Color(1, 1, 1, 0.65)
	else:
		option_b.modulate = Color(1, 1, 1, 1)
		option_a.modulate = Color(1, 1, 1, 0.65)


func _close_choice() -> void:
	if choice_panel:
		choice_panel.visible = false

	choice_active = false
	_pending = {}
	_interaction_cooldown = 0.15


func _apply_choice(which: String) -> void:
	# La elección puede modificar el ánimo y/o disparar una acción posterior
	var delta: float = 0.0
	var action: String = ""

	if which == "a":
		delta = float(_pending.get("a_mood", 0.0))
		action = str(_pending.get("a_action", ""))
	else:
		delta = float(_pending.get("b_mood", 0.0))
		action = str(_pending.get("b_action", ""))

	_close_choice()
	change_mood(delta)

	if action != "":
		run_action(action)


# =========================================================
# INTERACCIONES (se llaman desde Interactable.gd)
# =========================================================

func start_interaction(interaction_name: String) -> void:
	# No se inicia interacción si hay elección activa, cooldown, bloqueo de secuencia o final
	if choice_active or _interaction_cooldown > 0.0 or player_locked or ending_active:
		return

	match interaction_name:
		"window":
			show_choice({
				"prompt": "Podría asomarme un momento.\nNo para “arreglar nada”, solo para recordar que el mundo sigue ahí.\nQuizá respirar hondo me devuelva un poco de espacio por dentro.",
				"a_text": "Asomarme y respirar",
				"b_text": "Hoy no puedo",
				"a_mood": +6.0,
				"b_mood": -3.0,
				"a_action": "window_breath",
			})

		"mobile":
			show_choice({
				"prompt": "Tengo mensajes de mis amigos.\nHace tiempo que no saben de mí… y me da vergüenza aparecer ahora.\nPero quizá bastaría con decir la verdad: que no estoy bien, y que me cuesta.",
				"a_text": "Contestar",
				"b_text": "No contestar",
				"a_mood": +8.0,
				"b_mood": -6.0,
				"a_action": "mobile_after",
			})

		"cassette":
			show_choice({
				"prompt": "Puedo poner música.\nA veces el cuerpo entiende lo que la cabeza no puede.\nTal vez moverme un poco me saque del bloqueo… o tal vez hoy necesite bajar el ruido.",
				"a_text": "Música y bailar",
				"b_text": "Música triste y cama",
				"a_mood": +7.0,
				"b_mood": -4.0,
				"a_action": "cassette_minigame",
				"b_action": "cassette_sad_bed",
			})

		"door":
			if mood < 50.0:
				show_message("Salir ahora mismo se siente demasiado grande.")
				return

			show_choice({
				"prompt": "Salir un rato puede dar miedo.\nPero también sé que quedarme aquí alimenta el bucle.\nNo necesito una gran salida: solo dar una vuelta corta y volver.",
				"a_text": "Salir a pasear",
				"b_text": "Quedarme en casa",
				"a_mood": +10.0,
				"b_mood": -5.0,
				"a_action": "door_walk_return",
				"b_action": "door_no",
			})

		"bed":
			show_choice({
				"prompt": "La cama me llama.\nA veces descansar es cuidado… y otras veces es esconderme.\nPuedo tumbarme un momento, o puedo quedarme de pie y sostener lo que siento.",
				"a_text": "Acostarme",
				"b_text": "No ahora",
				"a_mood": 0.0,
				"b_mood": 0.0,
				"a_action": "bed_lie",
			})


# =========================================================
# ACCIONES (después de una elección)
# =========================================================

func run_action(action: String) -> void:
	match action:
		"window_breath":
			if breath_sfx:
				breath_sfx.play()

		"mobile_after":
			show_message("Me contestan rápido.\nDicen que se pasan un día a verme y echamos unos videojuegos.\nNo tengo que estar “bien” para que vengan.")

		"cassette_minigame":
			await _run_dance_minigame()

		"cassette_sad_bed":
			await _run_sad_bed_sequence()

		"door_walk_return":
			await _run_door_walk_sequence()

		"door_no":
			show_message("Ahora mismo no.\nCuando esté un poco mejor, saldré a pasear.")

		"bed_lie":
			if mood < 30.0:
				change_mood(+5.0)
				show_message("Descansar también puede ser una forma de cuidado.")
			else:
				change_mood(-4.0)
				show_message("Esta vez tumbarme se parece más a esconderme.")
			await _run_bed_sequence()

		"call_psychologist":
			await _go_to_ending_with_call()


# =========================================================
# SECUENCIA FINAL (respirar → texto → llamada → escena final)
# =========================================================

func _check_mood_max() -> void:
	if _ending_triggered:
		return
	if mood < mood_max_value:
		return

	_ending_triggered = true
	await _trigger_ending_sequence()


func _trigger_ending_sequence() -> void:
	ending_active = true
	player_locked = true

	# El jugador se queda quieto y se fuerza idle_down (el script del Player lo mantiene)
	_pose_player_idle_down()

	# Respiración antes de mostrar el mensaje final
	await _play_breath_and_wait()

	# Se vuelve a forzar idle_down por seguridad visual
	_pose_player_idle_down()

	var msg := "No ha sido magia. Han sido pequeños pasos.\n" \
		+ "Y ahora, por primera vez en mucho tiempo, lo veo claro:\n" \
		+ "esto me supera… y no tengo por qué hacerlo solo.\n" \
		+ "Necesito ayuda profesional."

	show_choice({
		"prompt": msg,
		"a_text": "Llamar a mi psicóloga",
		"b_text": "",
		"a_mood": 0.0,
		"b_mood": 0.0,
		"a_action": "call_psychologist",
	})


func _play_breath_and_wait() -> void:
	if breath_sfx == null:
		return

	# Si el stream no es loop, se puede esperar al "finished"
	breath_sfx.play()

	if breath_sfx.stream and breath_sfx.stream.get_length() > 0.0:
		await breath_sfx.finished
	else:
		await get_tree().create_timer(1.5).timeout


func _pose_player_idle_down() -> void:
	var player := get_node_or_null("Player")
	if player == null:
		return

	var anim: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D")
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("idle_down"):
		anim.play("idle_down")


func _go_to_ending_with_call() -> void:
	# Se reproduce el tono de llamada antes del fundido a negro
	if call_sfx:
		call_sfx.play()

	if call_sfx_lead_in > 0.0:
		await get_tree().create_timer(call_sfx_lead_in).timeout

	await _fade_out(ending_fade_out_duration)

	var err := get_tree().change_scene_to_file(ending_scene_path)
	if err != OK:
		push_error("No se pudo cargar la escena final: " + ending_scene_path + " (error " + str(err) + ")")
		await _fade_in(0.8)


# =========================================================
# BAILE (secuencia simple de animaciones mientras suena música)
# =========================================================

func _run_dance_sequence() -> void:
	player_locked = true

	var dur: float = dance_fallback_seconds
	if music_player:
		music_player.play()
		if music_player.stream:
			dur = max(0.5, float(music_player.stream.get_length()))

	# Orden de frames pensado como “baile” (alternando laterales y algún paso hacia abajo)
	var dance_order := [
		"walk_left2", "walk_left", "walk_left3",
		"walk_right2", "walk_right", "walk_right3",
		"walk_down2", "walk_down", "walk_down3",
	]

	var step_time := 0.18
	var start_time := Time.get_ticks_msec()

	while (Time.get_ticks_msec() - start_time) / 1000.0 < dur:
		for anim_name in dance_order:
			_pose_anim(anim_name)
			await get_tree().create_timer(step_time).timeout

	_pose_anim("idle_down")
	player_locked = false


func _pose_anim(anim_name: String) -> void:
	var player := get_node_or_null("Player")
	if player == null:
		return

	var anim: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D")
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation(anim_name):
		anim.play(anim_name)


# =========================================================
# CAMA / PUERTA (teleports con fade)
# =========================================================

func _run_bed_sequence() -> void:
	await _fade_out(0.6)
	_teleport_player_to(bed_spot, bed_offset)
	_pose_anim("idle_right")
	await _fade_in(0.6)


func _run_door_walk_sequence() -> void:
	await _fade_out(1.2)
	_teleport_player_to(door_return_spot, Vector2.ZERO)
	_pose_anim("idle_right")
	await _fade_in(1.0)


func _run_sad_bed_sequence() -> void:
	# Música triste y teletransporte a cama
	if sad_music_player:
		sad_music_player.play()

	await _fade_out(0.8)
	_teleport_player_to(bed_spot, bed_offset)
	_pose_anim("idle_right")
	await _fade_in(0.8)

	# Se mantiene un rato la música y se detiene
	await get_tree().create_timer(5.0).timeout
	if sad_music_player:
		sad_music_player.stop()


func _teleport_player_to(target: Node2D, offset: Vector2) -> void:
	if target == null:
		return

	var player: Node2D = get_node_or_null("Player")
	if player:
		player.global_position = target.global_position + offset


# =========================================================
# FADE (pantalla completa)
# =========================================================

func _fade_out(duration: float) -> void:
	if not fade_rect:
		return
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, duration)
	await tween.finished


func _fade_in(duration: float) -> void:
	if not fade_rect:
		return
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, duration)
	await tween.finished


# =========================================================
# POSICIÓN DEL BOCADILLO (cerca del jugador en pantalla)
# =========================================================

func position_choice_near_player() -> void:
	if not choice_panel:
		return

	var player: Node2D = get_node_or_null("Player")
	if player == null:
		return

	var cam := get_viewport().get_camera_2d()
	var viewport_size := get_viewport_rect().size

	# Conversión de coordenadas mundo → pantalla (teniendo en cuenta cámara y zoom)
	var screen_pos: Vector2
	if cam:
		screen_pos = ((player.global_position - cam.get_screen_center_position()) / cam.zoom) + (viewport_size * 0.5)
	else:
		screen_pos = player.global_position

	# Se intenta colocar arriba-izquierda del personaje, y si no cabe, se ajusta
	var margin := 12.0
	var panel_size := choice_panel.size

	var pos := screen_pos + Vector2(-panel_size.x - margin, -panel_size.y - margin)

	if pos.x < margin:
		pos.x = screen_pos.x + margin
	if pos.y < margin:
		pos.y = screen_pos.y + margin

	pos.x = clamp(pos.x, margin, viewport_size.x - panel_size.x - margin)
	pos.y = clamp(pos.y, margin, viewport_size.y - panel_size.y - margin)

	choice_panel.position = pos
	
func _run_dance_minigame() -> void:
	dance_minigame_active = true
	player_locked = true
	if music_player:
		music_player.play()

	var directions = ["left", "right", "up", "down"]
	var correct = 0
	var total = 9
	var dance_order := [
		"walk_left2", "walk_left", "walk_left3",
		"walk_right2", "walk_right", "walk_right3",
		"walk_down2", "walk_down", "walk_down3"]
	var previous_dir = ""

	for i in range(total):
		_pose_anim(dance_order[i % dance_order.size()])
		var dir = directions[randi() % directions.size()]

		while i > 0 and dir == previous_dir:
			dir = directions[randi() % directions.size()]

		previous_dir = dir

		show_message(
			"SIGUE EL RITMO\n\n" +
			_direction_to_text(dir) +
			"\n\nAciertos: " + str(correct) + " / " + str(total)
		)

		var success = await _wait_for_direction(dir, 0.75)

		if success:
			correct += 1

			if success_sfx:
				success_sfx.play()

			show_message(
				"SIGUE EL RITMO\n\n" +
				_direction_to_text(dir) +
				"\n\nAciertos: " + str(correct) + " / " + str(total) +
				"\n\nBIEN"
			)
			await get_tree().create_timer(0.30).timeout
		else:
			await get_tree().create_timer(0.30).timeout

	if music_player:
		music_player.stop()

	

	if correct == total:
		change_mood(10)
		show_message("Por un momento, el cuerpo ha ido por delante del miedo.")
	elif correct >= 7:
		change_mood(7)
		show_message("No ha sido perfecto, pero moverme me ha ayudado.")
	elif correct >= 4:
		change_mood(4)
		show_message("Me costó seguir el ritmo, pero lo intenté.")
	else:
		change_mood(1)
		show_message("Hoy incluso bailar pesa… pero probarlo ya cuenta.")
		
	dance_minigame_active = false
	_pose_anim("idle_down")
	player_locked = false
		
func _wait_for_direction(dir: String, time_limit: float) -> bool:

	var timer = 0.0

	while timer < time_limit:

		await get_tree().process_frame
		timer += get_process_delta_time()

		if dir == "left" and Input.is_action_just_pressed("ui_left"):
			return true
		if dir == "right" and Input.is_action_just_pressed("ui_right"):
			return true
		if dir == "up" and Input.is_action_just_pressed("ui_up"):
			return true
		if dir == "down" and Input.is_action_just_pressed("ui_down"):
			return true

	return false
func _direction_to_text(dir: String) -> String:
	match dir:
		"left":
			return "IZQUIERDA"
		"right":
			return "DERECHA"
		"up":
			return "ARRIBA"
		"down":
			return "ABAJO"
		_:
			return "?"
