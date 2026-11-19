# Cambio 6 — Optimización de CPU (Motor, Jolt Physics, MultiMesh y bucles calientes en GDScript)

Tras completar las mejoras geométricas y de VRAM del [Cambio 5](cambio5.md), el perfilado de hilos en Linux (`16` hilos, Vulkan RTX 4070, pantalla principal `eDP-1` a `144 Hz`) mostró que el hilo principal (`godot4`) seguía consumiendo una carga elevada innecesaria debido a renderizar a `144 FPS` sin tope, exceso de chunks `MultiMesh` y sombras lejanas de árboles, el motor físico `GodotPhysics3D` y cálculos redundantes en `_process` / `_physics_process` a `144 Hz`.

Esta iteración aplica ambos bloques de optimización sin necesidad de reescribir el proyecto en Rust (el grueso del coste provenía de trabajo del motor en C++ y de trabajo redundante en GDScript).

---

## 1. Bloque Motor, Física y Draw Calls

### A. Límite de FPS configurable y modo «Automático» multimonitor
- **`MalaHierba/scripts/autoload/ajustes.gd`** y **`MalaHierba/scripts/ui/panel_ajustes.gd`:**
  - Añadido ajuste `limite_fps` (`LIMITES_FPS := [-1, 30, 60, 90, 120, 0]`; por defecto `0` = *Automático*) y su selector «Límite de FPS» en *Ajustes → Imagen*.
  - En *Automático*, si el monitor opera a `>= 100 Hz`, limita el renderizado a la mitad exacta de la frecuencia (`72 FPS` en pantallas de `144 Hz`) para mantener un ritmo de fotogramas regular con VSync recortando a la mitad el trabajo por segundo del hilo principal.
  - En equipos con varios monitores (p. ej. `HDMI-1-0 60 Hz` en `+0+0` y `eDP-1 144 Hz` primario en `+1920+0` bajo X11 + NVIDIA PRIME), `fps_objetivo()` consulta `maxf(screen_get_refresh_rate(), screen_get_refresh_rate(SCREEN_PRIMARY))` para evitar que al abrir en ventana deje el límite a `0` mientras PRIME sigue sincronizando a `144 Hz`, y `aplicar_ventana()` suma `screen_get_position(pant)` al centrar la ventana.
  - Se respeta `--max-fps` pasado por línea de comandos (`_max_fps_cli`) salvo que el jugador cambie explícitamente el ajuste, y el modo `--headless` corre libre (`0`) para no alargar las pruebas automáticas.

### B. Física con Jolt Physics 3D
- **`MalaHierba/project.godot`:** activado `3d/physics_engine="Jolt Physics"` aprovechando el módulo Jolt incluido en Godot 4.7.2, validado con las suites completas de cámara (`H01`), movimiento/colisiones/cueva (`M2`) y combate (`H02`).

### C. Consolidación de `MultiMeshInstance3D` y sombras de árboles
- **`MalaHierba/scripts/mapas/cargador_mapa.gd`:** ampliadas las celdas y umbrales de agrupación de instancias (`TAM_CELDA` `42 → 64 m`, `TAM_CELDA_MEDIA` `68 → 96 m`, `TAM_CELDA_ARBOL` `36 → 48 m`, `TAM_CELDA_ARBOL_MEDIA` `56 → 72 m`, `UMBRAL_UNICO` `16 → 32`, `UMBRAL_UNICO_ARBOL` `8 → 12`, `UMBRAL_CELDA_MEDIA` `55 → 90`, `MIN_INSTANCIAS_CELDA` `3 → 6`):
  - **`granja`:** `347 → 217` nodos `MultiMeshInstance3D` (**-37,5 %**)
  - **`pueblo`:** `562 → 252` nodos `MultiMeshInstance3D` (**-55,2 %**)
  - **`bosque_norte`:** `291 → 159` nodos `MultiMeshInstance3D` (**-45,4 %**)
  - **`robledal_niebla`:** `161 → 100` nodos `MultiMeshInstance3D` (**-37,9 %**)
- **`MalaHierba/scripts/mapas/cuadriculas_render.gd`:** separada la distancia de sombras de árboles adultos (`d_sombra_arb = [26, 34, 44, 72] m`) respecto a las estructuras (`d_sombra_est = [42, 54, 68, 100] m`), evitando proyectar sombras en abetos de 4 superficies más allá de `44 m` en *Alto*.

---

## 2. Bloque GDScript — Eliminación de trabajo redundante en bucles calientes

- **`MalaHierba/scripts/mapas/cuadriculas_render.gd`:**
  - Reemplazado el `Array` de 17 elementos creado cada actualización para cada una de las ~150 celdas por una máscara entera de bits (`estado_bits: int`) sin asignaciones en heap.
  - Subidos umbrales de cámara (`> 0,5 m` o `< 0,998` dot), límite de `15 Hz` (`0,065 s`) al moverse, evaluación cada `0,45 s` en reposo comprobando solo NPCs si no cambió cámara/calidad, y llamada directa tipada `npc.aplicar_culling_visual(...)`.
- **`MalaHierba/scripts/ui/minimapa.gd`:**
  - Limitado `_process` a `20 Hz` (`0,05 s`) máximo al moverse; en reposo `_fondo` no se redibuja y `_marcas` pasa a `4 Hz` (`0,25 s`).
  - Preasignados `_puntos_foto`, `_colores_foto`, `_uvs_foto` y `_lineas_borde`, precalculada la trigonometría de cámara por cada redibujo, cacheada la lista de NPCs cada `0,5 s`, actualización del parámetro shader `usar_niebla` restringida únicamente a `mina_interior`, y aros reducidos de `96` a `48` segmentos.
- **`MalaHierba/scripts/autoload/escenas.gd`:** caché O(1) en `jugador()` (`_jugador_cache`), invalidada al salir de la escena.
- **`MalaHierba/scripts/autoload/juego.gd`:** comprobación de ventana minimizada (`DisplayServer.window_get_mode()`) reducida de todos los frames a cada `0,25 s`.
- **`MalaHierba/scripts/ui/interfaz.gd`:** caché de `_decoracion_activa()` (`_deco_cache`, limpiada al cambiar de mapa) y sondeo de foco/cursor en `_process` limitado a cada `0,08 s` (las aperturas/cierres de paneles siguen actualizando al instante por señal).
- **`MalaHierba/scripts/mapas/mapa.gd`:** salida temprana en `_process()` si no hay relámpagos ni lluvia/nieve activos (evita consultar jugador y cámara cada frame con buen tiempo).
- **`MalaHierba/scripts/granja/parcelas.gd`:** caché de estado de apuntado en `_actualizar_marcas()` (invalidada en `reconstruir()`) para no recalcular celdas/líneas ni reescribir `global_transform` cuando la mira no cambia.
- **`MalaHierba/scripts/autoload/tutorial.gd`:** comprobaciones periódicas de movimiento/regalos/rocas bajadas a `5 Hz` (`0,20 s`).
- **`MalaHierba/scripts/ui/hud.gd`:** retorno temprano en `_actualizar_efectos_vida()` cuando la salud está sana y sin pulso activo; caché de munición/flechas en `_actualizar_visor_arco()` invalidada por señales de inventario/ranura o cada `0,20 s`.
- **`MalaHierba/scripts/jugador/jugador.gd`:** `_actualizar_visibilidad_farol()` en `_al_actualizar_vista()` solo se dispara cuando cambia `camara.cabeza_oculta`, y la distancia al río en `_actualizar_realismo_audio()` se evalúa cada `0,15 s`.
- **`MalaHierba/scripts/pueblo/vecinos.gd`:** eliminada la evaluación duplicada de `_regla_activa()` entre `ubicacion_en_mapa()` y `ubicacion()`, y sincronización en `_al_cambiar_hora()` agrupada a múltiplos de `5` minutos (verificado que todos los horarios de `npcs.json` y `vecinos_relleno.json` son múltiplos de `30` min).
- **`MalaHierba/pruebas/prueba_ajustes.gd`:** ruta temporal de prueba movida a `"user://ajustes_prueba.cfg"` con limpieza al terminar (evita depender de `gestion/`).

---

## 3. Mediciones de CPU y rendimiento (RTX 4070 Laptop GPU · Vulkan · Calidad Alto)

Medido sobre `pruebas/medir_h14.tscn` en estado estable (porcentaje respecto a `1` núcleo CPU = `100 %`, equipo de `16` hilos):

| Escena | Antes (`144 Hz` por defecto) | Antes (`60 FPS`) | Después (`Automático = 72 FPS`) | Después (`60 FPS`) | MultiMesh (`Antes → Después`) |
|---|---:|---:|---:|---:|---:|
| **`granja`** | ~52 % (`godot4` 40–48 %) | 27,9–31,9 % (`godot4` 20 %) | 27,9–43,6 % (`godot4` 20–28 %) | **4,0–12,0 %** (`godot4` **4 %**) | `347 → 217` (**-37,5 %**) |
| **`pueblo`** | ~52–56 % (`godot4` 40–48 %) | 19,9–39,9 % (`godot4` 16–28 %) | 39,9–55,8 % (`godot4` 28–36 %) | **4,0–23,9 %** (`godot4` **4–8 %**) | `562 → 252` (**-55,2 %**) |
| **`bosque_norte`** | ~28–40 % | 19,9–27,9 % (`godot4` 12–20 %) | 35,8–39,9 % (`godot4` 24–28 %) | **4,0–27,9 %** (`godot4` **4–8 %**) | `291 → 159` (**-45,4 %**) |
| **`robledal_niebla`** | ~20–40 % | 12,0–31,9 % | 31,9–43,8 % (`godot4` 20–28 %) | **4,0–11,9 %** (`godot4` **4 %**) | `161 → 100` (**-37,9 %**) |

- **Draw calls medidos:** `granja` `701 → 594–617`, `bosque_norte` `697 → 568–643`, `robledal_niebla` `356 → 265–315`, `pueblo` `1.009 → 894–1.131` (desde `797` en una pasada a 144 FPS, variando según vecinos visibles y sombras en cuadro).
- Con el selector en **`60 FPS`** (*Ajustes → Imagen → Límite de FPS*), el consumo en estado estable cae por debajo del **1 % de la CPU global** (`4–12 %` de 1 núcleo en `granja`/`robledal_niebla` y `4–23,9 %` en `pueblo`).

---

## 4. Pruebas verificadas tras los cambios

- **Headless (Jolt Physics + optimizaciones GDScript):**
  - `prueba_ajustes`: **190/190** (`RC=0`, ejecutada tras la corrección multimonitor final en `ajustes.gd`)
  - `prueba_h01_camara`: **116/116** (`RC=0`)
  - `prueba_m1`: **270/270** (`RC=0`)
  - `prueba_m2`: **221/221** (`RC=0`)
  - `prueba_t19_arboles`: **OK** (`RC=0`)
  - `prueba_t18_vegetacion`: **OK** (`RC=0`)
  - `prueba_h03_entorno`: **146/146** (`RC=0`)
  - `prueba_l1`: **OK** (`RC=0`)
  - `prueba_t16_pueblo`: **107/107** (`RC=0`)
  - `prueba_l4b`: **482/482** (`RC=0`)
  - `prueba_t14_tutorial`: **44/44** (`RC=0`)
  - `prueba_h02_combate`: **105/105** (`RC=0`)
- **Vulkan RTX 4070:**
  - `prueba_t12_mapa`: **2499/2499** (`RC=0`)
  - `medir_h14.tscn`: **OK** en *Automático (72 FPS)*, *60 FPS* y *144 FPS* (`RC=0`)
