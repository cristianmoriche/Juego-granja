# Cómo meter modelos en Mala Hierba

Guía para quien hace los enemigos de la mina y los personajes nuevos. La lista de enemigos, con tamaños, animaciones y requisitos de cada `.glb`, está en `ENEMIGOS-A-MODELAR.md`, en esta misma carpeta.

El estilo es **realista y con textura**: nada de muñecos de formas simples. Mira cómo están Leo y los vecinos en el juego antes de empezar.

## Lo que ya hay en el proyecto

| Qué | Dónde (dentro de `MalaHierba`) |
|---|---|
| Código base de los enemigos | `scripts/mina/enemigo.gd` |
| Datos de los enemigos (vida, daño, niveles, modelo) | `datos/enemigos.json` |
| Dónde aparecen en la mina | `scripts/mina/nivel_mina.gd` (puntos `SpawnEnemigo_n` en cada nivel) |
| Modelos de Leo | `assets/personajes/leo/leo.glb` |
| Modelos de los vecinos | `assets/personajes/aldeanos/<nombre>.glb` |
| Qué modelo lleva cada vecino | `datos/npcs.json`, campo `"modelo"` |

**Ojo: los enemigos están apagados.** En `enemigo.gd` hay `const ACTIVOS := false`. Con eso, la mina coloca los puntos de aparición pero no saca ningún enemigo. `datos/enemigos.json` tiene ahora solo 4 entradas de prueba con `"modelo": ""` (murciélago, babosa, centinela, brasa), que no coinciden todavía con los 16 de la lista.

## Meter un enemigo

1. **En Blender**, haz el modelo según `ENEMIGOS-A-MODELAR.md`: escala real en metros, origen en el suelo, mirando a +Z, esqueleto y las animaciones con sus nombres exactos (`reposo`, `andar` o `volar`, `atacar`, `golpeado`, `morir`; los jefes, además, `ataque_especial`).
2. **Exporta** a glTF binario (`.glb`) con nombre en minúsculas, sin espacios ni tildes: `rata_mina.glb`.
3. **Cópialo** a `MalaHierba\assets\enemigos\` (crea la carpeta si no existe). Abre el editor con `Abrir el proyecto en Godot.cmd` y espera a que lo importe.
4. **Ábrelo en Godot** (doble clic en el `.glb`) y comprueba que se ve bien, que tiene la textura y que en el `AnimationPlayer` salen las animaciones con esos nombres.
5. **Añade su entrada** en `datos/enemigos.json` (o cambia una de las de prueba), con la ruta del modelo:

```json
{
  "id": "rata_mina",
  "tipo": "corredor",
  "nombre": "Rata de mina",
  "vida": 20.0,
  "dano": 6.0,
  "velocidad": 4.5,
  "alcance_deteccion": 9.0,
  "alcance_ataque": 1.2,
  "cadencia_ataque": 1.0,
  "niveles": [1, 5],
  "modelo": "res://assets/enemigos/rata_mina.glb"
}
```

6. **Para verlo en el juego**, cambia `ACTIVOS := false` a `true` en `scripts/mina/enemigo.gd`, pulsa F5 y baja a la mina.

**Lo que todavía no está programado:** el código carga el modelo, pero no reproduce sus animaciones ni tiene los ataques especiales de los jefes. Con los `.glb` bien hechos y las animaciones bien nombradas, eso se programa después. Lo importante ahora son **los modelos**.

## Meter un personaje nuevo (vecino)

1. Modelo con el mismo estilo que los vecinos (parte de `Blender personajes\aldeanos.blend`), con esqueleto y al menos las animaciones `reposo` y `andar`.
2. Exporta a `.glb` y cópialo a `assets/personajes/aldeanos/<nombre>.glb`.
3. En `datos/npcs.json`, pon `"modelo": "<nombre>"` en el vecino que lo lleve, sin `.glb`. Para un vecino nuevo, copia el bloque de uno que ya exista y cambia `id`, `nombre` y `modelo`.
4. F5, ve al pueblo y compruébalo de cerca: cara completa, sin agujeros y a buena altura.

Pendientes de modelo propio: **la tendera y el niño** (ahora usan el cuerpo de Leo, escalado y con otro color).

## Archivos de Blender incluidos (`Blender personajes`)

- `personaje_farmer_rig.blend` y `personaje_farmer_juego.blend`: Leo con su esqueleto, para usar como base o como referencia de escala.
- `aldeanos.blend` y `texturas_aldeanos\`: los vecinos y sus texturas.
- `renders\`: imágenes de cómo quedaron.
- `scripts\crear_aldeanos.py`: el script que generó los aldeanos.

## Al terminar

Pásale a Cristian **solo** los `.glb` nuevos y los `.json` o `.gd` que hayas cambiado, no el proyecto entero. Así no se pisan los cambios de los demás.
