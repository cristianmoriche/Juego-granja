class_name Hueco
extends Control
## Hueco de inventario o barra rápida con ilustración transparente y cantidad.
## Las texturas se comparten mediante la caché de Datos.

signal pulsado(hueco: Hueco, boton: int)

var indice: int = 0
var datos: Dictionary = {}        # {} o {"id": String, "cantidad": int}
var activo: bool = false          # ranura seleccionada de la barra rápida
var marcado: bool = false         # origen de un intercambio en curso
var numero: String = ""           # «1»..«0» en la barra rápida
var interactivo: bool = true
var tam: float = 64.0


func _init(tamano: float = 64.0, es_interactivo: bool = true) -> void:
	tam = tamano
	interactivo = es_interactivo
	focus_mode = Control.FOCUS_ALL if es_interactivo else Control.FOCUS_NONE
	custom_minimum_size = Vector2(tam, tam)
	mouse_filter = Control.MOUSE_FILTER_STOP if es_interactivo else Control.MOUSE_FILTER_IGNORE


func poner(d: Dictionary) -> void:
	datos = d
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactivo:
		return
	if event.is_action_pressed("ui_accept"):
		pulsado.emit(self, MOUSE_BUTTON_LEFT)
		accept_event()
		return
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.pressed and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT):
			pulsado.emit(self, e.button_index)
			accept_event()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var borde := Estilo.COLOR_BORDE_SUAVE
	var fondo := Color(0.07, 0.055, 0.045, 0.88)
	var grosor := 2.0
	if activo:
		borde = Estilo.COLOR_ACENTO
		fondo = Color(0.22, 0.16, 0.08, 0.95)
		grosor = 4.0
	elif marcado:
		borde = Color(0.55, 0.85, 0.95)
		fondo = Color(0.10, 0.18, 0.22, 0.95)
		grosor = 3.0
	elif interactivo and (has_focus() or get_global_rect().has_point(get_global_mouse_position())):
		borde = Estilo.COLOR_BORDE
		fondo = Color(0.16, 0.12, 0.09, 0.95)
	var sb := Estilo.caja(fondo, borde, int(grosor), 6, 0)
	if Ajustes.valores.alto_contraste:
		sb.bg_color = Color.BLACK
		sb.border_color = Color.YELLOW if has_focus() or activo else Color.WHITE
	draw_style_box(sb, r)

	var fuente := Estilo.fuente()
	if not datos.is_empty():
		var id := str(datos.get("id", ""))
		var lado := minf(size.x, size.y) * 0.82
		var caja_icono := Rect2((size.x - lado) * 0.5, (size.y - lado) * 0.5 - 2.0, lado, lado)
		draw_texture_rect(Datos.icono(Datos.id_icono(id, Juego.nivel(id))), caja_icono, false)
		if str(datos.get("calidad", "")) == "baja":
			var pt := Vector2(size.x - 9.0, 9.0)
			draw_circle(pt, 5.2, Color(0.15, 0.08, 0.04, 0.92))
			draw_circle(pt, 3.8, Color(0.88, 0.44, 0.18, 1.0))
		var cant := int(datos.get("cantidad", 1))
		if cant > 1:
			var t := str(cant)
			var tt := int(size.x * 0.27 * float([1.0, 1.18, 1.35][int(Ajustes.valores.texto)]))
			var w := fuente.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tt)
			var pos := Vector2(size.x - w.x - 5.0, size.y - 5.0)
			draw_string_outline(fuente, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tt, 5, Color(0, 0, 0, 0.9))
			draw_string(fuente, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tt, Color.WHITE)
	if not numero.is_empty():
		var tn := int(size.x * 0.24 * float([1.0, 1.18, 1.35][int(Ajustes.valores.texto)]))
		draw_string_outline(fuente, Vector2(5, tn + 1), numero, HORIZONTAL_ALIGNMENT_LEFT, -1, tn, 4, Color(0, 0, 0, 0.9))
		draw_string(fuente, Vector2(5, tn + 1), numero, HORIZONTAL_ALIGNMENT_LEFT, -1, tn, Estilo.COLOR_TEXTO_SUAVE if not activo else Estilo.COLOR_ACENTO)
