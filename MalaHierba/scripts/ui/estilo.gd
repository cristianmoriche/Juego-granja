class_name Estilo
extends RefCounted
## Colores, tamaños y tema común de toda la interfaz (HUD, paneles, menús).
## Estilo sobrio: paneles oscuros semitransparentes con borde cálido y letra grande.

const COLOR_FONDO := Color(0.09, 0.07, 0.06, 0.90)
const COLOR_FONDO_SUAVE := Color(0.16, 0.12, 0.10, 0.92)
const COLOR_BORDE := Color(0.86, 0.62, 0.30)
const COLOR_BORDE_SUAVE := Color(0.55, 0.42, 0.26)
const COLOR_TEXTO := Color(0.97, 0.94, 0.87)
const COLOR_TEXTO_SUAVE := Color(0.76, 0.71, 0.63)
const COLOR_ACENTO := Color(0.98, 0.80, 0.42)
const COLOR_BUENO := Color(0.55, 0.82, 0.45)
const COLOR_MALO := Color(0.90, 0.38, 0.30)

const TAM_TEXTO := 22
const TAM_PEQUENO := 17
const TAM_GRANDE := 28
const TAM_TITULO := 34

static var _tema: Theme = null
static var _fuente: Font = null


## Fuente del sistema (Segoe UI en Windows) con la de Godot como respaldo.
static func fuente() -> Font:
	if _fuente == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Calibri", "Arial", "Verdana"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_fuente = f
	return _fuente


static func caja(fondo: Color = COLOR_FONDO, borde: Color = COLOR_BORDE, grosor: int = 2, radio: int = 8, margen: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(grosor)
	s.set_corner_radius_all(radio)
	s.content_margin_left = margen
	s.content_margin_right = margen
	s.content_margin_top = margen * 0.7
	s.content_margin_bottom = margen * 0.7
	s.anti_aliasing = true
	return s


## Tema compartido: botones, etiquetas, barras de progreso, líneas de texto y desplazamiento.
static func tema() -> Theme:
	if _tema != null:
		return _tema
	var t := Theme.new()
	t.default_font = fuente()
	t.default_font_size = TAM_TEXTO

	t.set_font_size("font_size", "Label", TAM_TEXTO)
	t.set_color("font_color", "Label", COLOR_TEXTO)
	t.set_font_size("normal_font_size", "RichTextLabel", TAM_TEXTO)
	t.set_color("default_color", "RichTextLabel", COLOR_TEXTO)

	t.set_font_size("font_size", "Button", TAM_TEXTO)
	t.set_color("font_color", "Button", COLOR_TEXTO)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", COLOR_ACENTO)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.42))
	t.set_stylebox("normal", "Button", caja(Color(0.20, 0.15, 0.11, 0.95), COLOR_BORDE_SUAVE, 2, 6, 14))
	t.set_stylebox("hover", "Button", caja(Color(0.32, 0.23, 0.14, 0.97), COLOR_BORDE, 2, 6, 14))
	t.set_stylebox("pressed", "Button", caja(Color(0.42, 0.29, 0.14, 1.0), COLOR_ACENTO, 2, 6, 14))
	t.set_stylebox("focus", "Button", caja(Color(0.32, 0.23, 0.14, 0.97), COLOR_ACENTO, 3, 6, 14))
	t.set_stylebox("disabled", "Button", caja(Color(0.14, 0.11, 0.09, 0.8), Color(0.3, 0.26, 0.2), 2, 6, 14))

	t.set_font_size("font_size", "LineEdit", TAM_GRANDE)
	t.set_color("font_color", "LineEdit", COLOR_TEXTO)
	t.set_color("caret_color", "LineEdit", COLOR_ACENTO)
	t.set_color("font_placeholder_color", "LineEdit", COLOR_TEXTO_SUAVE)
	t.set_stylebox("normal", "LineEdit", caja(Color(0.05, 0.04, 0.03, 0.95), COLOR_BORDE_SUAVE, 2, 6, 12))
	t.set_stylebox("focus", "LineEdit", caja(Color(0.05, 0.04, 0.03, 0.95), COLOR_ACENTO, 3, 6, 12))

	t.set_stylebox("panel", "PanelContainer", caja())
	t.set_stylebox("panel", "Panel", caja())

	t.set_stylebox("background", "ProgressBar", caja(Color(0.05, 0.04, 0.03, 0.85), COLOR_BORDE_SUAVE, 2, 5, 0))
	t.set_stylebox("fill", "ProgressBar", caja(COLOR_BUENO, COLOR_BUENO, 0, 4, 0))

	var fondo_scroll := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", fondo_scroll)
	_tema = t
	return t


static func etiqueta(texto: String, tam: int = TAM_TEXTO, color: Color = COLOR_TEXTO) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func boton(texto: String, ancho: float = 0.0) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_ALL
	if ancho > 0.0:
		b.custom_minimum_size = Vector2(ancho, 48)
	else:
		b.custom_minimum_size = Vector2(0, 48)
	return b


## Dinero con separador de miles español: 1234 -> «1.234 €».
static func euros(n: int) -> String:
	var signo := "-" if n < 0 else ""
	var s := str(absi(n))
	var salida := ""
	var cuenta := 0
	for i in range(s.length() - 1, -1, -1):
		if cuenta == 3:
			salida = "." + salida
			cuenta = 0
		salida = s[i] + salida
		cuenta += 1
	return signo + salida + " €"


static func color_html(hex: String, defecto: Color = Color(0.6, 0.6, 0.6)) -> Color:
	if hex.is_empty():
		return defecto
	return Color.html(hex)


## Texto legible sobre un color de fondo (negro o blanco según el brillo).
static func contraste(c: Color) -> Color:
	var luz := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	return Color(0.08, 0.06, 0.05) if luz > 0.55 else Color(0.97, 0.95, 0.9)


## Aplica el borde y fondo del panel a un Control que lo admita (PanelContainer o Panel).
static func estilo_panel(p: Control, fondo: Color = COLOR_FONDO, borde: Color = COLOR_BORDE, margen: int = 14) -> void:
	p.add_theme_stylebox_override("panel", caja(fondo, borde, 2, 8, margen))
