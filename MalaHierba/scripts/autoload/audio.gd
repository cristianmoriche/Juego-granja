extends Node
## Autoload «Audio» (T07): gestiona música, ambiente y efectos de sonido en los buses
## Musica, Ambiente y Efectos, con fundidos suaves entre zonas.

const CARPETA := "res://assets/audio/"
const BUSES := ["Musica", "Efectos", "Ambiente"]
const POOL_EFECTOS := 8
const DURACION_FUNDIDO := 0.8

var ultimo_efecto: String = ""
var musica_actual: String = ""
var ambiente_actual: String = ""
var conteo_efectos: Dictionary = {}

var _streams: Dictionary = {}
var _mus_a: AudioStreamPlayer
var _mus_b: AudioStreamPlayer
var _mus_activa_a: bool = true
var _amb_a: AudioStreamPlayer
var _amb_b: AudioStreamPlayer
var _amb_activa_a: bool = true
var _efectos: Array[AudioStreamPlayer] = []
var _idx_efecto: int = 0
var _tween_mus: Tween
var _tween_amb: Tween
var _cerrar_puerta_al_entrar: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_asegurar_buses()
	_mus_a = _crear_reproductor("Musica")
	_mus_b = _crear_reproductor("Musica")
	_amb_a = _crear_reproductor("Ambiente")
	_amb_b = _crear_reproductor("Ambiente")
	for i in POOL_EFECTOS:
		_efectos.append(_crear_reproductor("Efectos"))
	get_tree().node_added.connect(_al_anadir_nodo)
	_conectar_senales.call_deferred()


func _al_anadir_nodo(nodo: Node) -> void:
	if nodo is BaseButton:
		var btn := nodo as BaseButton
		if not btn.pressed.is_connected(_al_pulsar_boton):
			btn.pressed.connect(_al_pulsar_boton)


func _al_pulsar_boton() -> void:
	reproducir("ui_clic")


func _asegurar_buses() -> void:
	for nombre: String in BUSES:
		if AudioServer.get_bus_index(nombre) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, nombre)
			AudioServer.set_bus_send(idx, "Master")


func _crear_reproductor(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _conectar_senales() -> void:
	if has_node("/root/Escenas"):
		Escenas.mapa_cargado.connect(_al_cargar_mapa)
	if has_node("/root/Juego"):
		Juego.dia_nuevo.connect(_actualizar_ambiente_actual)


func _cargar_stream(id: String, en_bucle: bool) -> AudioStream:
	var clave := id + ("_loop" if en_bucle else "")
	if _streams.has(clave):
		return _streams[clave]
	var ruta := CARPETA + id + ".wav"
	if not ResourceLoader.exists(ruta):
		return null
	var original := load(ruta)
	if original == null:
		return null
	if en_bucle and original is AudioStreamWAV:
		var copia := (original as AudioStreamWAV).duplicate() as AudioStreamWAV
		copia.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copia.loop_begin = 0
		copia.loop_end = int(copia.get_length() * copia.mix_rate)
		_streams[clave] = copia
		return copia
	_streams[clave] = original
	return original


func reproducir(id: String, variacion_tono: float = 0.04) -> void:
	var s := _cargar_stream(id, false)
	if s == null:
		return
	ultimo_efecto = id
	conteo_efectos[id] = int(conteo_efectos.get(id, 0)) + 1
	var p := _efectos[_idx_efecto]
	_idx_efecto = (_idx_efecto + 1) % _efectos.size()
	p.stream = s
	p.pitch_scale = randf_range(1.0 - variacion_tono, 1.0 + variacion_tono) if variacion_tono > 0.0 else 1.0
	p.volume_db = 0.0
	p.play()


func poner_musica(id: String) -> void:
	if id == musica_actual:
		return
	musica_actual = id
	if _tween_mus != null and _tween_mus.is_valid():
		_tween_mus.kill()
	var entrante := _mus_b if _mus_activa_a else _mus_a
	var saliente := _mus_a if _mus_activa_a else _mus_b
	_mus_activa_a = not _mus_activa_a
	if id.is_empty():
		_tween_mus = create_tween()
		_tween_mus.tween_property(saliente, "volume_db", -45.0, DURACION_FUNDIDO)
		_tween_mus.tween_callback(_soltar_player.bind(saliente))
		return
	var s := _cargar_stream(id, true)
	if s == null:
		return
	entrante.stream = s
	entrante.volume_db = -40.0
	entrante.play()
	_tween_mus = create_tween().set_parallel(true)
	_tween_mus.tween_property(entrante, "volume_db", -6.0, DURACION_FUNDIDO)
	if saliente.playing:
		_tween_mus.tween_property(saliente, "volume_db", -45.0, DURACION_FUNDIDO)
		_tween_mus.chain().tween_callback(_soltar_player.bind(saliente))


func poner_ambiente(id: String) -> void:
	if id == ambiente_actual:
		return
	ambiente_actual = id
	if _tween_amb != null and _tween_amb.is_valid():
		_tween_amb.kill()
	var entrante := _amb_b if _amb_activa_a else _amb_a
	var saliente := _amb_a if _amb_activa_a else _amb_b
	_amb_activa_a = not _amb_activa_a
	if id.is_empty():
		_tween_amb = create_tween()
		_tween_amb.tween_property(saliente, "volume_db", -45.0, DURACION_FUNDIDO)
		_tween_amb.tween_callback(_soltar_player.bind(saliente))
		return
	var s := _cargar_stream(id, true)
	if s == null:
		return
	entrante.stream = s
	entrante.volume_db = -40.0
	entrante.play()
	_tween_amb = create_tween().set_parallel(true)
	_tween_amb.tween_property(entrante, "volume_db", -8.0, DURACION_FUNDIDO)
	if saliente.playing:
		_tween_amb.tween_property(saliente, "volume_db", -45.0, DURACION_FUNDIDO)
		_tween_amb.chain().tween_callback(_soltar_player.bind(saliente))


func _soltar_player(p: AudioStreamPlayer) -> void:
	if is_instance_valid(p):
		p.stop()
		p.stream = null
	limpiar_cache_inactiva()


func ruta_musica_mapa(id_mapa: String) -> String:
	var id := musica_para_mapa(id_mapa)
	return "" if id.is_empty() else CARPETA + id + ".wav"


func ruta_ambiente_mapa(id_mapa: String) -> String:
	var id := ambiente_para_mapa(id_mapa)
	return "" if id.is_empty() else CARPETA + id + ".wav"


## Libera streams cacheados que no están sonando para no cargar memoria en menú.
func limpiar_cache_inactiva() -> void:
	var en_uso: Array[AudioStream] = []
	for p: AudioStreamPlayer in [_mus_a, _mus_b, _amb_a, _amb_b] + _efectos:
		if is_instance_valid(p):
			if p.playing and p.stream != null:
				en_uso.append(p.stream)
			else:
				p.stream = null
	for k: String in _streams.keys():
		if k == musica_actual or k == musica_actual + "_loop" or k == ambiente_actual or k == ambiente_actual + "_loop":
			continue
		if not en_uso.has(_streams[k]):
			_streams.erase(k)


func musica_para_mapa(id_mapa: String) -> String:
	match id_mapa:
		"granja", "bosque_norte", "costa_lago": return "mus_granja"
		"pueblo": return "mus_pueblo"
		"mina_exterior", "mina_interior": return "mus_mina"
		_: return "mus_interiores"


func ambiente_para_mapa(id_mapa: String) -> String:
	var exterior := id_mapa in ["granja", "pueblo", "mina_exterior", "bosque_norte", "costa_lago"]
	if exterior and has_node("/root/Juego") and Juego.esta_lloviendo():
		return "amb_lluvia"
	if id_mapa == "pueblo":
		return "amb_pueblo"
	if id_mapa == "mina_interior":
		return "amb_mina"
	return ""


func usar_puerta() -> void:
	reproducir("puerta_abrir")
	_cerrar_puerta_al_entrar = true


func _al_cargar_mapa(id_mapa: String) -> void:
	poner_musica(musica_para_mapa(id_mapa))
	poner_ambiente(ambiente_para_mapa(id_mapa))
	if _cerrar_puerta_al_entrar:
		_cerrar_puerta_al_entrar = false
		reproducir("puerta_cerrar")


func _actualizar_ambiente_actual() -> void:
	if has_node("/root/Juego") and not Juego.mapa_actual.is_empty():
		poner_ambiente(ambiente_para_mapa(Juego.mapa_actual))


func _exit_tree() -> void:
	if _tween_mus != null and _tween_mus.is_valid():
		_tween_mus.kill()
	if _tween_amb != null and _tween_amb.is_valid():
		_tween_amb.kill()
	for p: AudioStreamPlayer in [_mus_a, _mus_b, _amb_a, _amb_b] + _efectos:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_streams.clear()
