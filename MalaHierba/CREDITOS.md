# Créditos y licencias de Mala Hierba

**Mala Hierba** (versión 0.3.0) — *El Granado*.\
Juego de granja y mina en 3D ambientado en un valle rural español.

## Equipo de desarrollo

- **Autores**: Cristian, Juan José y Daniel.
- **Apoyo técnico y generación de recursos**: asistentes de programación (Codex, Claude y Gemini CLI) empleados para herramientas reproducibles en Python/Blender, mecánicas en GDScript e iconografía del proyecto.

## Motor y tecnología

- **Godot Engine 4.7.2** (`4.7.2.stable.official.ed1daf0bf`) — licencia **MIT** (texto completo en `licencias/godot_MIT.txt`).
- **Tipografías**: fuentes instaladas en el sistema cargadas dinámicamente mediante `SystemFont` (`Segoe UI`, `Ink Free` y equivalentes del sistema en `scripts/ui/estilo.gd` y `scripts/ui/intro.gd`), sin archivos tipográficos redistribuidos.
- **Modelado e interfaz de recursos**: Blender 5.2 y scripts reproducibles en Python (`Pillow`, `numpy`).

## Recursos externos con licencia verificada (Poly Haven · CC0 1.0)

Descargados desde [Poly Haven](https://polyhaven.com) bajo licencia **CC0 1.0 Universal** (`licencias/CC0-1.0.txt`) mediante `mapas/granja/scripts/descargar_assets.py` y `mapas/pueblo/scripts/descargar_assets_pueblo.py`:

- **Entorno e iluminación HDRI**: `assets/hdri/evening_meadow_2k.hdr`.
- **19 modelos 3D de vegetación y decoración**: `fir_tree_01`, `fir_sapling`, `pine_sapling_small`, `fern_02`, `grass_medium_01`, `rock_moss_set_01`, `rock_moss_set_02`, `tree_stump_01`, `dead_tree_trunk`, `dry_branches_medium_01`, `weed_plant_02`, `shrub_04`, `shrub_sorrel_01`, `dandelion_01`, `wooden_crate_01`, `wooden_barrels_01`, `wooden_bucket_01`, `wooden_lantern_01` y `stone_fire_pit` (con sus texturas extraídas en `assets/texturas/`).
- **16 conjuntos de texturas PBR**: `forest_ground_04`, `leafy_grass`, `sparse_grass`, `brown_mud_leaves_01`, `farm_soil`, `pine_bark`, `roof_planks`, `mossy_stone_wall`, `river_small_rocks`, `old_planks_02`, `roof_slates_02`, `weathered_plank_siding`, `castle_wall_slates`, `forest_leaves_04`, `rocky_terrain_02` y `rock_face` (junto con las texturas horneadas en `assets/mapas/*/horneado/`).
- **H02 · Escudo de cometa**, Ulan Cabanilla, CC0 1.0. Modelo y mapas adaptados a la mano de Leo en `assets/combate/escudo.glb`. [Kite Shield](https://polyhaven.com/a/kite_shield)
- **H02 · Daga medieval ornamentada**, Sofia Pahaoja, CC0 1.0. Modelo y mapas en `assets/combate/daga.glb`. [Ornate Medieval Dagger](https://polyhaven.com/a/ornate_medieval_dagger)
- **H02 · Maza medieval ornamentada**, Ulan Cabanilla, CC0 1.0. Modelo y mapas en `assets/combate/maza.glb`. [Ornate Medieval Mace](https://polyhaven.com/a/ornate_medieval_mace)
- **H02 · Martillo de guerra ornamentado**, James Ray Cock y Ulan Cabanilla, CC0 1.0. Modelo y mapas en `assets/combate/martillo_guerra.glb`. [Ornate War Hammer](https://polyhaven.com/a/ornate_war_hammer)
- **H03 · Cielos Qwantani en HDRI 4K**, Greg Zaal y Jarod Guest, CC0 1.0. Panoramas de la [madrugada](https://polyhaven.com/a/qwantani_dawn_puresky), [salida del sol](https://polyhaven.com/a/qwantani_sunrise_puresky), [mediodía](https://polyhaven.com/a/qwantani_noon_puresky), [primera tarde](https://polyhaven.com/a/qwantani_afternoon_puresky), [última tarde](https://polyhaven.com/a/qwantani_late_afternoon_puresky), [puesta del sol](https://polyhaven.com/a/qwantani_sunset_puresky), [crepúsculo](https://polyhaven.com/a/qwantani_dusk_2_puresky), [salida de la luna](https://polyhaven.com/a/qwantani_moonrise_puresky) y [noche](https://polyhaven.com/a/qwantani_night_puresky), en `assets/hdri/h03/`. La fotografía de la [mañana](https://polyhaven.com/a/qwantani_morning_puresky) es de Jarod Guest.
- **H03 · Cielos Kloofendal en HDRI 4K**, Greg Zaal, CC0 1.0. Panoramas de [cielo cubierto](https://polyhaven.com/a/kloofendal_overcast_puresky) y [niebla matinal](https://polyhaven.com/a/kloofendal_misty_morning_puresky), en `assets/hdri/h03/`.
- **H03 · Suelos PBR 2K**, CC0 1.0, en `assets/texturas/h03/`. [Stony Dirt Path](https://polyhaven.com/a/stony_dirt_path) y [Forest Floor](https://polyhaven.com/a/forest_floor), de eye-candy.xyz. [Coast Sand Rocks 02](https://polyhaven.com/a/coast_sand_rocks_02) y [Rocks Ground 06](https://polyhaven.com/a/rocks_ground_06), de Rob Tuytel.
- **H04 · Superficies PBR de mina 1K**, CC0 1.0, en `assets/texturas/h04/`. [Excavated Soil Wall](https://polyhaven.com/a/excavated_soil_wall), [Rock Wall 08](https://polyhaven.com/a/rock_wall_08), [Dark Rock](https://polyhaven.com/a/dark_rock), [Cracked Red Ground](https://polyhaven.com/a/cracked_red_ground) y [Red Laterite Soil Stones](https://polyhaven.com/a/red_laterite_soil_stones), de Amal Kumar. [Gravel Floor 02](https://polyhaven.com/a/gravel_floor_02), de Jenelle van Heerden y Dimitrios Savva. [Mossy Rock](https://polyhaven.com/a/mossy_rock) y [Burned Ground 01](https://polyhaven.com/a/burned_ground_01), de Rob Tuytel. [Rock Pitted Mossy](https://polyhaven.com/a/rock_pitted_mossy), de Dimitrios Savva y Rico Cilliers.
- **H04 · Modelos de cueva, cofre y farol**, CC0 1.0, en `assets/mina/`. [Rock Face 01](https://polyhaven.com/a/rock_face_01) de Dario Barresi; [Rock Face 02](https://polyhaven.com/a/rock_face_02) de Dario Barresi y Rico Cilliers; [Boulder 01](https://polyhaven.com/a/boulder_01) y [Treasure Chest](https://polyhaven.com/a/treasure_chest) de Rico Cilliers; [Rock 07](https://polyhaven.com/a/rock_07) y [Rock 09](https://polyhaven.com/a/rock_09) de Jenelle van Heerden; [Lantern 01](https://polyhaven.com/a/Lantern_01) de Rajil Jose Macatangay.

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
- **Combate (H02)**. Espada con mapas PBR propios, modelos de armadura para ilustrar el inventario y 24 iconos de equipo renderizados en Blender a partir de esos modelos o de los anteriores de Poly Haven. Once animaciones nuevas en el esqueleto original de Leo. Doce efectos PCM sintetizados en Python. Trabajo del proyecto con apoyo de Codex, **CC0 1.0** para los recursos nuevos. Fuentes en `juego/exportar/*_h02.py` y `juego/herramientas/generar_audio_combate_h02.py`.
- **Agua (H03)**. Mapa normal de ondas `assets/agua/ondas_normal.png`, generado con `juego/herramientas/generar_normal_agua_h03.py`. Trabajo del proyecto con apoyo de Codex, **CC0 1.0**.
- **Minas grandes (H04)**. Vagoneta de mina `assets/mina/vagoneta_mina.glb` (`juego/exportar/preparar_mina_h04.py`, reutiliza texturas PBR CC0 existentes) y 4 efectos de sonido PCM en `assets/audio/mina_*.wav` (`juego/herramientas/generar_audio_mina_h04.py`), **CC0 1.0**.
- **Mapa grande y zonas nuevas (H05)**. Modelos y texturas CC0 1.0 optimizados desde `recursos-cc0-2026-11-17/` (`rocky_trail`, `aerial_grass_rock`, `leaves_forest_ground`, `mud_forest`, `grass_path_2`, `grassy_cobblestone`, `cliff_side`, `withered_grass`, `namaqualand_cliff_01/02`, `namaqualand_boulder_02/04`, `stone_01`, `moss_01`, `dead_tree_trunk_02`, `tree_stump_02`, `root_cluster_01`, `pine_roots`, `shrub_02`, `shrub_03`, `nettle_plant`, `grass_medium_02`), además de arcos/pilares/muela/hito/roble/recolectables e iconos en `assets/naturaleza/`, `assets/texturas/h05/` y `assets/iconos/` (`juego/exportar/preparar_naturaleza_h05.py`, `juego/exportar/ampliar_zonas_h05.py`), **CC0 1.0**.
- **Granja ganadera (H12)**. Gallinero (`gallinero_roto/reparado.glb`), colmenas de corcho y de cuadros, panales, tarros de miel, huevos e iconos `128×128` preparados en Blender (`entregas/H12-granja-ganadera/`). Incorporan tres texturas PBR de Poly Haven (**CC0 1.0**): `rock_wall_08` y `dark_rock` (Amal Kumar, https://polyhaven.com/a/rock_wall_08 y https://polyhaven.com/a/dark_rock) y `rock_pitted_mossy` (Dimitrios Savva y Rico Cilliers, https://polyhaven.com/a/rock_pitted_mossy). Iconos de consumibles/herramientas (`ahumador`, `pienso_aves`, `revuelto_huevos`, `flan_miel`) y efectos PCM propios (`gallinas_cacareo`, `abejas_zumbido`, `huevo_recoger`, `abeja_picadura`, `juego/exportar/preparar_h12.py`, `juego/exportar/generar_audio_h12.py`), **CC0 1.0**.
- **Cocina y habilidades (H06)**. Modelos 3D de platos y iconos `128×128` en `assets/comida/` y `assets/iconos/` (`juego/exportar/preparar_h06.py`), **CC0 1.0**.
- **Modo foto y farol (H07)**. Modelo 3D e iluminación del farol de mano (`assets/herramientas/farol_mano.glb`, `juego/exportar/preparar_h07.py`), efecto `paso_agua.wav` y modos de captura en `scripts/ui/modo_foto.gd`, **CC0 1.0**.
- **Combate a distancia (H09)**. Arcos (`arco_leo.glb`, `arco_caza.glb`), carcaj (`carcaj_leo.glb`), proyectil (`flecha_proyectil.glb`), 7 iconos de arquería y 5 efectos de sonido PCM (`juego/exportar/preparar_arco_h09.py`, `juego/exportar/generar_audio_h09.py`), **CC0 1.0**.
- **Forja avanzada y gemas (H10)**. Horno de fundición 3D (`assets/pueblo/horno_fundicion.glb`), 4 iconos de carbón/lingotes y 2 efectos de sonido PCM (`juego/exportar/preparar_h10.py`, `juego/exportar/generar_audio_h10.py`), **CC0 1.0**.
- **Pesca avanzada (H11)**. Modelo 3D de pez en mano (`assets/herramientas/pez_mano.glb`), 11 iconos de cebos y especies nuevas y 3 efectos PCM (`juego/exportar/preparar_h11.py`, `juego/exportar/generar_audio_h11.py`), **CC0 1.0**.
- **Campamento y eventos nocturnos (H13)**. Tienda, hoguera y caldero 3D (`assets/naturaleza/campamento_h13.glb`), icono `kit_campamento.png` y 3 efectos PCM nocturnos (`juego/exportar/preparar_h13.py`), **CC0 1.0**.
- **Ranuras de aventura y logros (H14)**. Diez medallones `128×128` (`logro_*.png`) y sintonía de logro (`logro_desbloqueado.wav`, `juego/exportar/preparar_h14.py`, `juego/exportar/generar_audio_h14.py`), **CC0 1.0**.

## Recursos externos pendientes de verificación

Los siguientes activos ya se encontraban en el proyecto sin documentación de origen o licencia externa verificada (`licencias/terceros_pendientes.txt`):

- **Malla y esqueleto base originales de personajes**: `personajes/personaje_farmer.blend` y texturas heredadas (`assets/personajes/leo/leo_farmer_textured_ultra.jpg` y variantes previas en `assets/personajes/aldeanos/`). **PENDIENTE de verificación por el autor.**
- **Fondo del menú principal**: `assets/ui/fondo_menu.png`. **PENDIENTE de verificación por el autor.**
