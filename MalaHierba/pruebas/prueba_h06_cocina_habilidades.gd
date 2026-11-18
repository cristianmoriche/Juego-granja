extends Node
## Prueba breve de H06-cocina-y-habilidades: recetas, cocina, efectos/bufos, habilidades 1..10, guardado y migracion.

var _errores: int = 0
var _ok: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_errores += 1
		push_error("FALLO H06: " + msg)


func _ready() -> void:
	var ruta_orig := Juego.ruta_partida
	await get_tree().process_frame

	var recetas := Datos.recetas()
	_check(recetas.size() >= 18, "debe haber al menos 18 recetas cargadas (hay %d)" % recetas.size())
	for r: Dictionary in recetas:
		var rid := str(r.get("id", ""))
		var obj := Datos.objeto(rid)
		_check(not obj.is_empty() and obj.get("tipo", "") == "comida", "plato %s existe en objetos.json como comida" % rid)
		_check(Datos.tiene_icono(rid), "icono PNG existe para %s" % rid)
		for ing: Variant in r.get("ingredientes", []):
			if ing is Dictionary:
				_check(Datos.existe_objeto(str((ing as Dictionary).get("id", ""))), "ingrediente valido en %s" % rid)

	_check(Datos.tienda("tienda_mateo").get("compra_tipos", []).has("comida"), "Mateo compra platos cocinados")
	_check(Datos.tienda("taberna").get("recetas", []).size() >= 2, "Taberna vende recetas")

	Juego.nueva_partida("PruebaH06")
	_check(Juego.tiene_receta("patatas_asadas") and Juego.tiene_receta("salteado_setas"), "recetas iniciales aprendidas")
	_check(not Juego.tiene_receta("guiso_minero"), "guiso_minero empieza bloqueada")

	Juego.subir_amistad("tomas", 45)
	_check(Juego.tiene_receta("guiso_minero"), "amistad con Tomas desbloquea guiso_minero")
	_check(Juego.aprender_receta("crema_calabaza", false), "compra/aprendizaje manual de receta")
	_check(Juego.tiene_receta("crema_calabaza"), "crema_calabaza aprendida")

	# Cocinar y comer salteado_setas (dano +20%)
	Juego.anadir_objeto("seta_silvestre", 2)
	Juego.anadir_objeto("ajo", 1)
	_check(Juego.puede_cocinar("salteado_setas", 1), "puede cocinar salteado_setas con ingredientes")
	_check(Juego.cocinar("salteado_setas", 1), "cocinar salteado_setas devuelve true")
	_check(Juego.cantidad("seta_silvestre") == 0 and Juego.cantidad("salteado_setas") == 1, "consume ingredientes y entrega el plato")

	Juego.energia = 50.0
	Juego.vida = 70.0
	Juego.resistencia = 40.0
	_check(Juego.comer("salteado_setas"), "comer salteado_setas funciona")
	_check(Juego.energia >= 99.0 and Juego.vida >= 91.9 and Juego.resistencia >= 74.9, "plato repone energia, salud y resistencia")
	_check(Juego.bono_dano_combate() >= 0.19, "bufo de dano activo al comer plato")
	Juego.avanzar_minutos(190)
	_check(is_zero_approx(Juego.valor_bufo("dano")), "bufo caduca al pasar sus minutos de duracion")

	# Subida de habilidades y ventajas
	var senal_subida := {"n": 0}
	Juego.habilidad_subida.connect(func(_id: String, _nv: int, _ven: String) -> void: senal_subida["n"] += 1)
	Juego.ganar_xp_habilidad("combate", 45)
	_check(Juego.nivel_habilidad("combate") >= 2, "combate sube de nivel con XP")
	_check(Juego.vida_max >= 105.0, "nivel 2 de combate sube salud maxima a 105+")
	Juego.ganar_xp_habilidad("agricultura", 110)
	_check(Juego.nivel_habilidad("agricultura") >= 3 and Juego.factor_energia_habilidad("agricultura") < 0.95, "agricultura reduce gasto de energia")
	_check(senal_subida["n"] >= 2, "habilidad_subida emitida")

	# Guardar y cargar conserva habilidades, recetas y bufos
	Juego.anadir_objeto("sopa_ajo", 0) # sin invento
	Juego.anadir_objeto("ajo", 2)
	Juego.anadir_objeto("zanahoria", 1)
	Juego.cocinar("sopa_ajo", 1)
	Juego.comer("sopa_ajo")
	var nv_comb := Juego.nivel_habilidad("combate")
	Juego.ruta_partida = "user://prueba_h06_save.json"
	_check(Juego.guardar(), "guardado con datos H06")
	Juego.nueva_partida("Reset")
	_check(Juego.nivel_habilidad("combate") == 1, "nueva partida reinicia habilidades")
	_check(Juego.cargar(), "carga partida H06")
	_check(Juego.nivel_habilidad("combate") == nv_comb, "habilidades conservadas al cargar")
	_check(Juego.tiene_receta("guiso_minero") and Juego.tiene_receta("crema_calabaza"), "recetas conservadas al cargar")
	_check(Juego.valor_bufo("defensa") >= 11.9, "bufo activo conservado al cargar")
	Juego.borrar_partida()

	# Migrar una copia real de una partida antigua previa a H06
	var ruta_antigua := ProjectSettings.globalize_path("res://../copias/partidas-2026-11-17-antes-hiperrealista/partida_copia_2026-11-10_antes_de_la_version_final.json")
	if FileAccess.file_exists(ruta_antigua):
		var ruta_tmp := "user://prueba_h06_antigua.json"
		var fa := FileAccess.open(ruta_tmp, FileAccess.WRITE)
		fa.store_string(FileAccess.get_file_as_string(ruta_antigua))
		fa.close()
		Juego.ruta_partida = ruta_tmp
		_check(Juego.cargar(), "partida antigua previa a H06 carga sin errores")
		_check(Juego.nivel_habilidad("agricultura") == 1 and Juego.tiene_receta("patatas_asadas"), "partida antigua migra habilidades nivel 1 y recetas iniciales")
		Juego.borrar_partida()

	Juego.ruta_partida = ruta_orig
	if _errores == 0:
		print("PRUEBA H06 COCINA HABILIDADES OK (%d comprobaciones)" % _ok)
	else:
		push_error("PRUEBA H06 CON %d ERRORES" % _errores)
	get_tree().quit(0 if _errores == 0 else 1)
