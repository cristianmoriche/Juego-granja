# Cambio 1 — Análisis de rendimiento GPU y errores de arranque

## 1. Rendimiento bajo: uso de GPU integrada en lugar de la dedicada
- **Síntoma:** El juego funcionaba muy lento al ejecutarse en Linux.
- **Causa:** Al lanzar `godot4` sin variables de entorno de NVIDIA PRIME, el sistema asignaba la gráfica integrada **Intel (`Mesa Intel(R) Graphics (RPL-P)`)** usando **OpenGL Compatibility** e intentaba cargar `nouveau` (fallando), dejando la **NVIDIA GeForce RTX 4070 Laptop GPU** prácticamente sin uso.
- **Diferencia Windows vs Debian/Linux:** En Windows el driver de NVIDIA suele detectar el juego y cambiar automáticamente a la RTX 4070; en Debian/Linux con gráfica híbrida (Intel + NVIDIA), por defecto se ejecuta en la integrada de Intel salvo que se indique explícitamente mediante PRIME Render Offload.
- **Solución:** Lanzar el juego con NVIDIA PRIME Render Offload:
  ```bash
  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only /home/juanjo/.local/bin/godot4 --path /home/juanjo/Documentos/Juego-granja/MalaHierba --screen 1
  ```
  Con esto, Godot arranca en **Vulkan 1.4.357 - Forward+** usando `Device #0: NVIDIA - NVIDIA GeForce RTX 4070 Laptop GPU`.

## 2. Error al cargar texturas en `menu_principal.gd`
- **Archivo:** `MalaHierba/scripts/ui/menu_principal.gd` (líneas 46-47, función `_construir_fondo()`).
- **Código:**
  ```gdscript
  if ResourceLoader.exists(FONDO):
      fondo.texture = load(FONDO) as Texture2D
  ```
- **Causa:** Cuando se cambia de rama o se descarga el proyecto sin haberlo abierto antes en el editor de Godot, la carpeta `.godot/imported/` no contiene los `.ctex` compilados. `ResourceLoader.exists(FONDO)` devuelve `true` (porque existe el recurso/import), pero `load(FONDO)` falla con:
  `ERROR: Unable to open file: res://.godot/imported/fondo_menu.png-....ctex`
- **Solución:** Abrir el proyecto una vez en el editor de Godot para que genere `.godot/imported/`, o manejar el caso en que `load()` devuelva `null` sin romper el flujo.
