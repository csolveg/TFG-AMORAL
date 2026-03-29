extends Control

# Capa de fade para transicionar de la pantalla de título a la intro
@onready var fade_rect: ColorRect = $FadeRect

# Duración del fade-out al iniciar nueva partida (ajustable desde el Inspector)
@export var fade_out_duration: float = 2.0


func _ready() -> void:
	# FadeRect configurado como overlay a pantalla completa (arranca transparente)
	_setup_fade_rect()

	# Búsqueda de botones por nombre (evita depender de la posición exacta en el árbol)
	var new_btn: Button = find_child("NewGameButton", true, false) as Button
	var load_btn: Button = find_child("LoadGameButton", true, false) as Button
	var credits_btn: Button = find_child("CreditsButton", true, false) as Button

	# Si no existe el botón de nueva partida, la escena no es funcional
	if new_btn == null:
		push_error("No se encontró un nodo llamado 'NewGameButton' en esta escena.")
		return

	# Conexión por código para asegurar que el botón siempre llama al método correcto
	if not new_btn.pressed.is_connected(_on_new_game_pressed):
		new_btn.pressed.connect(_on_new_game_pressed)

	# Dejar el foco en el primer botón para navegar con teclado/mandos
	new_btn.grab_focus()

	# En esta demo no existe “cargar partida”, se deja desactivado si está el botón
	if load_btn:
		load_btn.disabled = true
		load_btn.text = "Cargar partida (demo)"

	# Créditos: previsto para una versión posterior (se conectará cuando esté implementado)
	# if credits_btn:
	# 	credits_btn.pressed.connect(_on_credits_pressed)


func _on_new_game_pressed() -> void:
	# Transición suave: oscurecer y cargar la escena de intro
	await _fade_out()
	get_tree().change_scene_to_file("res://scenes/start_scene.tscn")


func _setup_fade_rect() -> void:
	if not fade_rect:
		return

	# Asegura que el ColorRect cubre toda la pantalla
	fade_rect.anchor_left = 0.0
	fade_rect.anchor_top = 0.0
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	fade_rect.offset_left = 0
	fade_rect.offset_top = 0
	fade_rect.offset_right = 0
	fade_rect.offset_bottom = 0

	# Arranca transparente (pantalla visible)
	fade_rect.modulate.a = 0.0


func _fade_out() -> void:
	if not fade_rect:
		return
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, fade_out_duration)
	await tween.finished


# Créditos (pendiente):
# func _on_credits_pressed() -> void:
# 	pass
