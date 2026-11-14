# Herramienta de una sola vez: escribe el mapa de entradas en project.godot.
# Se ejecuta con: godot.ps1 --headless --path <proyecto> --script res://pruebas/configurar_entradas.gd
extends SceneTree


func _tecla(codigo: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = codigo
	e.device = -1
	return e


func _tecla_izquierda(codigo: Key) -> InputEventKey:
	var e := _tecla(codigo)
	e.location = KEY_LOCATION_LEFT
	return e


func _raton(boton: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = boton
	e.device = -1
	return e


func _init() -> void:
	var acciones: Dictionary = {
		"mover_izquierda": [_tecla(KEY_A), _tecla(KEY_LEFT)],
		"mover_derecha": [_tecla(KEY_D), _tecla(KEY_RIGHT)],
		"mover_arriba": [_tecla(KEY_W), _tecla(KEY_UP)],
		"mover_abajo": [_tecla(KEY_S), _tecla(KEY_DOWN)],
		"correr": [_tecla(KEY_SHIFT)],
		"interactuar": [_tecla(KEY_E)],
		"usar": [_raton(MOUSE_BUTTON_LEFT)],   # M2: el Espacio pasó a «saltar»
		"saltar": [_tecla(KEY_SPACE)],
		"agachar": [_tecla_izquierda(KEY_CTRL)],
		"inventario": [_tecla(KEY_I), _tecla(KEY_TAB)],
		"pausa": [_tecla(KEY_ESCAPE)],
		"pantalla_completa": [_tecla(KEY_F11)],
		"ranura_1": [_tecla(KEY_1)],
		"ranura_2": [_tecla(KEY_2)],
		"ranura_3": [_tecla(KEY_3)],
		"ranura_4": [_tecla(KEY_4)],
		"ranura_5": [_tecla(KEY_5)],
		"ranura_6": [_tecla(KEY_6)],
		"ranura_7": [_tecla(KEY_7)],
		"ranura_8": [_tecla(KEY_8)],
		"ranura_9": [_tecla(KEY_9)],
		"ranura_10": [_tecla(KEY_0)],
	}
	for nombre: String in acciones:
		ProjectSettings.set_setting("input/" + nombre, {"deadzone": 0.2, "events": acciones[nombre]})
	var err := ProjectSettings.save()
	print("Entradas guardadas, codigo ", err)
	quit(err)
