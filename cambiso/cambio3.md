# Cambio 3 — Optimización profunda del juego (GPU Vulkan Forward+, Shaders, Geometría, Física y CPU)

## Resumen de resultados (NVIDIA GeForce RTX 4070 Laptop GPU · Vulkan Forward+ · 1920×1080)

### 1. Comparativa `capturas_h03.tscn` (sin VSync, primera persona, 14:00, sol)

| Mapa | Calidad | FPS medios (Antes → Después) | Mejora FPS | 1 % más lento (Antes → Después) | Carga (Antes → Después) |
|---|---|---:|---:|---:|---:|
| **granja** | Bajo | 220.0 → **305.5** | +38.9 % | 109.6 → **132.9** | 3597 ms → **1866 ms** (-48.1 %) |
| **granja** | Medio | 178.2 → **346.7** | +94.6 % | 43.7 → **153.0** | — |
| **granja** | **Alto (predet.)** | 183.6 → **282.1** | **+53.6 %** | 54.3 → **85.6** | — |
| **granja** | Ultra | 120.8 → **148.7** | +23.1 % | 66.3 → 25.6 | — |
| **pueblo** | Bajo | 253.1 → **261.4** | +3.3 % | 115.3 → 109.7 | 1977 ms → 2388 ms |
| **pueblo** | Medio | 227.1 → **294.1** | +29.5 % | 111.8 → **123.4** | — |
| **pueblo** | **Alto (predet.)** | 169.1 → **301.4** | **+78.2 %** | 91.3 → **140.9** | — |
| **pueblo** | Ultra | 123.4 → **170.4** | +38.1 % | 76.2 → **104.0** | — |
| **mina_interior** | Bajo | 589.1 → **676.6** | +14.9 % | 201.7 → **223.2** | 7655 ms → **2181 ms** (-71.5 %) |
| **mina_interior** | Medio | 525.0 → 506.6 | -3.5 % | 200.2 → 170.3 | — |
| **mina_interior** | **Alto (predet.)** | 197.8 → **369.9** | **+87.0 %** | 124.3 → **152.6** | — |
| **mina_interior** | Ultra | 107.2 → **190.8** | **+78.0 %** | 36.9 → **107.2** | — |

### 2. Perfilado de escenas densas `medir_h14.tscn` (Calidad Alto, VSync 144 Hz, 19:30 noche)
- **pueblo (19:30 con 17 luces):** pasó de **45.4 FPS → 144.1 FPS** (topado por VSync), primitivas **2.92M → 1.46M (-50 %)**, transición **2974 ms → 1470 ms**.
- **granja:** primitivas **3.36M → 1.82M (-46 %)**, transición **4070 ms → 1775 ms**.
- **bosque_norte:** primitivas **6.38M → 2.08M (-67 %)**, transición **3095 ms → 723 ms**.
- **robledal_niebla:** primitivas **3.16M → 1.74M (-45 %)**, transición **3136 ms → 901 ms**.
- **VRAM:** menú inicial **137.4 MB → 96.4 MB**, tras recorrer 4 zonas **764.6 MB → 585.5 MB (-23.4 %)**.

---

## Optimizaciones aplicadas

### 1. Configuración base y pipeline Forward+ (`project.godot`, `grafica_h03.gd`, `ajustes.gd`)
- **`MalaHierba/project.godot`:** `msaa_3d=0`, `anisotropic_filtering_level=2`, `directional_shadow/size=2048`, `positional_shadow/atlas_size=2048`, `screen_space_reflection/half_size=true`.
- **`MalaHierba/scripts/mapas/grafica_h03.gd`:**
  - `aplicar_calidad_servidor()` con caché de nivel/viewport (`_ultimo_nivel_servidor`, `_ultimo_vp_rid`) para no recrear buffers innecesariamente, shadow atlases en potencias de 2, SSAO/SSIL en media resolución con fadeout temprano y menos blur passes en Alto, SSR en half-size y 16 pasos en Alto (32 en Ultra), Volumetric Fog a `32×32×48` en Alto (`64×64×64` en Ultra), y SDFGI optimizado en Ultra (`8` rayos, convergencia en `10` frames).
  - En `ajustar_sol()`: `SHADOW_PARALLEL_2_SPLITS` hasta Alto y `4_SPLITS` + `blend_splits` + `light_angular_distance` solo en Ultra.
  - En `ajustar_luz()`: `distance_fade_shadow` acotado (`12.0` en Alto, `20.0` en Ultra).
- **`MalaHierba/scripts/autoload/ajustes.gd`:**
  - En `_escala_render()`: uso de `SCALING_3D_MODE_FSR` + `FXAA` en lugar de `FSR2` cuando `escala < 1.0` (ahorra ~1.5–2 ms/frame y elimina el warning `FSR 2 is not compatible with TAA`).
  - En `aplicar_graficos()`: filtro de sombras suaves ajustado (`HARD / SOFT_VERY_LOW / SOFT_LOW / SOFT_MEDIUM`).
  - En `_nodo_anadido()` / `_interfaz_nodo()`: fast-path que evita clonar `StyleBoxFlat` y repintar cada control cuando `texto == 0` y `alto_contraste == false`.
- **`MalaHierba/scripts/mapas/recursos_exteriores.gd`:** corregido `GraficaH03.ajustar_luz(luz, true)` que pasaba `bool` en lugar de `int(Ajustes.valores.calidad)`.

### 2. Instancing, árboles, rocas y luces (`cargador_mapa.gd`)
- **Celdas espaciales (`TAM_CELDA := 42.0`):** balance óptimo entre número de draw calls y frustum culling por celda.
- **GI desactivado en vegetación y rocas (`GI_MODE_DISABLED`)** y sombras/alcance optimizados en rocas pequeñas (`rock_moss_set_02_*`, `stone_01`).
- **Árboles con auto-LOD optimizado:** `lod_bias` reducido en `_L2` (`0.035`) y saplings (`0.035`), acotando distancias de visibilidad sin perder fidelidad visual ni mallas `LOD1` cercanas.
- **Refuerzo de hierba:** reducido de `1/3` a `1/6` de instancias cercanas manteniendo el atributo `INSTANCE_CUSTOM`.
- **Límite de luces con sombra dinámica:** `MAX_SOMBRAS_EXT := 2` en exteriores y `MAX_SOMBRAS_INT := 4` en interiores; y en `actualizar_iluminacion_hora()` solo se llama a `GraficaH03.ajustar_luz()` cuando cambia el estado efectivo de sombra o calidad.

### 3. Optimización de Shaders GPU
- **`shaders/estandar_estacional.gdshader`:** eliminado fetch muerto de normal map; derivadas `dFdx`/`dFdy` precalculadas fuera de ramas y muestreo de detalle condicional (`cobertura > 0.001`); paralaje reducido a `4` pasos en Alto (`6` en Ultra) y rango `< 11 m`.
- **`shaders/triplanar_tinte.gdshader` y `scripts/mina/generador_caverna_h04.gd` (`SHADER_CAVERNAS_PBR`):** uso de `textureGrad` con derivadas calculadas fuera de ramas y skip de ejes cuyo peso triplanar `w.* <= 0.01` (y skip pared/suelo según `es_suelo`), reduciendo hasta un 66 % las lecturas de textura por píxel.
- **`shaders/follaje_h03.gdshader`:** cálculo temprano de distancia/cobertura en `vertex()` para saltar cálculo de viento en hierba oculta o refuerzo fuera de alcance, y simplificación a 1 onda de viento a `> 40 m`.
- **`shaders/agua_h03.gdshader`:** raymarch SSR de `8` pasos en Alto (`12` en Ultra) solo a `< 55 m`, y skip de doble muestreo de profundidad para refracción a `> 60 m`.
- **`shaders/cielo_h03.gdshader`:** skip de muestreo de `panorama_a`/`panorama_b` en extremos de transición o nubosidad total.

### 4. Optimización de CPU, UI y Física
- **`scripts/ui/minimapa.gd`:** círculo precalculado en `_ready()`, polígono de límites predividido con `draw_multiline()`, caché de grupos `salida`/`puerta`, y dirty-checking en `_process()` (redibuja solo si cambia posición, cámara, textura o cada 0.10 s para NPCs/niebla).
- **`scripts/jugador/jugador.gd`:** caché de nodos `decoracion_casa` y `parcelas_apuntables`, throttling adaptativo del raycast de apuntado (`_actualizar_interactuable`) según movimiento, caché de comprobación de límites del polígono cuando está quieto, y emisión de nivel de agua a `Audio` solo ante cambios `> 0.01`.
- **`scripts/pueblo/npc.gd`:** skip de `move_and_slide()` cuando el NPC está quieto en el suelo (solo ejecuta 1 tick de comprobación cada 12 ticks).
- **`scripts/mapas/mapa.gd`:** `next_pass` de nieve en vallas y toldo activado únicamente en invierno (`estacion == 3`) y partículas de lluvia/nieve escaladas según calidad.

---

## Verificación
Todas las pruebas de regresión headless ejecutadas tras el último cambio pasaron con éxito:
- `prueba_l1` (OK)
- `prueba_t18_vegetacion` (OK)
- `prueba_t19_arboles` (OK)
- `prueba_h03_entorno` (146/146)
- `prueba_t11_iluminacion` (OK)
- `prueba_t12_mapa` (OK, 2921 comprobaciones)
- `prueba_ajustes` (OK, 187 comprobaciones)
- `prueba_h04_mina` (OK, 45 comprobaciones)
- `prueba_h05_mapa` (OK, 122 comprobaciones)
- `prueba_h01_camara` (116 aciertos, 0 errores)
- `prueba_h02_combate` (105 correctas, 0 fallos)
