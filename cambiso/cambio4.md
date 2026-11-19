# Cambio 4 — Animaciones de movimiento para Leo y Optimización Gráfica Ronda 2

## 1. Importación y aplicación de animaciones de movimiento a Leo (`leo.glb` + `jugador.gd`)

Se han retargeteado e integrado las nuevas animaciones de movimiento desde `/home/juanjo/Documentos/personaje/godot/farmer_godot.glb` (`ARM-Farmer_SOMA`, 23 huesos, clips in-place) sobre el modelo actual optimizado del protagonista en `MalaHierba/assets/personajes/leo/leo.glb`:

- **Integridad del personaje actual:**
  - Malla conservada intacta con exactamente **28.000 triángulos** y textura de albedo (`leo_leo_leo_color_nuevo.jpg`).
  - Esqueleto de **35 huesos `DEF-*`** preservado con sus nombres exactos (`DEF-spine.001`..`.006`, `DEF-*.L`, `DEF-*.R`), manteniendo intacta la separación de cabeza (`DEF-spine.006`) para primera persona (`vista_leo.gd`) y los soportes de herramientas/combate (`DEF-hand.R`, `DEF-hand.L`, `DEF-spine`).
  - Total de **30 animaciones** en `leo.glb`: se añaden/actualizan `andar`, `agachado_andar`, `correr` y `saltar` (junto con `caer` y `aterrizar`), conservando todos los clips existentes de herramientas, combate y gestos.
- **Retargeting y soporte de movimiento:**
  - Retargeting en espacio mundo con alineación anatómica de extremidades, escalado de desplazamiento vertical (`1.15`) y ajuste de apoyo de pies al suelo (`~0.040 m`).
  - Limpieza del nodo raíz envolvente al reexportar el GLB y restauración de la nomenclatura original con puntos en huesos (`DEF-*.*`).
- **Integración en `MalaHierba/scripts/jugador/jugador.gd`:**
  - Registrada `"correr"` en modo bucle (`Animation.LOOP_LINEAR`) y seleccionada automáticamente al esprintar sin herramienta equipada y sin estar agachado (`velocidad = 1.15`).

---

## 2. Optimización Gráfica Ronda 2 (Culling, LOD, Lightmaps y Normal Maps)

### Resumen de rendimiento (NVIDIA GeForce RTX 4070 Laptop GPU · Vulkan Forward+ · 1920×1080)

#### A. Comparativa `capturas_h03.tscn` (sin VSync, 14:00, día despejado)

| Mapa | Calidad | FPS medios (Inicio R2 → Fin R2) | 1 % más lento (Inicio R2 → Fin R2) |
|---|---|---:|---:|
| **granja** | Bajo | — → **446.6 FPS** | — → **188.3 FPS** |
| **granja** | Medio | — → **433.5 FPS** | — → **184.0 FPS** |
| **granja** | **Alto (predet.)** | 205.2 → **353.3 FPS (+72.2 %)** | 51.8 → **196.0 FPS (×3.78)** |
| **granja** | Ultra | — → **163.7 FPS** | — → **105.5 FPS** |
| **pueblo** | Bajo | — → **377.7 FPS** | — → **174.0 FPS** |
| **pueblo** | Medio | — → **358.6 FPS** | — → **152.7 FPS** |
| **pueblo** | **Alto (predet.)** | 165.8 → **319.9 FPS (+92.9 %)** | 56.7 → **132.8 FPS (×2.34)** |
| **pueblo** | Ultra | — → **174.2 FPS** | — → **123.0 FPS** |
| **mina_interior** | Bajo | — → **573.0 FPS** | — → **160.8 FPS** |
| **mina_interior** | Medio | — → **523.9 FPS** | — → **189.4 FPS** |
| **mina_interior** | **Alto (predet.)** | 359.2 → **370.5 FPS (+3.1 %)** | 147.9 → **157.2 FPS** |
| **mina_interior** | Ultra | — → **190.7 FPS** | — → **131.7 FPS** |

#### B. Perfilado `medir_h14.tscn` (Calidad Alto, VSync 144 Hz, 19:30 noche)

- **pueblo:** draw calls **1165 → 857 (-26.4 %)**, primitivas **1.32M → 1.04M (-20.9 %)**, **144.3 FPS** (topado por VSync), transición **1854 ms**, trozos MultiMesh `mm=833`.
- **granja:** **143.7 FPS**, draw calls **527**, primitivas **1.88M**.
- **bosque_norte:** draw calls **656 → 627**, **144.4 FPS**, transición **852 ms**.
- **robledal_niebla:** draw calls **352 → 349**, primitivas **1.67M → 1.39M (-17.1 %)**, **143.6 FPS**.

#### C. Aislamiento por técnicas en `pueblo` (cámara a nivel de calle y barrido 360°)

- **Barrido 360° (`yaw = 0° / 90° / 180° / 270°`):** se ocultan entre **69 y 81 de 140 cuadrículas** (**680–828 nodos ocultos**) y hasta **6 de 10 NPCs** cuando quedan fuera de cámara; **587–772 draw calls** y **419k–753k primitivas** (`263.3–342.8 FPS`).
- **A nivel de suelo (`Camara_suelo`):**
  - Frustum culling por cuadrículas: **1046 → 900 draw calls**, **1.09M → 893k primitivas**, **280.8 → 306.8 FPS**.
  - Lightmaps horneados (`LightmapGI`): mejora el peor frame de **8.2 ms → 6.9 ms** (**277.9 → 306.8 FPS**).
  - Oclusores arquitectónicos (`OclusoresMapa`, 1088 triángulos): **946 → 900 draw calls** y **906k → 893k primitivas**.

---

### Técnicas implementadas

1. **Backface Culling (`CULL_BACK`):**
   - `scripts/jugador/jugador.gd` (`_activar_backface_culling()` con caché `_cache_cull_leo`): activa `CULL_BACK` en los materiales opacos del cuerpo de Leo conservando doble cara donde corresponde en accesorios/farol.
   - `scripts/pueblo/npc.gd` (`_activar_backface_culling()` con caché `_cache_cull_back`): activa `CULL_BACK` en **10/10 NPCs** del pueblo preservando prendas finas (`falda`, `chal`, `delantal`).
   - `shaders/estandar_estacional.gdshader`, `shaders/triplanar_tinte.gdshader`, `shaders/agua_h03.gdshader` y `scripts/mapas/horizonte_h05.gd`: pasan a `render_mode cull_back` (manteniendo `cull_disabled` en hojas/follaje de doble cara en `follaje_h03.gdshader` y `nieve_hojas.gdshader`).
   - Eliminado `CULL_DISABLED` innecesario en mallas sólidas de `scripts/pueblo/vida_pueblo.gd`, `scripts/granja/parcelas.gd` y materiales opacos en `cargador_mapa.gd`.

2. **Frustum Culling por cuadrículas espaciales (`scripts/mapas/cuadriculas_render.gd` + `mapa.gd`):**
   - División automática de geometría estática, props pequeños, árboles `_L2`/pequeños, bloques `MultiMeshInstance3D` (`CargadorMapa.TAM_CELDA := 38.0`) y luces puntuales en **cuadrículas de 16 m × 16 m** (`TAM_CUADRICULA := 16.0`).
   - Evaluación por los 6 planos del frustum (`MARGEN_FRUSTUM := 1.5`, zona segura `caja.grow(0.5)` y margen trasero de `8.0 m` únicamente para luces puntuales cercanas).
   - Culling de NPCs (`npc.gd`: `aplicar_culling_visual()`) ocultando únicamente su subárbol visual `_modelo` y pausando `_anim.active` para mantener operativos minimapa, físicas e interacciones.
   - `scripts/ui/foto_cenital.gd`: desactiva temporalmente occlusion/grid culling (`forzar_todo_visible(true)`, `sv.use_occlusion_culling = false`) durante capturas cenitales.

3. **Level of Detail (LOD) de mallas, sombras, props y shaders:**
   - `project.godot` y `scripts/mapas/grafica_h03.gd`: activado `mesh_lod/lod_change/threshold_pixels=2.0` y escalado por calidad (`[4.0, 2.8, 2.0, 1.2]`).
   - `CuadriculasRender`: reducción progresiva de `lod_bias`, desactivación de sombras lejanas (`SHADOW_CASTING_SETTING_OFF`) y recorte por distancia de props diminutos (`[20..46] m`), detalles (`[24..62] m`), rocas pequeñas (`[30..74] m`), hierba (`[34..80] m`), árboles pequeños (`[28..60] m`) y árboles `_L2` (`[56..125] m`).
   - **Distance LOD de Normal Maps en shaders:** apagado suave a partir de `42 m` en `estandar_estacional.gdshader`, `32–48 m` en `triplanar_tinte.gdshader` y `28 m` en `follaje_h03.gdshader`.

4. **Occlusion Culling (`cargador_mapa.gd`, `project.godot`, `grafica_h03.gd`):**
   - `occlusion_culling/use_occlusion_culling=true` y `bvh_build_quality=1` en `project.godot` y activado por viewport en `GraficaH03`.
   - `CargadorMapa._construir_oclusores()` genera el nodo `OclusoresMapa` (`OccluderInstance3D` con `ArrayOccluder3D` a partir de la geometría arquitectónica sólida; `1088` triángulos en `pueblo`).

5. **Lightmaps horneados (`LightmapGI`, `.lmbake`, `.exr`):**
   - Habilitado `meshes/light_baking=2` en los `.glb.import` de **10 mapas** (`pueblo`, `granja` a `0.45` y 8 edificios interiores a `0.25`) y horneado real en Godot Vulkan (`LightmapGI` -> `.lmbake` + `.exr`).
   - Configurados `GI_MODE_STATIC` en arquitectura/techos y `GI_MODE_DISABLED` en props pequeños (`< 4.0 m`).
   - `mapa.gd` (`_cargar_lightmap()`) carga automáticamente el `LightmapMapa` (`58/58` mallas resueltas en `pueblo`, `9/9` en `casa_leo`) y `ciclo_dia.gd` apaga el lightmap diurno de noche (`lm.visible = noche < 0.65`).

6. **Normal Maps:**
   - Reutilización de mapas normales de texturas locales en `cargador_mapa.gd` (tejados de madera, muros de piedra, rocas de cueva con proyección world-space en `estandar_estacional.gdshader`), vallas en `mapa.gd`, parcelas/rocas en `parcelas.gd` y menas exteriores compartiendo `_mat_roca_mena` en `recursos_exteriores.gd`.

---

### Verificación final de pruebas

Todas las pruebas ejecutadas tras el último cambio pasaron correctamente:
- **Headless (14 suites):**
  - `prueba_l1` (OK)
  - `prueba_l2` (OK — Leo: `28000` triángulos, `35` huesos, `30` animaciones, altura `1.97 m`)
  - `prueba_t05_animaciones` (OK — todas las comprobaciones de hueso/malla/animación de Leo)
  - `prueba_t18_vegetacion` (OK)
  - `prueba_t19_arboles` (OK)
  - `prueba_h03_entorno` (`146/146`)
  - `prueba_t11_iluminacion` (OK)
  - `prueba_t12_mapa` (`2921` comprobaciones)
  - `prueba_t16_pueblo` (`107` comprobaciones OK, `0` fallos)
  - `prueba_ajustes` (`187` comprobaciones)
  - `prueba_h04_mina` (`45` comprobaciones OK; nota: requiere `vista=0` inicial en `user://ajustes.cfg` tras ejecutar `prueba_ajustes`)
  - `prueba_h05_mapa` (`122` comprobaciones)
  - `prueba_h01_camara` (`116` aciertos, `0` errores)
  - `prueba_h02_combate` (`105` correctas, `0` fallos)
- **Vulkan Forward+ (RTX 4070):**
  - `prueba_t12_mapa` (`2935` comprobaciones OK, `rc=0`)
  - `medir_andar_m2.gd`: `andar` (`1.733 s`), `DEF-foot.L` / `DEF-foot.R` recorrido Z `0.76 m` / `0.77 m`, `y min = 0.14 m`.

---

## 3. Mejora de 13 animaciones de Leo con MotionBricks (`/home/juanjo/herramientas/motionbricks`)

- **Generación neuronal en GPU (`MotionBricksSOMAEngine`):** se generaron secuencias de movimiento SOMA sobre RTX 4070 (`mb_generate_leo.py`) y se aplicó **retargeting directo 1-salto (SOMA 77 → Leo 35 huesos `DEF-*`)** sin alterar la malla (`28.000` triángulos), textura, nombres exactos con puntos, primera persona ni los 17 clips previos de herramientas/ataques.
- **13 animaciones actualizadas en `leo.glb` (26 pistas cada una, cierre cíclico suave y contacto exacto al suelo):**
  - `reposo` (`3.567 s`), `andar` (`1.167 s`, ciclo completo izq.+der.), `correr` (`0.700 s`, ciclo atlético completo), `agachado_reposo` (`3.567 s`, cadera `0.894 → 0.663 m`, rodillas `100.5°`), `agachado_andar` (`1.067 s`, desplazamiento `0.962 m` en T05), `saltar` (`0.567 s`), `caer` (`0.500 s`), `aterrizar` (`0.433 s`), `combate_reposo` (`3.300 s`), `combate_esquiva` (`0.733 s`), `combate_esquiva_atras` (`0.733 s`).
  - `reposo_herramienta` (`3.567 s`) y `andar_herramienta` (`1.167 s`) combinan el cuerpo completo MotionBricks conservando el agarre original del brazo derecho.
- **Sincronización de velocidad en `MalaHierba/scripts/jugador/jugador.gd`:**
  - Actualizadas `VEL_SUELO_ANDAR := 1.82`, `VEL_SUELO_CORRER := 2.80`, `VEL_SUELO_AGACHADO := 1.74` (incluyendo `andar_herramienta` y tope `1.95` en sprint) para mantener las velocidades exactas de Leo sin patinaje y dar prioridad a `"correr"` al pulsar **Shift** incluso con herramienta en mano.
- **Verificación tras el cambio:** `prueba_t05_animaciones` (`OK`), `prueba_l2` (`PRUEBA OK`), `prueba_l3` (`PRUEBA OK`), `prueba_h01_camara` (`116/0`) y `prueba_h02_combate` (`105/0`).
