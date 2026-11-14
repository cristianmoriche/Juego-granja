# Mala Hierba

Juego de granja en 3D hecho con Godot 4.7.2 y Blender. Proyecto de clase de DAM de Cristian, Juan José y Daniel.

Leo, programador quemado de 45 años, hereda la finca de su abuela con una deuda de 5.000 €. Tiene un año para
sacarla adelante: cultivar, bajar a la mina, tratar con los vecinos y pagar lo que debe.

## Descargas (versión 0.2.0)

En **[Releases](../../releases/latest)**:

| Archivo | Para qué |
|---|---|
| `Mala-Hierba-0.2.0-jugar.zip` | Solo jugar. Descomprimir y doble clic en `Jugar Mala Hierba.cmd`. |
| `Godot-4.7.2-editor.zip` | El editor de Godot en la versión exacta del proyecto. |
| `Mala-Hierba-0.2.0-completo.zip` | Todo junto: juego, editor, proyecto y archivos para modelar. |

Descomprime siempre con clic derecho > «Extraer todo», no abras los archivos desde dentro del zip.

## Trabajar en el proyecto

1. Clona el repo (con GitHub Desktop: File > Clone repository > `cristianmoriche/Juego-granja`).
2. Descarga `Godot-4.7.2-editor.zip` de la Release y descomprímelo dentro del repo, de modo que quede
   `Godot 4.7.2\Godot_v4.7.2-stable_win64.exe` (esa carpeta no se sube a git).
3. Doble clic en `Abrir el proyecto en Godot.cmd`. La primera vez tarda varios minutos en importar.

Usa **siempre Godot 4.7.2**: otra versión puede romper el proyecto.

## Qué hay

| Carpeta | Qué es |
|---|---|
| `MalaHierba/` | El proyecto de Godot: escenas, scripts, datos y modelos. |
| `Para modelar/` | Lista de enemigos que hay que modelar, guía para meter modelos en el juego y los `.blend` de los personajes. |

**Si haces modelos (enemigos o personajes nuevos), empieza por
[`Para modelar/COMO METER MODELOS EN EL JUEGO.md`](Para%20modelar/COMO%20METER%20MODELOS%20EN%20EL%20JUEGO.md).**

Controles, cómo se juega y qué hacer si algo falla: en el `README.md` que viene dentro del zip del juego.

## Normas para no pisarnos

- Haz *pull* antes de empezar y sube solo lo que hayas tocado.
- No subas la carpeta `.godot/` ni el juego exportado (ya están en `.gitignore`).
- Ningún archivo puede pasar de 100 MB (límite de GitHub).
