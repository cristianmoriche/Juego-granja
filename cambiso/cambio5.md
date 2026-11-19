# Cambio 5 — Optimización de árboles actuales, consolidación de render/física/VRAM y eliminación de tirones de carga

Esta iteración resuelve los 6 cuellos de botella estructurales diagnosticados sobre **Mala Hierba** conservando intacto el estilo visual realista PBR de los modelos originales.

---

## 1. Optimización de los modelos actuales de árboles y brotes + deduplicación

Se decimaron por superficie en **Blender 5.2.0 LTS** los **14 prototipos pesados** de `MalaHierba/assets/mapas/granja/protos/` conservando sus materiales exactos, coordenadas UV (`TEXCOORD_0`), normales (`NORMAL`), altura (`dH <= 2.4 %`), pivotes y `meshes/generate_lods=true`:

- **Troncos y madera (`fir_tree_01_trunk_*`, `fir_tree_01_dead_branches`, `dead_tree_trunk`, `tree_stump_01`):** simplificación `DECIMATE COLLAPSE` con preservación UV/topológica (`101.8k → 2.8k` y `41.0k → 1.8k` tris).
- **Ramitas de corteza (`fir_tree_01_bark`):** modo *branchlets* que conserva las ramas estructurales de mayor área y decima únicamente preservando UV (`maxEdge <= 1.51 m` en `LOD1`), evitando cuñas estiradas.
- **Tarjetas de copa (`fir_tree_01_twig`):** simplificación interna de tarjetas subdivididas + muestreo espacial estratificado en `z`/azimut.
- **Pinos jóvenes (`fir_sapling_*`, `pine_sapling_small_*`):** ramas principales íntegras (`~500` tris) + simplificación y muestreo estratificado de agujas con compensación de volumen (`~4.9k–5.4k` tris frente a `122k–157k`).

| Prototipo (`.glb`) | Triángulos (Antes → Después) | Reducción | Tamaño (Antes → Después) |
|---|---:|---:|---:|
| `fir_tree_01_a_LOD1` | 177.444 → **8.757** | 20,3× | 5,97 → **0,34 MB** |
| `fir_tree_01_a_LOD2` | 70.661 → **3.233** | 21,9× | 3,52 → **0,18 MB** |
| `fir_tree_01_b_LOD1` | 128.464 → **7.755** | 16,6× | 3,75 → **0,31 MB** |
| `fir_tree_01_b_LOD2` | 54.927 → **2.985** | 18,4× | 2,61 → **0,16 MB** |
| `fir_tree_01_c_LOD1` | 68.879 → **6.701** | 10,3× | 1,84 → **0,30 MB** |
| `fir_tree_01_c_LOD2` | 31.512 → **2.625** | 12,0× | 1,31 → **0,15 MB** |
| `fir_sapling_a` | 157.402 → **5.447** | 28,9× | 7,88 → **0,28 MB** |
| `fir_sapling_b` | 150.876 → **5.310** | 28,4× | 7,56 → **0,27 MB** |
| `fir_sapling_c` | 124.743 → **4.885** | 25,5× | 6,25 → **0,25 MB** |
| `pine_sapling_small_a` | 142.506 → **5.440** | 26,2× | 6,36 → **0,24 MB** |
| `pine_sapling_small_b` | 122.235 → **5.190** | 23,6× | 5,46 → **0,23 MB** |
| `pine_sapling_small_c` | 133.403 → **5.332** | 25,0× | 5,95 → **0,24 MB** |
| `dead_tree_trunk` | 101.802 → **2.800** | 36,4× | 2,30 → **0,08 MB** |
| `tree_stump_01` | 41.046 → **1.800** | 22,8× | 0,97 → **0,06 MB** |
| **Total 14 prototipos** | **1.505.900 → 68.260** | **22,1×** | **61,72 → 3,09 MB** |

Además se **deduplicaron los prototipos compartidos** en `pueblo` (52 GLBs, **61,96 MB**) y `mina_exterior` (50 GLBs, **58,69 MB**) redirigiendo sus rutas en `instancias.json` hacia `res://assets/mapas/granja/protos/` (**120,65 MB** duplicados eliminados) y conservando los prototipos específicos de cada mapa.

---

## 2. Árboles en `MultiMeshInstance3D` y consolidación de fragmentación

En `MalaHierba/scripts/mapas/cargador_mapa.gd` y `cuadriculas_render.gd`:
- Eliminado el esquema anterior de 2 nodos `MeshInstance3D` por árbol (`_L1` + `_L2`) con `VISIBILITY_RANGE_FADE_SELF` (que doblaba el dibujado durante la transición): ahora toda la masa arbórea se instancia en `MultiMeshInstance3D` (`mm_<proto>_<cx>_<cy>`) con `VISIBILITY_RANGE_FADE_DISABLED`, `GI_MODE_DISABLED` y distancias/sombras configuradas por categoría (`CuadriculasRender` gestiona `lod_bias`, visibilidad y sombreado dinámico por cuadrícula sobre `GeometryInstance3D`).
- Agrupación adaptativa en `_agrupar_celdas_proto`: prototipos poco numerosos (`<= 16` en props/plantas, `<= 8` en árboles) pasan a un único `MultiMeshInstance3D`, se amplían celdas densas a `42 m` (`68 m` en densidad media; `36 m / 56 m` en árboles) y se fusionan celdas con `<= 3` instancias en la vecina más poblada.
- Reducción total de nodos en escena (`medir_h14`):
  - **granja:** `654` mallas + `629` MM → **`95` mallas + `347` MM**
  - **pueblo:** `812` mallas + `833` MM → **`192` mallas + `562` MM**
  - **bosque_norte:** `874` mallas + `467` MM → **`68` mallas + `291` MM**
  - **robledal_niebla:** `312` mallas + `364` MM → **`58` mallas + `161` MM**

---

## 3. Compresión VRAM de texturas 3D y reducción de GLBs pesados

- **642 archivos `.import`** de texturas 3D (`enemigos`, `naturaleza`, `granja`, `herramientas`, `personajes`, `muebles`, `mapas`, `mina`, `agua`, `texturas`, `combate`) migrados de `compress/mode=0` (RGBA8 sin comprimir) a **`compress/mode=2`** (VRAM Compressed) con `mipmaps/generate=true` y `process/size_limit` (`1024` en personajes/enemigos/armas/props, `2048` en terrenos/arquitectura). Se excluyeron `iconos/`, `ui/`, `hdri/` y archivos `.exr`/`.hdr`. Verificado **0 texturas 3D en `compress/mode=0`**.
- **21 GLBs de combate y enemigos** (`espada.glb` `27,79 → 6,14 MB`, `escudo.glb` `14,35 → 3,51 MB`, `daga.glb`, `maza.glb`, `martillo_guerra.glb` y 16 enemigos): texturas embebidas reescaladas a máx. `1024 px` con PNG en normales/alfa y JPEG calidad 88 en difusión/ORM, reduciendo el conjunto de **180,94 MB → 75,52 MB**.

---

## 4. Física a 60 Hz y colisiones primitivas en props compactos

- **`MalaHierba/project.godot`:** `common/physics_ticks_per_second` pasa de **`120` → `60`** ticks/s (mitad de invocaciones de `move_and_slide()` y raycasts por segundo).
- **`cargador_mapa.gd` (`_forma_colision_malla`):** los props individuales compactos de alto poligonaje (`dim_max <= 3.0 m`) usan primitivas cacheadas (`CylinderShape3D` para `wooden_barrels_*` y `wooden_bucket_*`; `BoxShape3D` para `wooden_crate_*` y `txt_*`), mientras terreno, cuevas, muros y mallas combinadas conservan `create_trimesh_shape()` exacto:
  - **pueblo:** `216.118 → 59.360` triángulos trimesh (**-72,5 %**), sustituyendo 41 props por `17` cilindros y `24` cajas.
  - **mina_exterior:** `141.814 → 65.056` tris (**-54,1 %**, `7` cil, `15` cajas).
  - **mina_interior:** `104.354 → 57.650` tris (**-44,8 %**, `3` cil, `6` cajas).
  - **granja:** `78.674 → 44.520` tris (**-43,4 %**, `4` cil, `3` cajas).

---

## 5. Preset «Alto» equilibrado, oclusión CPU y distancias de cámara

- **`MalaHierba/scripts/mapas/grafica_h03.gd`:**
  - `SSIL` y `SSR` se reservan para **Ultra** (`calidad >= 3`); **Alto** conserva `SSAO` + `LightmapGI` prehorneado + `Auto-Exposure` + `Volumetric Fog` optimizado (`24×32`, longitud `60 m` en exteriores / `24 m` en interiores).
  - `use_occlusion_culling` desactivado (`false` tanto en `project.godot` como en `GraficaH03.aplicar_calidad_servidor`) para evitar rasterizado CPU innecesario en exteriores abiertos.
- **`MalaHierba/scripts/autoload/ajustes.gd`:** `camera.far` acotado a `[100.0, 220.0, 360.0, 600.0]`.
- **`camara_juego.gd` y `jugador.gd`:** ajustado `blanco` en `encuadre_cercano` e invalidación inmediata de interactuable desactivado para plena precisión a 60 Hz.

---

## 6. Transiciones sin bloqueo y recomendación para doble monitor X11

- **`MalaHierba/scripts/autoload/escenas.gd`:** espera no bloqueante (hasta `2,5 s`, cediendo por fotogramas con la pantalla «Cargando…» activa) mientras terminan en segundo plano los hilos de `ResourceLoader` de la escena, `.glb` y `.lmbake` antes de instanciar.
- **Doble monitor heterogéneo en Linux X11 (`144 Hz` + `60 Hz`):** jugar en ventana bajo un compositor X11 con monitores de distinta frecuencia puede introducir variaciones de ritmo de fotogramas (*frame pacing*); se recomienda pulsar **`F11`** (pantalla completa) para que el servidor gráfico entregue sin interferencia del compositor.

---

## Métricas reales antes / después (RTX 4070 Laptop GPU · Vulkan Forward+)

### A. Perfilado `medir_h14.tscn` (Calidad Alto, 19:30, ventana 1600×900 con VSync)

| Métrica | Antes (`800ce24`) | Después (`cambio5`) | Variación |
|---|---:|---:|---:|
| **VRAM total (`menu_tras_jugar`)** | 678,8 MB | **315,4 MB** | **-53,5 %** |
| **VRAM texturas (`menu_tras_jugar`)** | 446,9 MB | **121,3 MB** | **-72,9 %** |
| **Pico RAM estática (`menu_tras_jugar`)** | 490,9 MB | **314,1 MB** | **-36,0 %** |
| **`pueblo` transición / cargador** | 1803 ms / 514 ms | **1171 ms / 213 ms** | **-35,1 % / -58,6 %** |
| **`granja` transición / cargador** | 2953 ms / 230 ms | **2320 ms / 180 ms** | **-21,4 % / -21,7 %** |
| **`bosque_norte` transición / cargador** | 840 ms / 144 ms | **534 ms / 132 ms** | **-36,4 % / -8,3 %** |
| **`robledal_niebla` transición / prims** | 989 ms / 1,66M | **541 ms / 568k** | **-45,3 % / -65,9 %** |

### B. Rendimiento sin VSync en `pueblo` (`capturas_h03.tscn`, 1080p, sol 14:00)

| Calidad | FPS medios | 1 % más lento |
|---|---:|---:|
| Bajo | **403,0 FPS** | **171,6 FPS** |
| Medio | **298,6 FPS** | **120,2 FPS** |
| **Alto (predet.)** | **271,1 FPS** | **132,8 FPS** |
| Ultra | **130,4 FPS** | **91,8 FPS** |

---

## Pruebas verificadas

- **Headless tras los últimos cambios de código:**
  - `prueba_h01_camara`: **116/116** (`rc=0`)
  - `prueba_m2`: **221/221** (`rc=0`)
  - `prueba_t19_arboles`: **OK** (`granja` 187 ms / 48 nodos, `pueblo` 236 ms / 50 nodos, `mina_exterior` 184 ms / 42 nodos, `rc=0`)
  - `prueba_t18_vegetacion`: **OK** (`rc=0`)
  - `prueba_h03_entorno`: **146/146** (`rc=0`)
  - `prueba_ajustes`: **187/187** (`rc=0`)
  - `prueba_l1`, `prueba_l2`, `prueba_l3`: **OK** (`rc=0`)
  - `prueba_h02_combate`: **105/105** (`rc=0`)
  - `prueba_h04_mina`: **45/45** (`rc=0`)
  - `prueba_t16_pueblo`: **107/107** (`rc=0`)
  - `prueba_t26_mina`: **226/226** (`rc=0`)
- **Vulkan con ventana RTX 4070:**
  - `prueba_t12_mapa`: **2499/2499** (`rc=0`, foto cenital verificada sin parches blancos)
  - `medir_h14.tscn` y `capturas_h03.tscn` (`H03_MEDIR` pueblo): **OK** (`rc=0`)
- **Headless ejecutadas previamente tras optimizar GLBs/texturas y deduplicar mapas:**
  - `prueba_m1` (`270/270`), `prueba_h05_mapa` (`122/122`), `prueba_e1_enemigos` (`365/365`), `prueba_t05_animaciones`, `prueba_t21_herramientas_en_mano` (`106/106`), `prueba_iconos` (`746/746`) (`rc=0`).
