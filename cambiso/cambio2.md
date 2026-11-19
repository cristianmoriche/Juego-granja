# Cambio 2 — Recursos sin importar en `.godot/imported/`

## Error detectado
Al ejecutar el juego directamente tras descargar la rama `main`, Godot mostraba múltiples errores de carga de modelos `.glb` y texturas `.png`, por ejemplo:
- `ERROR: Cannot open file 'res://.godot/imported/pine_sapling_small_b.glb-...scn'`
- `ERROR: Cannot open file 'res://.godot/imported/rock_moss_set_02_rock10.glb-...scn'`
- `ERROR: Cannot open file 'res://.godot/imported/mora_silvestre.glb-...scn'`
- `ERROR: Cannot open file 'res://.godot/imported/hierba_monte.glb-...scn'`
- `WARNING: 'res://assets/granja/colmena_corcho.glb': invalid UID ...`

## Causa
La carpeta `.godot/imported/` (ignorada en Git) no había sido generada todavía para los nuevos assets de `main`. Al lanzar el juego sin pasar por el editor ni ejecutar una importación previa, Godot no encontraba los archivos compilados (`.scn`, `.ctex`, etc.) correspondientes a los `.import`.

## Solución aplicada
Se ejecutó la importación en modo headless de Godot para compilar y cachear todos los recursos del proyecto:
```bash
/home/juanjo/.local/bin/godot4 --headless --path /home/juanjo/Documentos/Juego-granja/MalaHierba --import
```
