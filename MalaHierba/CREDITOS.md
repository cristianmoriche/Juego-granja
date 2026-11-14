# Créditos y licencias de Mala Hierba

**Mala Hierba** (versión 0.2.0) — *El Granado*.  
Juego de granja y mina en 3D ambientado en un valle rural español.

## Equipo de desarrollo

- **Autores**: Cristian, Juan José y Daniel.
- **Apoyo técnico y generación de recursos**: asistentes de programación (Codex y Gemini CLI) empleados para herramientas reproducibles en Python/Blender, mecánicas en GDScript e iconografía del proyecto.

## Motor y tecnología

- **Godot Engine 4.7.2** (`4.7.2.stable.official.ed1daf0bf`) — licencia **MIT** (texto completo en `licencias/godot_MIT.txt`).
- **Tipografías**: fuentes instaladas en el sistema cargadas dinámicamente mediante `SystemFont` (`Segoe UI`, `Ink Free` y equivalentes del sistema en `scripts/ui/estilo.gd` y `scripts/ui/intro.gd`), sin archivos tipográficos redistribuidos.
- **Modelado e interfaz de recursos**: Blender 5.2 y scripts reproducibles en Python (`Pillow`, `numpy`).

## Recursos externos con licencia verificada (Poly Haven · CC0 1.0)

Descargados desde [Poly Haven](https://polyhaven.com) bajo licencia **CC0 1.0 Universal** (`licencias/CC0-1.0.txt`) mediante `mapas/granja/scripts/descargar_assets.py` y `mapas/pueblo/scripts/descargar_assets_pueblo.py`:

- **Entorno e iluminación HDRI**: `assets/hdri/evening_meadow_2k.hdr`.
- **19 modelos 3D de vegetación y decoración**: `fir_tree_01`, `fir_sapling`, `pine_sapling_small`, `fern_02`, `grass_medium_01`, `rock_moss_set_01`, `rock_moss_set_02`, `tree_stump_01`, `dead_tree_trunk`, `dry_branches_medium_01`, `weed_plant_02`, `shrub_04`, `shrub_sorrel_01`, `dandelion_01`, `wooden_crate_01`, `wooden_barrels_01`, `wooden_bucket_01`, `wooden_lantern_01` y `stone_fire_pit` (con sus texturas extraídas en `assets/texturas/`).
- **16 conjuntos de texturas PBR**: `forest_ground_04`, `leafy_grass`, `sparse_grass`, `brown_mud_leaves_01`, `farm_soil`, `pine_bark`, `roof_planks`, `mossy_stone_wall`, `river_small_rocks`, `old_planks_02`, `roof_slates_02`, `weathered_plank_siding`, `castle_wall_slates`, `forest_leaves_04`, `rocky_terrain_02` y `rock_face` (junto con las texturas horneadas en `assets/mapas/*/horneado/`).

## Recursos propios del proyecto

- **Escenarios y edificios originales**: mapa de la granja, pueblo, capilla, tienda, herrería, taberna, casa de Leo, casa del alcalde, casitas, bosque norte, costa del lago y mina (exterior e interior de 20 niveles), modelados y exportados en Blender (`mapas/*`, `juego/exportar/exportar_mapa.py`, `juego/exportar/crear_zonas_t25.py`).
- **Superficies y caras de personajes (T02)**: geometría cerrada, caras con ojos, nariz, boca, orejas y cabello y materiales opacos para Leo y los seis modelos de vecinos, generados en local mediante `gestion/noche-codex/herramientas/T02-personajes/reconstruir.py` (**CC0 1.0**). Se conservan esqueletos y accesorios preexistentes de `assets/personajes/`.
- **Animaciones de personaje y herramientas en mano (T05, T21)**:
  - Animaciones añadidas sobre los 35 huesos de Leo en Blender 5.2 (`juego/exportar/animar_herramientas_leo_t21.py` y `juego/exportar/animaciones_leo.json`, **CC0 1.0**).
  - 11 modelos 3D en `assets/herramientas/*.glb` (`juego/exportar/crear_herramientas_t21.py`, **CC0 1.0** para la geometría nueva; reutilizan texturas CC0 de `assets/texturas/`).
- **Muebles y decoración de casa (T24)**: 20 modelos `.glb` en `assets/muebles/` y 20 iconos renderizados en Blender (`juego/exportar/crear_muebles_t24.py`, **CC0 1.0**; reutilizan texturas CC0 de `assets/texturas/` y texturas procedimentales propias).
- **Iconos de interfaz (T01, T10, T15, T25, T26)**:
  - 52 iconos originales de objetos y mejoras (T01) generados por Codex con la herramienta de imágenes de OpenAI (conservados en `gestion/noche-codex/recursos/T01-iconos/`), sin material externo con atribución obligatoria.
  - 17 iconos adicionales (caña, peces, minerales y pociones/misiones) y el icono del ejecutable (`assets/ui/icono.png`, `assets/ui/icono.ico`, T10) generados con herramientas de imagen de Gemini CLI para Mala Hierba (`gestion/noche-codex/recursos/`), para un total de 89 iconos en `assets/iconos/`.
- **Música, ambientes y efectos de sonido (T07)**: 24 archivos WAV PCM 16-bit (pico ≤ -3 dB) en `assets/audio/` sintetizados localmente en Python (`juego/herramientas/generar_audio.py`, `numpy` y `wave`, **CC0 1.0**). Incluyen pasos, golpes de herramientas, cosecha, puertas, interfaz, 3 bucles de ambiente y 5 músicas de 64–72 s.

## Recursos externos pendientes de verificación

Los siguientes activos ya se encontraban en el proyecto sin documentación de origen o licencia externa verificada (`licencias/terceros_pendientes.txt`):

- **Malla y esqueleto base originales de personajes**: `personajes/personaje_farmer.blend` y texturas heredadas (`assets/personajes/leo/leo_farmer_textured_ultra.jpg` y variantes previas en `assets/personajes/aldeanos/`). **PENDIENTE de verificación por el autor.**
- **Fondo del menú principal**: `assets/ui/fondo_menu.png`. **PENDIENTE de verificación por el autor.**
