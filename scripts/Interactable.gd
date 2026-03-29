extends Area2D

# Identificador de la interacción (se envía a main.gd)
@export var interaction_name: String = "window"

# Texto que se muestra cuando el jugador puede interactuar
@export var prompt_text: String = "Pulsa para explorar"

# Label opcional que muestra el aviso en pantalla (debe ser hijo del Area2D)
@onready var prompt_label: Label = get_node_or_null("PromptLabel") as Label

# Indica si el jugador está dentro del área de interacción
var player_inside: bool = false

# Evita disparar la interacción cada frame si se mantiene pulsada la tecla E
var _e_was_down: bool = false


func _ready() -> void:
	# Conexión de señales por código para no depender del editor
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	# Preparación del texto de aviso
	if prompt_label:
		prompt_label.visible = false
		prompt_label.text = prompt_text
	else:
		push_warning("Interactable: no se ha encontrado un nodo PromptLabel como hijo.")


func _process(_delta: float) -> void:
	# Si el jugador no está dentro del área, no se procesa la interacción
	if not player_inside:
		_e_was_down = false
		return

	# Si hay una elección activa en el juego, no se permite iniciar otra
	var game: Node = get_tree().current_scene as Node
	if game != null and ("choice_active" in game) and game.choice_active:
		return

	# Interacción con la tecla de aceptar (espacio / enter)
	if Input.is_action_just_pressed("ui_accept"):
		_interact()
		return

	# Interacción alternativa con la tecla E (una sola vez por pulsación)
	var e_down: bool = Input.is_key_pressed(KEY_E)
	if e_down and not _e_was_down:
		_interact()
	_e_was_down = e_down


func _on_body_entered(body: Node) -> void:
	# El área solo reacciona al jugador
	if body.name != "Player":
		return

	player_inside = true
	if prompt_label:
		prompt_label.visible = true
		prompt_label.text = prompt_text


func _on_body_exited(body: Node) -> void:
	# Al salir el jugador, se oculta el aviso
	if body.name != "Player":
		return

	player_inside = false
	_e_was_down = false
	if prompt_label:
		prompt_label.visible = false


func _interact() -> void:
	# Se delega la lógica de la interacción a la escena principal (main.gd)
	var game: Node = get_tree().current_scene as Node
	if game != null and game.has_method("start_interaction"):
		game.start_interaction(interaction_name)
	else:
		push_warning("Interactable: la escena actual no implementa start_interaction().")
