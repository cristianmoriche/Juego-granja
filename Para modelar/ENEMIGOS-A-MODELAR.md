# Enemigos de la mina para modelar

La mina tiene 20 niveles, repartidos en 4 zonas de 5 niveles cada una. El estilo es realista: animales y criaturas creíbles, no de dibujo animado.

| N.º | Enemigo | Niveles | Tamaño | Cómo es | Se mueve |
|---|---|---|---|---|---|
| **Piedra (1–5)** |
| 1 | Rata de mina | 1–5 | 40 cm | Rata grande, pelo sucio y polvoriento, ojos rojizos | Corre |
| 2 | Murciélago de cueva | 1–10 | 50 cm de envergadura | Murciélago oscuro con orejas grandes | Vuela |
| 3 | Escarabajo de roca | 3–8 | 60 cm | Escarabajo con caparazón que parece piedra | Anda lento |
| J1 | **Rata reina** (jefe del nivel 5) | 5 | 1,2 m | Rata enorme, cicatrices y pelo apelmazado | Corre y embiste |
| **Húmeda, con agua (6–10)** |
| 4 | Babosa de gruta | 6–10 | 70 cm | Babosa gigante translúcida que deja un rastro brillante | Repta |
| 5 | Sapo ciego | 6–10 | 50 cm | Sapo pálido de cueva, sin ojos y con piel húmeda | Salta |
| 6 | Ciempiés gigante | 8–13 | 1,5 m de largo | Ciempiés rojizo y segmentado | Repta rápido |
| J2 | **Sapo gigante** (jefe del nivel 10) | 10 | 2 m | Sapo ciego enorme con verrugas y lengua larga | Salta y ataca con la lengua |
| **Cristal (11–15)** |
| 7 | Araña de cristal | 11–15 | 80 cm | Araña con cristales de cuarzo azul que le salen del lomo | Anda rápido |
| 8 | Polilla luminosa | 11–15 | 40 cm | Polilla con alas que brillan en azul | Vuela |
| 9 | Gólem de cuarzo | 12–15 | 1,6 m | Figura humanoide hecha de bloques de roca y cuarzo | Anda pesado |
| J3 | **Araña madre** (jefe del nivel 15) | 15 | 2,5 m | Araña de cristal enorme con el cuerpo lleno de cristales | Anda y lanza cristales |
| **Magma (16–20)** |
| 10 | Salamandra de magma | 16–20 | 1 m | Salamandra negra con grietas brillantes de lava | Corre |
| 11 | Escorpión de ceniza | 16–20 | 1 m | Escorpión gris ceniza con la cola al rojo | Anda y pica |
| 12 | Gólem de magma | 18–20 | 2 m | Gólem de roca volcánica con lava entre las piedras | Anda pesado |
| J4 | **Gusano de magma** (jefe final, nivel 20) | 20 | 6 m de largo | Gusano gigante acorazado que sale del suelo de lava | Emerge, se hunde y ataca |

En total son 16 modelos: 12 enemigos y 4 jefes.

## Animaciones que necesita cada uno
Ponles estos nombres exactos:
- `reposo`
- `andar` (o `volar` en el murciélago y la polilla)
- `atacar`
- `golpeado`
- `morir`

Los jefes llevan además `ataque_especial`, y el gusano también `emerger` y `hundirse`.

## Cómo entregarlos
- Un archivo `.glb` por enemigo, con su esqueleto y las animaciones dentro.
- Escala real en metros, con el origen en el suelo, entre los pies.
- Mirando hacia delante en +Z (lo normal al exportar glTF desde Blender).
- Entre 3.000 y 8.000 triángulos en los normales y 20.000 como máximo en los jefes.
- Una textura de 2048 px por enemigo: color, normal y rugosidad. En la de magma, la de cristal, la babosa y la polilla, también emisión.
- La malla cerrada, sin agujeros ni caras sueltas.
- Nombre de archivo en minúsculas, sin espacios ni tildes: `rata_mina.glb`, `murcielago.glb`, `escarabajo_roca.glb`, `rata_reina.glb`, `babosa_gruta.glb`, `sapo_ciego.glb`, `ciempies.glb`, `sapo_gigante.glb`, `arana_cristal.glb`, `polilla_luminosa.glb`, `golem_cuarzo.glb`, `arana_madre.glb`, `salamandra_magma.glb`, `escorpion_ceniza.glb`, `golem_magma.glb`, `gusano_magma.glb`.
