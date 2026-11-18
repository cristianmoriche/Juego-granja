extends Node
## Autoload «Cultivos» (L4a): datos y reglas de las parcelas de la granja. No toca nodos: la parte visual y el uso
## de las herramientas con el cursor están en `parcelas.gd`.
##
## Las parcelas viven en `Juego.estado_mapas["granja"]["parcelas"]` (compatible con JSON, se guarda con la partida):
##   "Zona_Cultivo_1:3:5" -> {estado, regado, cultivo, dias, etapa, listo, golpes}
## estado: maleza | piedra | tronco | limpio | arado.
## En una casilla arada con cultivo, `dias` cuenta los días regados; sin cultivo cuenta los días seguidos sin regar.
## `etapa` va de 0 a `etapas - 1` del cultivo; la última es «listo».

signal parcela_cambiada(clave: String)
signal parcelas_cambiadas()
signal accion_visual(tipo: String, clave: String)

const MAPA := "granja"
const PROB_MALEZA := 0.55          # reparto inicial en partida nueva
const PROB_PIEDRA := 0.10
const PROB_TRONCO := 0.07
const PROB_MALEZA_NUEVA := 0.03    # cada noche, en lo limpio
const DIAS_ARADO_SECO := 3         # lo arado sin sembrar ni regar vuelve a limpio
const ENERGIA_NIVEL: Array[float] = [2.0, 1.5, 1.0]   # por uso de herramienta, según su nivel
const ENERGIA_SEMILLA := 0.5
const GOLPES_PIEDRA := 2
const GOLPES_TRONCO := 3

## Cultivos marchitos en el último cambio de día (la granja lo avisa al cargarse).
var marchitos_pendientes: int = 0
## Claves de parcelas cuyo cultivo acaba de subir de fase (la granja las anima al mostrarse).
var fases_pendientes: Dictionary = {}


func _ready() -> void:
	Juego.dia_nuevo.connect(procesar_dia)


# --- Acceso a los datos -------------------------------------------------------------------------------------------

func clave(zona: String, x: int, z: int) -> String:
	return "%s:%d:%d" % [zona, x, z]


## Diccionario vivo de parcelas (se crea si falta). Siempre se pide a través de Juego: al cargar una partida cambia.
func parcelas() -> Dictionary:
	var m: Variant = Juego.estado_mapas.get(MAPA)
	if not (m is Dictionary):
		m = {}
		Juego.estado_mapas[MAPA] = m
	var md: Dictionary = m
	var p: Variant = md.get("parcelas")
	if not (p is Dictionary):
		p = {}
		md["parcelas"] = p
	return p


## Datos vivos de una casilla ({} si no existe): editar el diccionario devuelto cambia el estado de la partida.
func parcela(k: String) -> Dictionary:
	var v: Variant = parcelas().get(k)
	if v is Dictionary:
		return v
	return {}


func nueva_parcela(estado: String = "limpio") -> Dictionary:
	return {"estado": estado, "regado": false, "cultivo": "", "dias": 0, "etapa": 0, "listo": false, "golpes": 0}


## Cuántas casillas hay en ese estado (todas si `estado` está vacío).
func contar(estado: String = "") -> int:
	var n := 0
	for k: Variant in parcelas():
		var c: Dictionary = parcelas()[k]
		if estado.is_empty() or str(c.get("estado", "")) == estado:
			n += 1
	return n


## Crea las casillas que falten de una zona (en partida nueva: ~55 % maleza, 10 % piedra, 7 % tronco, resto limpio;
## la maleza sale en manchas). Devuelve cuántas ha creado.
func generar_zona(zona: String, nx: int, nz: int) -> int:
	var p := parcelas()
	var faltan: Array[Vector2i] = []
	for x in nx:
		for z in nz:
			if not p.has(clave(zona, x, z)):
				faltan.append(Vector2i(x, z))
	if faltan.is_empty():
		return 0
	var ruido := FastNoiseLite.new()
	ruido.seed = randi()
	ruido.frequency = 0.3
	var puntuadas: Array = []
	for c in faltan:
		puntuadas.append([ruido.get_noise_2d(c.x, c.y) * 0.7 + randf_range(-0.3, 0.3), c])
	puntuadas.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var n := faltan.size()
	var n_maleza := roundi(n * PROB_MALEZA)
	var n_piedra := roundi(n * PROB_PIEDRA)
	var n_tronco := roundi(n * PROB_TRONCO)
	var resto: Array[Vector2i] = []
	for i in n:
		var c: Vector2i = (puntuadas[i] as Array)[1]
		if i < n_maleza:
			p[clave(zona, c.x, c.y)] = nueva_parcela("maleza")
		else:
			resto.append(c)
	resto.shuffle()
	for i in resto.size():
		var estado := "limpio"
		if i < n_piedra:
			estado = "piedra"
		elif i < n_piedra + n_tronco:
			estado = "tronco"
		p[clave(zona, resto[i].x, resto[i].y)] = nueva_parcela(estado)
	parcelas_cambiadas.emit()
	return n


# --- El paso de los días ------------------------------------------------------------------------------------------

## Se llama con `Juego.dia_nuevo` (la fecha y el clima ya son los de la mañana), aunque la granja no esté cargada.
func procesar_dia() -> void:
	var p := parcelas()
	if p.is_empty():
		return
	var llueve := Juego.esta_lloviendo()
	var es_dia_plaga := str(Juego.evento_hoy().get("tipo", "")) == "plaga"
	var marchitos := 0
	var cultivos_presentes: Dictionary = {}
	for k: Variant in p:
		var c: Dictionary = p[k]
		var id_cultivo := str(c.get("cultivo", ""))
		if id_cultivo != "":
			var def := Datos.cultivo(id_cultivo)
			if def.is_empty() or not _estacion_vale(def, Juego.estacion):
				_vaciar_cultivo(c)       # fuera de estación se marchita
				c["estado"] = "arado"
				c["regado"] = false
				marchitos += 1
			else:
				if bool(c.get("plaga", false)):
					c["calidad_baja"] = true
					c["plaga"] = false
				if not bool(c.get("listo", false)) and bool(c.get("regado", false)):
					var etapa_antes := int(c.get("etapa", 0))
					var listo_antes := bool(c.get("listo", false))
					c["dias"] = int(c.get("dias", 0)) + 1
					var total := maxi(int(def.get("dias", 1)), 1)
					var etapas := maxi(int(def.get("etapas", 4)), 2)
					if int(c["dias"]) >= total:
						c["listo"] = true
						c["etapa"] = etapas - 1
					else:
						c["etapa"] = _etapa_de(int(c["dias"]), total, etapas)
					if int(c.get("etapa", 0)) > etapa_antes or (not listo_antes and bool(c.get("listo", false))):
						fases_pendientes[str(k)] = true
				cultivos_presentes[id_cultivo] = int(cultivos_presentes.get(id_cultivo, 0)) + 1
			c["regado"] = llueve
			continue
		match str(c.get("estado", "")):
			"arado":
				if bool(c.get("regado", false)):
					c["dias"] = 0
				else:
					c["dias"] = int(c.get("dias", 0)) + 1
				if int(c["dias"]) >= DIAS_ARADO_SECO:
					c["estado"] = "limpio"
					c["dias"] = 0
					c["regado"] = false
				else:
					c["regado"] = llueve
			"limpio":
				c["regado"] = false
				if randf() < PROB_MALEZA_NUEVA:
					c["estado"] = "maleza"
			_:
				c["regado"] = false
	if es_dia_plaga and not cultivos_presentes.is_empty():
		infectar_plaga(_elegir_cultivo_plaga(cultivos_presentes), false)
	marchitos_pendientes += marchitos
	parcelas_cambiadas.emit()


func _elegir_cultivo_plaga(conteos: Dictionary) -> String:
	var mejor := ""
	var max_n := -1
	for k: Variant in conteos:
		var n := int(conteos[k])
		if n > max_n:
			max_n = n
			mejor = str(k)
	return mejor


## Marca todas las parcelas de un cultivo con plaga activa. Devuelve el id afectado o "".
func infectar_plaga(id_cultivo: String = "", emitir: bool = true) -> String:
	var p := parcelas()
	if p.is_empty():
		return ""
	var objetivo := id_cultivo
	if objetivo.is_empty():
		for k: Variant in p:
			var cid := str((p[k] as Dictionary).get("cultivo", ""))
			if not cid.is_empty():
				objetivo = cid
				break
	if objetivo.is_empty():
		return ""
	var tocadas := 0
	for k: Variant in p:
		var c: Dictionary = p[k]
		if str(c.get("cultivo", "")) == objetivo:
			c["plaga"] = true
			tocadas += 1
	if tocadas <= 0:
		return ""
	Juego.registrar_plaga_cultivo(objetivo)
	if emitir:
		parcelas_cambiadas.emit()
	return objetivo


func _estacion_vale(def: Dictionary, estacion: int) -> bool:
	for e: Variant in def.get("estaciones", []):
		if int(e) == estacion:
			return true
	return false


func _etapa_de(dias: int, total: int, etapas: int) -> int:
	return clampi(int(float(dias) * float(etapas - 1) / float(total)), 0, etapas - 2)


func _vaciar_cultivo(c: Dictionary) -> void:
	c["cultivo"] = ""
	c["dias"] = 0
	c["etapa"] = 0
	c["listo"] = false
	c["plaga"] = false
	c["calidad_baja"] = false


# --- Herramientas y semillas -------------------------------------------------------------------------------------

func energia_de(herramienta: String) -> float:
	return ENERGIA_NIVEL[clampi(Juego.nivel(herramienta), 0, ENERGIA_NIVEL.size() - 1)] * Juego.factor_energia_habilidad("agricultura")


## Golpes que hacen falta con esa herramienta (uno menos por nivel, mínimo uno).
func golpes_necesarios(base: int, herramienta: String) -> int:
	return maxi(1, base - Juego.nivel(herramienta))


## Usa un objeto (herramienta o semilla) sobre la primera casilla de `claves`; azada y regadera de nivel 1 o más
## afectan además a las siguientes (la línea que calcula `Parcelas`). Gasta la energía. true = ha hecho algo.
func aplicar(id: String, claves: Array) -> bool:
	if claves.is_empty():
		return false
	var k0 := str(claves[0])
	var c0 := parcela(k0)
	if c0.is_empty():
		return false
	var tipo := str(Datos.objeto(id).get("tipo", ""))
	if tipo == "semilla":
		return _sembrar(id, k0)
	if tipo == "tratamiento":
		return _curar_plaga(id, k0)
	if tipo != "herramienta":
		return false
	var eventos: Array[Array] = []
	var sacudir := false
	match id:
		"hoz":
			if str(c0["estado"]) != "maleza":
				return _pista(id, c0)
			if not Juego.gastar_energia(energia_de(id)):
				return false
			c0["estado"] = "limpio"
			c0["golpes"] = 0
			var n_fib := randi_range(1, 2) + (1 if randf() < Juego.bono_suerte_recoleccion() else 0)
			_entregar("fibra", n_fib)
			Juego.ganar_xp_habilidad("recoleccion", 5)
		"pico":
			if str(c0["estado"]) != "piedra":
				return _pista(id, c0)
			if not Juego.gastar_energia(energia_de(id)):
				return false
			c0["golpes"] = int(c0.get("golpes", 0)) + 1
			Juego.ganar_xp_habilidad("mineria", 3)
			if int(c0["golpes"]) >= golpes_necesarios(GOLPES_PIEDRA, id):
				c0["estado"] = "limpio"
				c0["golpes"] = 0
				_entregar("piedra", randi_range(1, 3))
				Juego.ganar_xp_habilidad("mineria", 6)
			eventos.append(["picar", k0])
			sacudir = true
		"hacha":
			if str(c0["estado"]) != "tronco":
				return _pista(id, c0)
			if not Juego.gastar_energia(energia_de(id)):
				return false
			c0["golpes"] = int(c0.get("golpes", 0)) + 1
			Juego.ganar_xp_habilidad("recoleccion", 3)
			if int(c0["golpes"]) >= golpes_necesarios(GOLPES_TRONCO, id):
				c0["estado"] = "limpio"
				c0["golpes"] = 0
				var n_mad := randi_range(2, 4) + (1 if randf() < Juego.bono_suerte_recoleccion() else 0)
				_entregar("madera", n_mad)
				Juego.ganar_xp_habilidad("recoleccion", 8)
				TareasDiarias.registrar_progreso("talar", 1)
			eventos.append(["talar", k0])
			sacudir = true
		"azada":
			var por_arar: Array[Dictionary] = []
			var claves_arar: Array[String] = []
			for k in _en_linea(id, claves):
				var c := parcela(k)
				if str(c.get("estado", "")) == "limpio":
					por_arar.append(c)
					claves_arar.append(k)
			if por_arar.is_empty():
				return _pista(id, c0)
			if not Juego.gastar_energia(energia_de(id)):
				return false
			for i in por_arar.size():
				var c := por_arar[i]
				c["estado"] = "arado"
				c["dias"] = 0
				c["regado"] = Juego.esta_lloviendo()
				eventos.append(["labrar", claves_arar[i]])
			Juego.ganar_xp_habilidad("agricultura", 4 * por_arar.size())
		"regadera":
			var por_regar: Array[Dictionary] = []
			var claves_regar: Array[String] = []
			for k in _en_linea(id, claves):
				var c := parcela(k)
				if str(c.get("estado", "")) == "arado" and not bool(c.get("regado", false)):
					por_regar.append(c)
					claves_regar.append(k)
			if por_regar.is_empty():
				return _pista(id, c0)
			if not Juego.gastar_energia(energia_de(id)):
				return false
			for i in por_regar.size():
				por_regar[i]["regado"] = true
				eventos.append(["regar", claves_regar[i]])
			Juego.ganar_xp_habilidad("agricultura", 3 * por_regar.size())
			TareasDiarias.registrar_progreso("regar", por_regar.size())
		_:
			return false
	for k: Variant in claves:
		parcela_cambiada.emit(str(k))
	for ev: Array in eventos:
		accion_visual.emit(str(ev[0]), str(ev[1]))
	if sacudir:
		CamaraJuego.sacudir_activa()
	Audio.reproducir(id)
	return true


## Las casillas afectadas: solo la primera con nivel 0; hasta tres en línea con nivel 1 o más.
func _en_linea(herramienta: String, claves: Array) -> Array[String]:
	var r: Array[String] = []
	var n := 1 if Juego.nivel(herramienta) < 1 else mini(claves.size(), 3)
	for i in n:
		r.append(str(claves[i]))
	return r


func _sembrar(id_semilla: String, k: String) -> bool:
	var c := parcela(k)
	var def := Datos.cultivo_de_semilla(id_semilla)
	if def.is_empty():
		return false
	if str(c.get("estado", "")) != "arado" or str(c.get("cultivo", "")) != "":
		return _pista(id_semilla, c)
	if not _estacion_vale(def, Juego.estacion):
		Juego.mensaje.emit("Esta semilla no es de %s; es de %s." % [Juego.nombre_estacion().to_lower(), _nombres_estaciones(def)])
		return false
	if Juego.cantidad(id_semilla) < 1 or not Juego.gastar_energia(ENERGIA_SEMILLA * Juego.factor_energia_habilidad("agricultura")):
		return false
	Juego.quitar_objeto(id_semilla, 1)
	Juego.ganar_xp_habilidad("agricultura", 4)
	c["cultivo"] = str(def["id"])
	c["dias"] = 0
	c["etapa"] = 0
	c["listo"] = false
	c["plaga"] = false
	c["calidad_baja"] = false
	parcela_cambiada.emit(k)
	return true


func _curar_plaga(id_obj: String, k0: String) -> bool:
	var partes := k0.split(":")
	if partes.size() != 3:
		return false
	var zona := str(partes[0])
	var cx := int(partes[1])
	var cz := int(partes[2])
	var afectadas: Array[String] = []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := clave(zona, cx + dx, cz + dz)
			var c := parcela(k)
			if not c.is_empty() and bool(c.get("plaga", false)):
				afectadas.append(k)
	if afectadas.is_empty():
		Juego.mensaje.emit("Aquí no hay ningún cultivo con plaga que tratar.")
		return false
	if Juego.cantidad(id_obj) < 1 or not Juego.gastar_energia(ENERGIA_SEMILLA):
		return false
	Juego.quitar_objeto(id_obj, 1)
	for k in afectadas:
		var c := parcela(k)
		c["plaga"] = false
		parcela_cambiada.emit(k)
		accion_visual.emit("regar", k)
	Audio.reproducir("regadera")
	Juego.mensaje.emit("Has tratado %d %s contra la plaga." % [afectadas.size(), "parcela" if afectadas.size() == 1 else "parcelas"])
	return true


func _nombres_estaciones(def: Dictionary) -> String:
	var nombres: Array[String] = []
	for e: Variant in def.get("estaciones", []):
		nombres.append(Juego.NOMBRES_ESTACION[clampi(int(e), 0, 3)].to_lower())
	return " y ".join(PackedStringArray(nombres))


## Aviso breve cuando la herramienta no vale para lo que hay en la casilla (devuelve siempre false).
func _pista(id: String, c: Dictionary) -> bool:
	var estado := str(c.get("estado", ""))
	var texto := ""
	var tipo := str(Datos.objeto(id).get("tipo", ""))
	match estado:
		"maleza":
			if id != "hoz":
				texto = "La maleza se siega con la hoz."
		"piedra":
			if id != "pico":
				texto = "Esa piedra pide el pico."
		"tronco":
			if id != "hacha":
				texto = "Ese tronco es cosa del hacha."
		"limpio":
			if id == "regadera" or tipo == "semilla":
				texto = "Antes hay que arar la tierra."
	if not texto.is_empty():
		Juego.mensaje.emit(texto)
	return false


func _entregar(id: String, n: int) -> void:
	if Juego.anadir_objeto(id, n) > 0:
		Juego.mensaje.emit("La mochila está llena: se pierde lo que no cabe.")


# --- Cosecha ------------------------------------------------------------------------------------------------------

func esta_listo(k: String) -> bool:
	var c := parcela(k)
	return not c.is_empty() and bool(c.get("listo", false)) and str(c.get("cultivo", "")) != ""


## Recoge el cultivo de una casilla lista. false si no está listo o no cabe en la mochila.
func cosechar(k: String) -> bool:
	if not esta_listo(k):
		return false
	var c := parcela(k)
	var def := Datos.cultivo(str(c["cultivo"]))
	if def.is_empty():
		return false
	var rango: Array = def.get("cantidad", [1, 1])
	var n := randi_range(int(rango[0]), int(rango[rango.size() - 1]))
	if randf() < Juego.bono_suerte_cosecha():
		n += 1
	var id := str(def.get("cosecha", c["cultivo"]))
	var calidad := "baja" if (bool(c.get("plaga", false)) or bool(c.get("calidad_baja", false))) else ""
	if Juego.espacio_para(id, calidad) < n:
		Juego.mensaje.emit("No te cabe la cosecha en la mochila.")
		return false
	Juego.anadir_objeto(id, n, calidad)
	Juego.ganar_xp_habilidad("agricultura", 8 + n * 2)
	if calidad == "baja":
		Juego.mensaje.emit("La plaga ha rebajado la calidad de %s: vale la mitad en tienda." % Datos.nombre_objeto(id).to_lower())
	Juego.estadisticas["cosechado"] = int(Juego.estadisticas.get("cosechado", 0)) + n
	Juego.estadisticas["cosechas"] = int(Juego.estadisticas.get("cosechas", 0)) + n
	Misiones.registrar_cosecha(id, n)
	var rebrota := int(def.get("rebrota", 0))
	if rebrota > 0:
		var total := maxi(int(def.get("dias", 1)), 1)
		c["dias"] = maxi(total - rebrota, 0)
		c["listo"] = false
		c["plaga"] = false
		c["calidad_baja"] = false
		c["etapa"] = _etapa_de(int(c["dias"]), total, maxi(int(def.get("etapas", 4)), 2))
	else:
		_vaciar_cultivo(c)
	Audio.reproducir("cosecha")
	parcela_cambiada.emit(k)
	accion_visual.emit("cosechar", k)
	return true


## «Cosechar tomates», para el cartel de la tecla E.
func texto_cosecha(k: String) -> String:
	var c := parcela(k)
	var def := Datos.cultivo(str(c.get("cultivo", "")))
	if def.is_empty():
		return ""
	return "Cosechar " + plural(Datos.nombre_objeto(str(def.get("cosecha", ""))))


func plural(nombre: String) -> String:
	var n := nombre.to_lower()
	if n.is_empty():
		return n
	var ultima := n.substr(n.length() - 1)
	if ultima in ["a", "e", "i", "o", "u"]:
		return n + "s"
	if ultima == "n":
		return n.replace("ó", "o").replace("é", "e").replace("á", "a") + "es"
	return n + "es"
