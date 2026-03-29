extends CharacterBody2D

# Velocidad base del personaje (sin modificadores)
@export var base_speed: float = 120.0

# Factor mínimo de velocidad cuando el ánimo es bajo
@export var min_speed_factor: float = 0.45

# AnimatedSprite2D con las animaciones idle_*/walk_*
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# Última dirección “real” registrada (se usa para decidir el idle)
var last_dir: Vector2 = Vector2.DOWN


func _physics_process(_delta: float) -> void:
	# Se asume que la escena actual es el “main” (Node2D) que expone flags y mood
	var game: Node = get_tree().current_scene as Node

	# 1) Final: se bloquea el control y se fuerza idle_down
	if game != null and ("ending_active" in game) and game.ending_active:
		velocity = Vector2.ZERO
		move_and_slide()
		if anim:
			anim.play("idle_down")
		return

	# 2) Si hay una elección abierta: jugador inmóvil con idle según la última dirección
	if game != null and ("choice_active" in game) and game.choice_active:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation(Vector2.ZERO, false)
		return

	# 3) Bloqueo por secuencia (baile, teletransporte, etc.)
	#    En este caso la animación la controla main.gd, aquí solo se cancela movimiento.
	if game != null and ("player_locked" in game) and game.player_locked:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# -------------------------
	# Movimiento normal
	# -------------------------
	var input_dir: Vector2 = Vector2.ZERO
	input_dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_dir.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")

	var moving: bool = input_dir.length() > 0.1
	if moving:
		last_dir = input_dir.normalized()

	# El ánimo ajusta la velocidad: con ánimo bajo, el personaje se mueve “más pesado”
	var mood_value: float = 20.0
	if game != null and ("mood" in game):
		mood_value = float(game.mood)

	var t: float = clamp(mood_value / 100.0, 0.0, 1.0)
	var mood_factor: float = lerp(min_speed_factor, 1.0, t)

	velocity = input_dir.normalized() * (base_speed * mood_factor)
	move_and_slide()

	_update_animation(input_dir, moving)


func _update_animation(_input_dir: Vector2, moving: bool) -> void:
	var dir: String = _get_dir_name(last_dir)

	if not moving:
		anim.play("idle_%s" % dir)
	else:
		anim.play("walk_%s" % dir)


func _get_dir_name(v: Vector2) -> String:
	# Se prioriza el eje dominante para decidir up/down/left/right
	if abs(v.x) > abs(v.y):
		return "right" if v.x > 0.0 else "left"
	else:
		return "down" if v.y > 0.0 else "up"
