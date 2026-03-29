extends Control

# Referencias a nodos de UI / pantallas
@onready var narration_label: Label = $NarrationLabel
@onready var background_image: TextureRect = $backgroundImage
@onready var screen_door: TextureRect = $ScreenDoor
@onready var screen_face: TextureRect = $ScreenFace
@onready var screen_mother: TextureRect = $ScreenMother

# Audio
@onready var door_sfx: AudioStreamPlayer = $DoorSfx
@onready var typewriter_sfx: AudioStreamPlayer = $TypewriterSfx

# Capa de fade (pantalla completa)
@onready var fade_rect: ColorRect = $FadeRect

# Ajustes de fade (exportados para poder ajustar desde el Inspector)
@export var intro_fade_in_duration: float = 2.5
@export var to_gameplay_fade_out_duration: float = 3.0

# Texto inicial (monólogo interno). Se imprime carácter a carácter con pausas.
var full_text := "No recuerdo la última vez que sentí algo.\nNada parece tener sentido.\n¿Por qué la gente se esfuerza?\n¿Por qué siguen adelante?\nNada importa..."
var type_speed := 0.05
var pause_short := 0.3
var pause_long := 0.7
var start_delay := 2.0

# Pausa extra y fade solo del label (para cerrar la parte del monólogo)
var fade_delay := 0.8
var fade_duration := 0.7

# Texto de la madre (se muestra mientras se anima la boca)
var mother_text := "¿Vas a pasarte todo el día ahí metido?\n¡Levántate ya y haz algo con tu vida!"

# Secuencias de frames cargadas desde PNG (se cargan al inicio para evitar tirones)
var door_frames: Array[Texture2D] = []
var face_frames: Array[Texture2D] = []
var mother_frames: Array[Texture2D] = []


func _ready() -> void:
	# 1) Fade in inicial (arranca en negro y aparece la escena)
	_setup_fade_rect()
	if fade_rect:
		fade_rect.modulate.a = 1.0
		await _fade_in(intro_fade_in_duration)

	# 2) Pre-carga de animaciones (PNG → memoria)
	load_all_frames()

	# 3) Preparación del texto
	narration_label.visible = true
	narration_label.modulate = Color(1, 1, 1, 1)
	narration_label.z_index = 100
	narration_label.text = ""

	# 4) Estado inicial visible: solo “cama” (background)
	hide_all_screens()
	background_image.visible = true

	# 5) Arranca la intro (texto → puerta → cara → madre → gameplay)
	write_text_intro()


# =========================================================
# FADE (pantalla completa con FadeRect)
# =========================================================

func _setup_fade_rect() -> void:
	if not fade_rect:
		return
	# Se fuerza a cubrir todo el viewport (anchors 0..1 y offsets a 0)
	fade_rect.anchor_left = 0.0
	fade_rect.anchor_top = 0.0
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	fade_rect.offset_left = 0
	fade_rect.offset_top = 0
	fade_rect.offset_right = 0
	fade_rect.offset_bottom = 0


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
# CARGA DE FRAMES (PNG secuenciales)
# =========================================================

func load_all_frames() -> void:
	# Nota: los nombres siguen un patrón door_1.png ... door_13.png, etc.
	door_frames = load_sequence_from_one("res://anim/door/door_%d.png", 13)
	face_frames = load_sequence_from_one("res://anim/face/face_%d.png", 14)
	mother_frames = load_sequence_from_one("res://anim/mother/mother_%d.png", 5)


func load_sequence_from_one(pattern: String, count: int) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for i in range(1, count + 1):
		var path := pattern % i
		var tex: Texture2D = load(path)
		if tex:
			result.append(tex)
		else:
			push_warning("No se pudo cargar: %s" % path)
	return result


# =========================================================
# UTILIDADES VISUALES / AUDIO
# =========================================================

func hide_all_screens() -> void:
	background_image.visible = false
	screen_door.visible = false
	screen_face.visible = false
	screen_mother.visible = false


func play_frames_on_texturerect(target: TextureRect, frames: Array[Texture2D], frame_time: float) -> void:
	# Reproduce una lista de frames en un TextureRect
	for tex in frames:
		target.texture = tex
		await get_tree().create_timer(frame_time).timeout


func _typewriter_on() -> void:
	# El audio se activa solo si no está sonando ya
	if typewriter_sfx and not typewriter_sfx.playing:
		typewriter_sfx.play()


func _typewriter_off() -> void:
	if typewriter_sfx and typewriter_sfx.playing:
		typewriter_sfx.stop()


# Devuelve el tiempo de espera para cada carácter y si ese carácter genera “pausa”
# (en pausas se apaga el sonido de máquina para respetar el ritmo)
func _get_wait_for_char(ch: String) -> Dictionary:
	var wait_time := type_speed
	var is_pause := false

	match ch:
		".":
			wait_time = pause_long
			is_pause = true
		"?", "¿", ",":
			wait_time = pause_short
			is_pause = true
		"\n":
			wait_time = pause_long
			is_pause = true
		_:
			wait_time = type_speed
			is_pause = false

	return {"time": wait_time, "pause": is_pause}


# =========================================================
# INTRO 1: monólogo interno (cama) + sonido máquina de escribir
# =========================================================

func write_text_intro() -> void:
	await get_tree().create_timer(start_delay).timeout

	var current_text := ""
	_typewriter_off()

	for ch in full_text:
		current_text += str(ch)
		narration_label.text = current_text

		var info := _get_wait_for_char(str(ch))
		var wait_time: float = float(info.time)
		var is_pause: bool = bool(info.pause)

		# Máquina solo “mientras escribe” (no durante puntuación / saltos)
		if is_pause:
			_typewriter_off()
		else:
			_typewriter_on()

		await get_tree().create_timer(wait_time).timeout

	# Asegurar apagado al terminar el bloque
	_typewriter_off()

	# Pausa con el texto completo en pantalla
	await get_tree().create_timer(fade_delay).timeout

	# Fade-out del texto (solo del label)
	var tween := create_tween()
	tween.tween_property(narration_label, "modulate:a", 0.0, fade_duration)
	await tween.finished

	# Pausa breve tras desaparecer el texto
	await get_tree().create_timer(0.5).timeout

	# Secuencia visual: puerta → cara → madre
	await play_door_face_mother_sequence()


# =========================================================
# INTRO 2: Puerta → Cara → Madre
# =========================================================

func play_door_face_mother_sequence() -> void:
	# 1) Puerta: animación en bucle por la duración del audio del golpe/intento de abrir
	hide_all_screens()
	screen_door.visible = true

	var door_duration := 0.8
	if door_sfx and door_sfx.stream:
		door_duration = door_sfx.stream.get_length()
		door_sfx.play()

	await play_door_animation_for(door_duration)

	# 2) Cara: animación más lenta (último frame se sostiene)
	hide_all_screens()
	screen_face.visible = true
	await play_face_animation()

	# 3) Madre: texto + animación de boca ligada a cada carácter
	hide_all_screens()
	screen_mother.visible = true

	narration_label.modulate.a = 1.0
	narration_label.text = ""

	await write_mother_text()

	# Transición a gameplay
	await go_to_gameplay()


func play_door_animation_for(duration: float) -> void:
	# Repite la lista de frames hasta completar el tiempo indicado
	if door_frames.is_empty():
		return

	var elapsed := 0.0
	var frame_time := 0.06

	while elapsed < duration:
		for tex in door_frames:
			screen_door.texture = tex
			await get_tree().create_timer(frame_time).timeout
			elapsed += frame_time
			if elapsed >= duration:
				break


func play_face_animation() -> void:
	# 200 ms por frame y el último se queda 1500 ms (para “asentar” la reacción)
	if face_frames.is_empty():
		return

	var last_index := face_frames.size() - 1

	for i in range(face_frames.size()):
		screen_face.texture = face_frames[i]

		var wait_time := 0.2
		if i == last_index:
			wait_time = 1.5

		await get_tree().create_timer(wait_time).timeout


func write_mother_text() -> void:
	# El texto se imprime carácter a carácter y la boca avanza un frame por carácter.
	# La máquina de escribir acompaña el ritmo del texto (se apaga en pausas).
	var current_text := ""
	var mouth_index := 0
	_typewriter_off()

	for ch in mother_text:
		current_text += str(ch)
		narration_label.text = current_text

		if not mother_frames.is_empty():
			screen_mother.texture = mother_frames[mouth_index]
			mouth_index = (mouth_index + 1) % mother_frames.size()

		var info := _get_wait_for_char(str(ch))
		var wait_time: float = float(info.time)
		var is_pause: bool = bool(info.pause)

		if is_pause:
			_typewriter_off()
		else:
			_typewriter_on()

		await get_tree().create_timer(wait_time).timeout

	# Estado final: sonido off y frame neutro
	_typewriter_off()
	if not mother_frames.is_empty():
		screen_mother.texture = mother_frames[0]


# =========================================================
# Transición a escena jugable
# =========================================================

func go_to_gameplay() -> void:
	# Seguridad: no dejar audio de máquina sonando durante el cambio
	_typewriter_off()

	# Fade-out largo de pantalla completa para entrar a gameplay con ritmo lento
	await _fade_out(to_gameplay_fade_out_duration)

	get_tree().change_scene_to_file("res://scenes/main.tscn")
