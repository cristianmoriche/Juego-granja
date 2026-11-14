class_name EscalaPersonaje
extends RefCounted
## Escala única de los personajes (M2). Leo y los vecinos salen de aquí: si hay que cambiar el tamaño de la gente,
## se cambia ESCALA y nada más (las casas y los mapas no se tocan).
##
## Los modelos `.glb` miden: Leo 1,97 m; vecinos entre 1,34 m (el niño) y 1,84 m (el minero). Todos se multiplican por
## la misma escala, así que las diferencias entre ellos se conservan. Con 0,89 Leo mide 1,75 m: unos 25 cm menos que
## las puertas de 2 m de la cabaña y por debajo de los aleros de las casitas del pueblo (2,0–2,7 m).

## Factor que se aplica al modelo de cada personaje (el `.glb` no se toca).
const ESCALA := 0.89
## Altura del modelo de Leo en el `.glb` (sin escalar).
const ALTURA_MODELO_LEO := 1.97
## Cápsula de colisión de pie (la de antes era radio 0,35 × 1,8 m): misma proporción con el modelo nuevo.
const RADIO := 0.35 * ESCALA
const ALTURA_PIE := 1.8 * ESCALA


## Altura de Leo en el juego (metros).
static func altura_leo() -> float:
	return ALTURA_MODELO_LEO * ESCALA
