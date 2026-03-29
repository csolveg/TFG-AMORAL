extends Control

# =========================================================
# TRANSICIÓN VISUAL
# =========================================================

# Duración del fade-in inicial (de negro a la portada)
@export var fade_in_duration: float = 2.8

# =========================================================
# TEXTO FINAL
# =========================================================

# Duración del fade-in del texto final
@export var text_fade_in_duration: float = 2.0

# Pequeña pausa tras aparecer la portada antes de mostrar el texto
@export var text_delay_after_fade: float = 0.6

# =========================================================
# AMBIENTE
# =========================================================

# Volumen inicial del ambiente (al entrar en la escena)
@export var ambient_start_db: float = -14.0

# Volumen del ambiente mientras aparece el texto (un poco más discreto)
@export var ambient_during_text_db: float = -22.0

# Duración del ajuste de volumen del ambiente
@export var ambient_fade_db_duration: float = 2.5


@onready var fade_rect: ColorRect = $FadeRect
@onready var ending_label: Label = $EndingLabel
@onready var ambient_player: AudioStreamPlayer = $AmbientPlayer


func _ready() -> void:
	# 1) Ambiente: se inicia en bucle (si hay stream asignado)
	if ambient_player and ambient_player.stream:
		ambient_player.volume_db = ambient_start_db
		ambient_player.play()

	# 2) Arranque visual: la escena empieza en negro y se hace fade-in
	if fade_rect:
		fade_rect.modulate.a = 1.0
		await _fade_in(fade_in_duration)

	# 3) Preparación del texto final: invisible al inicio para poder hacer fade-in
	if ending_label:
		ending_label.text = "No todo está resuelto.\nPero hoy he dado un paso distinto.\n\nQuizá no sea el final de nada.\nQuizá sea, por fin, un comienzo."
		ending_label.modulate.a = 0.0

	# Pausa breve tras aparecer la portada antes de mostrar el texto
	await get_tree().create_timer(text_delay_after_fade).timeout

	# 4) Mientras entra el texto, se baja un poco el ambiente para que no compita con la lectura
	_fade_ambient_to(ambient_during_text_db, ambient_fade_db_duration)

	# 5) Fade-in lento del texto final
	await _fade_label_in(text_fade_in_duration)


func _fade_in(duration: float) -> void:
	# Fade de pantalla completa (negro -> transparente)
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, duration)
	await tween.finished


func _fade_label_in(duration: float) -> void:
	# Fade-in del texto final
	if not ending_label:
		return
	var tween := create_tween()
	tween.tween_property(ending_label, "modulate:a", 1.0, duration)
	await tween.finished


func _fade_ambient_to(target_db: float, duration: float) -> void:
	# Ajuste progresivo del volumen del ambiente
	if not ambient_player:
		return
	var tween := create_tween()
	tween.tween_property(ambient_player, "volume_db", target_db, duration)
