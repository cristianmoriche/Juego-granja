# Mala Hierba · los 6 aldeanos, variantes del protagonista (personaje_farmer.blend).
#
# El protagonista es una sola malla escultural con una textura de 4096 px (sin armature, sin shape keys,
# sin grupos de vértices). Por eso las variantes se consiguen así:
#   1. Se carga (append, nunca se modifica el original), se suelda, se decima y se pone el origen a los pies.
#   2. La textura se clasifica por colores (piel, tela roja, vaquero, cuero, paja...) y se «pinta» por script
#      para cada aldeano: ropa, piel, pelo y barba. Se guarda una textura de 2048 px por aldeano.
#   3. La malla se deforma por regiones (altura, anchura, brazos más finos, barriga, cabeza mayor, espalda
#      encorvada) con numpy.
#   4. Las piezas nuevas se modelan por script: pelo, delantal, chal, falda, mangas, chaleco, casco, pico, bastón...
#      Las prendas que se ajustan al cuerpo usan el modificador Shrinkwrap sobre la propia malla.
# Uso:
#   blender -b --factory-startup -P crear_aldeanos.py -- preview|final
# Salida: ../aldeanos.blend (colecciones Aldeano_*), ../renders/aldeanos_{preview,final}.png y
#   ../texturas_aldeanos/*.jpg.
# Variables de entorno opcionales para pruebas: ALDEANOS=herrero,nino  RENDER=0 (no renderiza)
#   ALDEA_CERCA=carpeta (en vez del render de la fila, vistas de cuerpo, cabeza y espalda de cada aldeano).
import bpy, bmesh, math, os, random, sys, time
import numpy as np
from mathutils import Vector, Matrix, Euler

CALIDAD = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "preview"
AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, ".."))                       # .../personajes
JUEGO = os.path.normpath(os.path.join(RAIZ, ".."))                      # .../juego-personajes
PROTAGONISTA = os.path.join(RAIZ, "personaje_farmer.blend")
DIR_TEX = os.path.join(RAIZ, "texturas_aldeanos")
DIR_RENDER = os.path.join(RAIZ, "renders")
SALIDA_BLEND = os.path.join(RAIZ, "aldeanos.blend")
HDRI = os.path.join(JUEGO, "mapas", "granja", "assets", "hdri", "evening_meadow_2k.hdr")
RES = 2048                      # resolución de las texturas de los aldeanos
RATIO_DECIMADO = 0.30           # la malla original tiene 584.000 triángulos: demasiados para un aldeano
T0 = time.time()


def log(*a):
    print(f"[{time.time() - T0:6.1f}s]", *a, flush=True)


# ================================================================ utilidades de malla y numpy
def suave(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def coords(me):
    n = len(me.vertices)
    c = np.empty(n * 3, np.float32)
    me.vertices.foreach_get("co", c)
    return c.reshape(-1, 3)


def poner_coords(me, c):
    me.vertices.foreach_set("co", np.ascontiguousarray(c, dtype=np.float32).reshape(-1))
    me.update()


def uv_de_bucles(me):
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers[0].data.foreach_get("uv", uv)
    return uv.reshape(-1, 2)


def vertice_de_bucles(me):
    lv = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", lv)
    return lv


def ruido_fbm(forma, escala, octavas=5, semilla=0):
    """Ruido de valores fractal en 2D (0..1) hecho con numpy: sirve para suciedad y manchas."""
    rng = np.random.default_rng(semilla)
    h, w = forma
    out = np.zeros(forma, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octavas):
        n = max(2, int(escala * (2 ** o)))
        g = rng.random((n + 1, n + 1)).astype(np.float32)
        ys = np.linspace(0, n, h, endpoint=False, dtype=np.float32)
        xs = np.linspace(0, n, w, endpoint=False, dtype=np.float32)
        y0 = ys.astype(int); x0 = xs.astype(int)
        fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
        fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
        a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        tot += amp
        amp *= 0.5
    return out / tot


def caja_blur(a, veces=1):
    """Desenfoque de caja 3x3 repetido (numpy puro)."""
    for _ in range(veces):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0)) / 3.0
        a = (a + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 3.0
    return a


# ================================================================ carga y preparación de la base
class Base:
    """Datos compartidos por todos los aldeanos: malla limpia, mapas de clases y de posiciones."""
    pass


def cargar_base():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(PROTAGONISTA, link=False) as (src, dst):
        dst.objects = ["GEO-Farmer_Ultra"]
    ob = dst.objects[0]
    bpy.context.scene.collection.objects.link(ob)
    me = ob.data
    img0 = [i for i in bpy.data.images if i.name == "TEX-FarmerUltra_Albedo"][0]
    # La malla del protagonista tiene el eje Y hacia arriba con el objeto girado 90°: se hornea la transformación.
    me.transform(ob.matrix_basis)
    ob.matrix_basis = Matrix.Identity(4)
    # Soldar los vértices que el protagonista tiene duplicados en las costuras de UV (373 k -> 281 k).
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(me); bm.free()
    # Origen a los pies: z mínima = 0; x centrada; y centrada entre los pies.
    c = coords(me)
    pies = c[c[:, 2] < 0.25]
    dx = (pies[:, 0].min() + pies[:, 0].max()) / 2
    dy = (pies[:, 1].min() + pies[:, 1].max()) / 2
    c -= np.array([dx, dy, c[:, 2].min()], np.float32)
    poner_coords(me, c)
    log("granjero soldado:", len(me.vertices), "vértices,", len(me.polygons), "triángulos; altura", round(float(c[:, 2].max()), 3))

    b = Base()
    b.res = RES
    # --- mapa de posiciones 3D de cada texel (a partir de la malla soldada completa)
    lv = vertice_de_bucles(me); uv = uv_de_bucles(me)
    tv = lv.reshape(-1, 3); tuv = uv.reshape(-1, 3, 2)
    cen_uv = tuv.mean(1); cen_p = c[tv].mean(1)
    pos = np.zeros((RES, RES, 3), np.float32); ok = np.zeros((RES, RES), bool)
    ix = np.clip((cen_uv[:, 0] * RES).astype(int), 0, RES - 1); iy = np.clip((cen_uv[:, 1] * RES).astype(int), 0, RES - 1)
    pos[iy, ix] = cen_p; ok[iy, ix] = True
    for k in range(3):
        jx = np.clip((tuv[:, k, 0] * RES).astype(int), 0, RES - 1); jy = np.clip((tuv[:, k, 1] * RES).astype(int), 0, RES - 1)
        sel = ~ok[jy, jx]
        pos[jy[sel], jx[sel]] = c[tv[:, k]][sel]; ok[jy[sel], jx[sel]] = True
    for _ in range(3):
        nuevo = pos.copy(); nok = ok.copy()
        for dy_, dx_ in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            sp = np.roll(np.roll(pos, dy_, 0), dx_, 1); so = np.roll(np.roll(ok, dy_, 0), dx_, 1)
            sel = (~nok) & so
            nuevo[sel] = sp[sel]; nok |= sel
        pos, ok = nuevo, nok
    b.pos = pos
    # --- textura original a RESxRES (valores tal como están guardados, sin linealizar)
    im = img0.copy(); im.scale(RES, RES)
    px = np.empty(RES * RES * 4, np.float32); im.pixels.foreach_get(px)
    b.px = px.reshape(RES, RES, 4)[:, :, :3].copy()
    bpy.data.images.remove(im)
    # --- clasificación por color (HSV)
    r, g, bl = b.px[..., 0], b.px[..., 1], b.px[..., 2]
    mx = b.px.max(-1); mn = b.px.min(-1); d = np.maximum(mx - mn, 1e-6)
    v = mx; s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)
    h = np.where(mx == r, ((g - bl) / d) % 6, np.where(mx == g, (bl - r) / d + 2, (r - g) / d + 4)) / 6.0
    b.h, b.s, b.v = h.astype(np.float32), s.astype(np.float32), v.astype(np.float32)
    X, Y, Z = pos[..., 0], pos[..., 1], pos[..., 2]
    b.X, b.Y, b.Z = X, Y, Z
    CL = {"otro": 0, "denim": 1, "rojo": 2, "piel": 3, "paja": 4, "marron": 5, "oscuro": 6}
    cls = np.zeros((RES, RES), np.uint8)
    cls[(h < 0.17) & (v <= 0.5)] = CL["marron"]
    cls[(h >= 0.075) & (h < 0.17) & (v > 0.5)] = CL["paja"]
    cls[(h >= 0.02) & (h < 0.075) & (s > 0.18) & (s < 0.7) & (v > 0.45)] = CL["piel"]
    rojo = (((h > 0.92) | (h < 0.02)) & (s > 0.35) & (v > 0.15)) | ((h >= 0.02) & (h < 0.04) & (s > 0.62) & (v > 0.15))
    cls[rojo] = CL["rojo"]
    cls[v < 0.14] = CL["oscuro"]
    cls[(h > 0.48) & (h < 0.68) & (s > 0.12)] = CL["denim"]
    b.cls = cls
    b.CL = CL

    # --- decimar (la malla soldada queda en un solo trozo, con algo de geometría no múltiple)
    mod = ob.modifiers.new("dec", "DECIMATE"); mod.ratio = RATIO_DECIMADO
    with bpy.context.temp_override(object=ob, active_object=ob):
        bpy.ops.object.modifier_apply(modifier="dec")
    log("decimado:", len(me.vertices), "vértices,", len(me.polygons), "triángulos")
    ob.name = "Base_granjero"; me.name = "Base_granjero"
    b.ob = ob
    b.imagen_original = img0
    # --- quitar el sombrero de paja (todos los aldeanos van sin él) y los trozos sueltos que deja
    cl = clase_de_vertices(b, me); c = coords(me)
    sombrero = ((cl == CL["paja"]) & (c[:, 2] > 1.72)) | ((c[:, 2] > 1.80) & (np.hypot(c[:, 0], c[:, 1] + 0.06) > 0.235))         | ((c[:, 2] > 1.775) & (np.abs(c[:, 0]) > 0.15) & (np.abs(c[:, 0]) < 0.30) & (c[:, 1] > -0.16))
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(sombrero)[0]], context="VERTS")
    bm.verts.ensure_lookup_table()
    comp = [-1] * len(bm.verts); tam = []
    for v0 in bm.verts:
        if comp[v0.index] >= 0:
            continue
        pila = [v0]; comp[v0.index] = len(tam); n = 0
        while pila:
            a = pila.pop(); n += 1
            for e in a.link_edges:
                o = e.other_vert(a)
                if comp[o.index] < 0:
                    comp[o.index] = len(tam); pila.append(o)
        tam.append(n)
    grande = int(np.argmax(tam))
    sueltos = [bm.verts[i] for i in range(len(bm.verts)) if comp[i] != grande]
    bmesh.ops.delete(bm, geom=sueltos, context="VERTS")
    bm.to_mesh(me); bm.free()
    log("sin sombrero:", len(me.vertices), "vértices (quitados", int(sombrero.sum()), "del sombrero y", len(sueltos), "sueltos)")
    # --- máscaras de la textura por regiones (suavizadas un poco para que no queden bordes duros)
    CLs = cls
    cab = Z > 1.58
    m = {}
    # La barba se define por zona (parte baja de la cara) y no solo por color, para no teñir la cara de negro.
    zona_barba = (np.abs(X) < 0.23) & (Z > 1.50) & (Z < 1.785) & (Y < 0.0)
    ventana_nariz = (np.abs(X) < 0.03) & (Z > 1.735) & (Y < -0.19)
    barba = zona_barba & ~ventana_nariz & ((CLs == CL["marron"]) | (CLs == CL["oscuro"]) | ((CLs == CL["piel"]) & (Z < 1.70) & (np.abs(X) < 0.16)))
    # Banda de sombra del ala del sombrero sobre los ojos: se aclara, que sin sombrero parecería un antifaz.
    banda = (Z > 1.79) & (Z < 1.87) & (np.abs(X) < 0.16) & (Y < -0.10) & ((CLs == CL["oscuro"]) | (CLs == CL["marron"]))
    wb = caja_blur(banda.astype(np.float32), 2)[..., None]
    b.px = b.px * (1 - wb) + (1.0 - (1.0 - b.px) * 0.55) * wb
    cara = (Z > 1.64) & (Z < 1.88) & (Y < 0.0) & (np.abs(X) < 0.17)        # delante de la cabeza: nariz, mejillas, labios
    m["piel_cuerpo"] = (CLs == CL["piel"]) & ~cab
    m["piel_cara"] = ((CLs == CL["piel"]) & cab & ~barba) | banda | (cara & (CLs == CL["rojo"]) & ~barba)
    m["pelo"] = barba
    barba_todo = zona_barba & ((CLs == CL["marron"]) | (CLs == CL["oscuro"]) | ((CLs == CL["piel"]) & (Z < 1.70) & (np.abs(X) < 0.16)))
    m["pelo_todo"] = barba_todo
    m["camisa"] = (((CLs == CL["rojo"]) & (Z > 1.0)) | ((CLs == CL["oscuro"]) & (Z > 1.0) & (Z <= 1.58))) & ~cara
    m["babero"] = (CLs == CL["denim"]) & (Z >= 1.05)
    m["pantalon"] = (CLs == CL["denim"]) & (Z < 1.05)
    m["botas"] = (CLs == CL["marron"]) & (Z < 0.40)
    m["guante"] = (CLs == CL["paja"]) & (Z > 0.6) & (Z < 1.25)
    b.m = {k: caja_blur(v.astype(np.float32), 2) for k, v in m.items()}
    return b


def clase_de_vertices(base, me):
    """Clase de color (mapa de clases) y posición en la textura de cada vértice de `me` según su UV."""
    uv = uv_de_bucles(me); lv = vertice_de_bucles(me)
    ix = np.clip((uv[:, 0] * base.res).astype(int), 0, base.res - 1); iy = np.clip((uv[:, 1] * base.res).astype(int), 0, base.res - 1)
    cl = np.zeros(len(me.vertices), np.uint8)
    cl[lv] = base.cls[iy, ix]
    return cl



# ================================================================ forma del cuerpo (deformación por regiones)
# Eje de cada brazo del protagonista (lado +X) medido sobre su malla: del hombro a la mano. El otro lado es el espejo.
BRAZO = np.array([(0.358, 0.098, 1.57), (0.400, 0.113, 1.45), (0.450, 0.130, 1.33), (0.488, 0.138, 1.21),
                  (0.543, 0.128, 1.09), (0.598, 0.086, 1.03), (0.605, 0.045, 0.95), (0.619, -0.007, 0.85),
                  (0.635, 0.020, 0.77), (0.626, 0.033, 0.70)], np.float32)


def aristas(me):
    e = np.empty(len(me.edges) * 2, np.int32)
    me.edges.foreach_get("vertices", e)
    return e.reshape(-1, 2)


def suavizar_campo(v, ar, iters=4):
    """Promedia un campo por vértice con sus vecinos (iters pasadas)."""
    v = v.astype(np.float32)
    n = len(v)
    cnt = np.zeros(n, np.float32)
    np.add.at(cnt, ar[:, 0], 1); np.add.at(cnt, ar[:, 1], 1)
    cnt = np.maximum(cnt, 1)
    for _ in range(iters):
        acc = np.zeros_like(v)
        np.add.at(acc, ar[:, 0], v[ar[:, 1]]); np.add.at(acc, ar[:, 1], v[ar[:, 0]])
        v = 0.5 * v + 0.5 * acc / (cnt[:, None] if v.ndim > 1 else cnt)
    return v


def a_lo_largo(P, poly):
    """Distancia, posición relativa (0..1) y punto más cercano de cada punto P a una polilínea."""
    best_d = np.full(len(P), 1e9, np.float32); best_q = np.zeros_like(P); best_s = np.zeros(len(P), np.float32)
    seg = np.linalg.norm(poly[1:] - poly[:-1], axis=1); cum = np.concatenate([[0], np.cumsum(seg)])
    for i in range(len(poly) - 1):
        a = poly[i]; ab = poly[i + 1] - a
        t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1)
        q = a + t[:, None] * ab
        d = np.linalg.norm(P - q, axis=1)
        m = d < best_d
        best_d[m] = d[m]; best_q[m] = q[m]; best_s[m] = cum[i] + t[m] * seg[i]
    return best_d, best_s / cum[-1], best_q


def pesos_brazos(c, cl, CL, ar):
    """Para cada lado devuelve (peso de pertenencia al brazo, posición a lo largo, punto del eje)."""
    res = []
    for lado in (1.0, -1.0):
        poly = BRAZO.copy(); poly[:, 0] *= lado
        d, s, q = a_lo_largo(c, poly)
        ind = ((c[:, 0] * lado > 0.28) & (d < 0.20) & (c[:, 2] < 1.64)
               & np.isin(cl, [CL["piel"], CL["marron"], CL["otro"]])).astype(np.float32)
        w = np.clip(suavizar_campo(ind, ar, 5) * 1.6 - 0.2, 0, 1) * suave(1.62, 1.46, c[:, 2])
        res.append((w, s, q))
    return res


def deformar(base, me, cl, r):
    """Aplica la complexión de la receta `r` a la malla `me` (suelta, con origen a los pies)."""
    c = coords(me); ar = aristas(me); CL = base.CL
    # 1) brazos más finos (radial hacia el eje del brazo)
    brazos = pesos_brazos(c, cl, CL, ar)      # se calcula sobre la malla original: sirve luego para las mangas
    f_brazo = r.get("brazo", 1.0)
    if abs(f_brazo - 1.0) > 1e-3:
        for w, s, q in brazos:
            f = f_brazo + (1.0 - (1.0 - f_brazo) * 0.45 - f_brazo) * suave(0.80, 0.97, s)   # la mano adelgaza menos
            c = c + (w * (1.0 - f))[:, None] * (q - c)
    # 2) barba más corta / afeitada: se recoge hacia la mandíbula
    fb = r.get("barba_recoger", 0.0)
    if fb > 0:
        x_, y_, z_ = c[:, 0], c[:, 1], c[:, 2]
        zona = (np.abs(x_) < 0.2) & (y_ < 0.0) & (z_ > 1.52) & (z_ < 1.78) & ~((np.abs(x_) < 0.045) & (z_ > 1.715) & (y_ < -0.17))
        ind = (zona & ((cl == CL["marron"]) | (cl == CL["oscuro"]) | ((cl == CL["piel"]) & (z_ < 1.70)))).astype(np.float32)
        wb = np.clip(suavizar_campo(ind, ar, 3) * 1.5 - 0.15, 0, 1)
        # alisar los surcos de los mechones (más cuanto más se recoge la barba) y acortarla hacia la mandíbula
        cs = suavizar_campo(c, ar, int(4 + 22 * fb * fb))
        c = c + (wb * min(1.0, 0.45 + 0.6 * fb))[:, None] * (cs - c)
        piv = np.array([0.0, -0.01, 1.82], np.float32)
        esc = np.array([1.0, 1.0 - 0.30 * fb, 1.0 - 0.42 * fb], np.float32)
        c = c + wb[:, None] * ((piv + (c - piv) * esc) - c)
    # 3) anchura del tronco (hombros y pecho), sin tocar piernas ni cabeza
    k = r.get("ancho_tronco", 1.0)
    if abs(k - 1.0) > 1e-3:
        w = suave(0.95, 1.25, c[:, 2]) * (1 - suave(1.58, 1.70, c[:, 2]))
        c[:, 0] *= 1 - (1 - k) * w
        c[:, 1] *= 1 - (1 - r.get("fondo_tronco", k)) * w
    # 4) barriga
    bar = r.get("barriga", 0.0)
    if bar:
        g = np.exp(-((c[:, 0] / 0.30) ** 2 + ((c[:, 2] - 1.05) / 0.24) ** 2)) * suave(0.10, -0.10, c[:, 1])
        c[:, 1] -= bar * g
    # 5) cabeza mayor (niño): escala alrededor del cuello
    kc = r.get("cabeza", 1.0)
    if abs(kc - 1.0) > 1e-3:
        piv = np.array([0.0, -0.04, 1.54], np.float32)
        w = suave(1.50, 1.64, c[:, 2])[:, None]
        c = c + w * (kc - 1.0) * (c - piv)
    # 6) espalda encorvada (hacia −Y), con la cabeza algo adelantada
    th0 = math.radians(r.get("encorvar", 0.0))
    if th0:
        th = th0 * suave(1.10, 1.50, c[:, 2])
        y0, z0 = 0.0, 1.10
        dy = c[:, 1] - y0; dz = c[:, 2] - z0
        c[:, 1] = y0 + dy * np.cos(th) - dz * np.sin(th)
        c[:, 2] = z0 + dy * np.sin(th) + dz * np.cos(th)
    # 7) escala global no uniforme y pies al suelo
    sx, sy, sz = r.get("ancho", 1.0), r.get("fondo", 1.0), r.get("altura", 1.0)
    c *= np.array([sx, sy, sz], np.float32)
    c[:, 2] -= c[:, 2].min()
    poner_coords(me, c)
    return c, {"brazos": [(w, s) for w, s, q in brazos], "escala": (sx, sy, sz)}


# ================================================================ pintado de la textura
def lum(a):
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


def teñir(alb, w, color, contraste=0.8, claridad=1.0, kmax=1.4):
    """Cambia el color de la región `w` conservando el detalle de luminancia (estampado, manchas, arrugas)."""
    idx = w > 0.02
    if not idx.any():
        return
    px = alb[idx]
    L = lum(px)
    ref = np.percentile(L[w[idx] > 0.5], 80) if (w[idx] > 0.5).any() else np.percentile(L, 80)
    k = np.clip(1.0 + contraste * (L / max(ref, 1e-3) - 1.0), 0.12, kmax) * claridad
    nuevo = np.clip(np.asarray(color, np.float32)[None, :] * k[:, None], 0, 1)
    ww = w[idx][:, None]
    alb[idx] = px * (1 - ww) + nuevo * ww


def tintar(alb, w, mult, sat=1.0):
    """Multiplica el color de la región por `mult` (tono de piel) y ajusta la saturación."""
    idx = w > 0.02
    if not idx.any():
        return
    px = alb[idx]
    L = lum(px)[:, None]
    px2 = L + (px - L) * sat
    nuevo = np.clip(px2 * np.asarray(mult, np.float32)[None, :], 0, 1)
    ww = w[idx][:, None]
    alb[idx] = px * (1 - ww) + nuevo * ww


def ensuciar(alb, w, nivel, semilla, color=(0.10, 0.085, 0.07)):
    """Manchas de hollín/barro con ruido fractal, solo donde `w` lo permite."""
    if nivel <= 0:
        return
    n = ruido_fbm((RES, RES), 5, 6, semilla)
    a = (nivel * suave(0.42, 0.80, n) * w)[..., None]
    alb[:] = alb * (1 - 0.55 * a) + np.asarray(color, np.float32) * 0.25 * a


def pintar(base, r, nombre):
    """Devuelve (albedo RESxRESx3, rugosidad RESxRES) de la receta `r`."""
    t0 = time.time()
    alb = base.px.copy()
    M = base.m
    # --- piel (cuerpo y cara) y su tono de referencia para la barba afeitada
    teñir(alb, M["piel_cuerpo"], r["piel"], contraste=r.get("piel_contraste", 0.7), kmax=1.2)
    teñir(alb, M["piel_cara"], r["piel"], contraste=r.get("piel_contraste", 0.55), kmax=1.12)
    piel_nueva = np.asarray(r["piel"], np.float32) * 0.9
    # --- pelo y barba
    if r.get("afeitado"):
        w = M["pelo_todo"]
        idx = w > 0.02
        Ls = caja_blur(lum(alb) * w, 5) / np.maximum(caja_blur(w, 5), 1e-3)       # luminancia suave de la zona
        refL = np.median(Ls[w > 0.5])
        k = np.clip(1.0 + 0.7 * (Ls / refL - 1.0), 0.6, 1.4)[..., None]
        nuevo = np.clip(piel_nueva[None, None, :] * k * r.get("sombra_barba", 1.0), 0, 1)
        alb[idx] = alb[idx] * (1 - w[idx][:, None]) + nuevo[idx] * w[idx][:, None]
    else:
        teñir(alb, M["pelo"], r["pelo"], contraste=r.get("pelo_contraste", 0.9))
    if r.get("afeitado"):
        X_, Y_, Z_ = base.X, base.Y, base.Z
        labios = caja_blur(((np.abs(X_) < 0.042) & (np.abs(Z_ - 1.706) < 0.0085) & (Y_ < -0.15)).astype(np.float32), 1)[..., None]
        linea = caja_blur(((np.abs(X_) < 0.038) & (np.abs(Z_ - 1.7065) < 0.0030) & (Y_ < -0.15)).astype(np.float32), 1)[..., None]
        rojo_labio = np.clip(piel_nueva * np.array([0.92, 0.62, 0.62], np.float32), 0, 1)
        alb[:] = alb * (1 - labios * 0.85) + rojo_labio * labios * 0.85
        alb[:] = alb * (1 - linea * 0.7) + rojo_labio * 0.45 * linea * 0.7
    # --- ropa
    teñir(alb, M["camisa"], r["camisa"], contraste=r.get("camisa_contraste", 0.7))
    teñir(alb, M["babero"], r["babero"], contraste=r.get("babero_contraste", 0.8))
    teñir(alb, M["pantalon"], r["pantalon"], contraste=r.get("pantalon_contraste", 0.8))
    teñir(alb, M["botas"], r["botas"], contraste=0.9)
    teñir(alb, M["guante"], r.get("guante", r["botas"]), contraste=0.8)
    # --- suciedad
    if r.get("cara_sucia", 0) > 0:
        ensuciar(alb, M["piel_cara"], r["cara_sucia"], 31 + sum(map(ord, nombre)) % 500, color=(0.04, 0.035, 0.03))
    s = r.get("sucio", 0.0)
    if s > 0:
        tela = np.clip(M["camisa"] + M["babero"] + M["pantalon"] + M["botas"], 0, 1)
        ensuciar(alb, tela, s, sum(map(ord, nombre)) % 1000)
        zmanos = np.clip(M["piel_cuerpo"] * (0.35 + suave(1.1, 0.8, base.Z)), 0, 1)
        ensuciar(alb, zmanos, s * 0.6, 7 + sum(map(ord, nombre)) % 1000, color=(0.08, 0.07, 0.06))
    # --- rugosidad: piel semibrillante, cuero más lisa, tela mate
    rug = np.full((RES, RES), 0.80, np.float32)
    rug = rug * (1 - M["piel_cuerpo"]) + 0.52 * M["piel_cuerpo"]
    rug = rug * (1 - M["piel_cara"]) + 0.50 * M["piel_cara"]
    rug = rug * (1 - M["pelo"]) + 0.55 * M["pelo"]
    rug = rug * (1 - M["botas"]) + 0.58 * M["botas"]
    cuero = r.get("cuero_babero", False)
    rug = rug * (1 - M["babero"]) + (0.50 if cuero else 0.88) * M["babero"]
    rug = np.clip(rug + 0.18 * (lum(alb) - 0.35), 0.25, 0.95)
    log(f"  textura de {nombre} pintada ({time.time() - t0:.1f}s)")
    return alb, rug


def guardar_imagen(nombre, arr, no_color=False):
    """Guarda `arr` (RxRx3 o RxR) como JPEG en texturas_aldeanos, lo carga de nuevo y lo empaqueta en el .blend."""
    os.makedirs(DIR_TEX, exist_ok=True)
    h, w = arr.shape[:2]
    rgba = np.ones((h, w, 4), np.float32)
    rgba[..., :3] = arr[..., None] if arr.ndim == 2 else arr
    im = bpy.data.images.new("tmp_" + nombre, w, h, alpha=False)
    im.pixels.foreach_set(rgba.reshape(-1))
    ruta = os.path.join(DIR_TEX, nombre + ".jpg")
    im.filepath_raw = ruta; im.file_format = "JPEG"
    im.save()
    bpy.data.images.remove(im)
    im2 = bpy.data.images.load(ruta, check_existing=False)
    im2.name = nombre
    if no_color:
        im2.colorspace_settings.name = "Non-Color"
    im2.pack()
    return im2


# ================================================================ materiales
def lin(c):
    """sRGB (0..1) -> lineal: los colores de los materiales de Blender son lineales."""
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def _nodo(nt, tipo, **kw):
    n = nt.nodes.new(tipo)
    for k, v in kw.items():
        setattr(n, k, v)
    return n


def _salida_rgba(n):
    return [s for s in n.outputs if s.type == "RGBA" and s.enabled][0]


def _entradas_rgba(n):
    return [s for s in n.inputs if s.type == "RGBA" and s.enabled]


def _material_vacio(nombre):
    m = bpy.data.materials.new(nombre)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    return m, nt


def mat_cuerpo(nombre, alb, rug):
    m, nt = _material_vacio(nombre)
    sal = _nodo(nt, "ShaderNodeOutputMaterial"); bsdf = _nodo(nt, "ShaderNodeBsdfPrincipled")
    ta = _nodo(nt, "ShaderNodeTexImage", image=alb); tr = _nodo(nt, "ShaderNodeTexImage", image=rug)
    nt.links.new(ta.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    bsdf.inputs["Specular IOR Level"].default_value = 0.3
    nt.links.new(bsdf.outputs["BSDF"], sal.inputs["Surface"])
    return m


def mat_proc(nombre, color, rug=0.7, metal=0.0, tipo="tela", escala=1.0, var=0.25, bump=0.2, color2=None):
    """Material procedural sencillo: color con variación por ruido + relieve fino según el tipo."""
    m, nt = _material_vacio(nombre)
    sal = _nodo(nt, "ShaderNodeOutputMaterial"); bsdf = _nodo(nt, "ShaderNodeBsdfPrincipled")
    tc = _nodo(nt, "ShaderNodeTexCoord")
    c1 = (*lin(color), 1.0)
    c2 = (*lin(color2 if color2 else tuple(min(1.0, x * 0.55) for x in color)), 1.0)
    mp = _nodo(nt, "ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1, 1, 0.07) if tipo == "pelo" else (1, 1, 1)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nz = _nodo(nt, "ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = (90.0 if tipo == "pelo" else 14.0) / escala
    nz.inputs["Detail"].default_value = 6
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    mz = _nodo(nt, "ShaderNodeMix", data_type="RGBA")
    ins = _entradas_rgba(mz)
    ins[0].default_value = c1; ins[1].default_value = c2
    mt = _nodo(nt, "ShaderNodeMath", operation="MULTIPLY"); mt.inputs[1].default_value = var * 2.0
    nt.links.new(nz.outputs["Fac"], mt.inputs[0]); nt.links.new(mt.outputs[0], mz.inputs["Factor"])
    nt.links.new(_salida_rgba(mz), bsdf.inputs["Base Color"])
    esc_b = {"tela": 260.0, "cuero": 55.0, "pelo": 110.0, "madera": 40.0, "metal": 90.0}.get(tipo, 100.0) / escala
    n2 = _nodo(nt, "ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = esc_b; n2.inputs["Detail"].default_value = 8
    nt.links.new(mp.outputs["Vector"] if tipo == "pelo" else tc.outputs["Object"], n2.inputs["Vector"])
    bp = _nodo(nt, "ShaderNodeBump"); bp.inputs["Strength"].default_value = bump; bp.inputs["Distance"].default_value = 0.01
    nt.links.new(n2.outputs["Fac"], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = rug
    bsdf.inputs["Metallic"].default_value = metal
    nt.links.new(bsdf.outputs["BSDF"], sal.inputs["Surface"])
    return m


def mat_emisivo(nombre, color, fuerza):
    m, nt = _material_vacio(nombre)
    sal = _nodo(nt, "ShaderNodeOutputMaterial"); em = _nodo(nt, "ShaderNodeEmission")
    em.inputs["Color"].default_value = (*lin(color), 1.0); em.inputs["Strength"].default_value = fuerza
    nt.links.new(em.outputs["Emission"], sal.inputs["Surface"])
    return m


# ================================================================ piezas modeladas por script
def crear_warp(c0, c, k=10):
    """Devuelve warp(P): lleva puntos del espacio ORIGINAL del granjero al cuerpo ya deformado, interpolando el
    desplazamiento de los k vértices más cercanos. Sirve para colocar pelo, cinturones, herramientas..."""
    from mathutils.kdtree import KDTree
    kd = KDTree(len(c0))
    for i, p in enumerate(c0):
        kd.insert(Vector(p), i)
    kd.balance()
    d = (c - c0).astype(np.float32)

    def warp(P):
        P = np.asarray(P, np.float32).reshape(-1, 3)
        out = np.empty_like(P)
        for i, p in enumerate(P):
            res = kd.find_n(Vector(p), k)
            idx = np.array([r[1] for r in res]); dist = np.array([r[2] for r in res], np.float32)
            w = 1.0 / (dist + 0.012) ** 2
            out[i] = p + (d[idx] * w[:, None]).sum(0) / w.sum()
        return out
    return warp


def warp_bm(bm, warp):
    P = np.array([v.co[:] for v in bm.verts], np.float32)
    Q = warp(P)
    for v, q in zip(bm.verts, Q):
        v.co = Vector(q)


def m_trs(loc=(0, 0, 0), rot=(0, 0, 0), esc=(1, 1, 1)):
    return Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((esc[0], esc[1], esc[2], 1.0))


def esfera(bm, loc, radios, rot=(0, 0, 0), seg=24, anillos=14):
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=anillos, radius=1.0, matrix=m_trs(loc, rot, radios))


def caja(bm, loc, tam, rot=(0, 0, 0)):
    bmesh.ops.create_cube(bm, size=1.0, matrix=m_trs(loc, rot, tam))


def cilindro(bm, a, b, ra, rb=None, seg=16, tapas=True):
    """Cilindro o tronco de cono entre los puntos a y b."""
    a = Vector(a); b = Vector(b)
    d = b - a
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=tapas, cap_tris=False, segments=seg, radius1=ra, radius2=ra if rb is None else rb,
                          depth=d.length, matrix=Matrix.Translation((a + b) / 2) @ rot)


def toro(bm, centro, radio_mayor, radio_menor, rot=(0, 0, 0), seg_m=32, seg_n=8, esc=(1, 1, 1)):
    mt = m_trs(centro, rot, esc)
    filas = []
    for i in range(seg_m):
        t = 2 * math.pi * i / seg_m
        fila = []
        for j in range(seg_n):
            u = 2 * math.pi * j / seg_n
            r = radio_mayor + radio_menor * math.cos(u)
            fila.append(bm.verts.new(mt @ Vector((r * math.cos(t), r * math.sin(t), radio_menor * math.sin(u)))))
        filas.append(fila)
    for i in range(seg_m):
        for j in range(seg_n):
            bm.faces.new((filas[i][j], filas[(i + 1) % seg_m][j], filas[(i + 1) % seg_m][(j + 1) % seg_n], filas[i][(j + 1) % seg_n]))


def a_objeto(nombre, bm, mat, col, padre=None, liso=True):
    me = bpy.data.meshes.new(nombre)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(nombre, me)
    col.objects.link(ob)
    if mat is not None:
        me.materials.append(mat)
    if liso and len(me.polygons):
        me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    if padre is not None:
        ob.parent = padre
    return ob


def malla_de_arrays(nombre, P, F, mat, col, padre=None):
    me = bpy.data.meshes.new(nombre)
    me.from_pydata(np.asarray(P, np.float32).tolist(), [], np.asarray(F, np.int32).tolist())
    me.update()
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    ob = bpy.data.objects.new(nombre, me)
    col.objects.link(ob)
    if mat is not None:
        me.materials.append(mat)
    if padre is not None:
        ob.parent = padre
    return ob


def aplicar_modificador(ob, nombre):
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier=nombre)


# --- casquete elipsoidal: pelo, casco...
def filas_ult_fila(filas, n_v):
    return [f[n_v - 1] for f in filas]


def casquete(nombre, centro, rx, ry_frente, ry_atras, rz, borde, mat, col, padre=None, n_phi=160, n_v=26,
             grosor=0.012, ondas=(0.006, 40), ruido=0.006, flequillo=0.005, semilla=0, extra=None, warp=None):
    """Casquete que cubre la parte alta de la cabeza.
    borde: tabla [(grados desde el frente, z del borde)]. ondas: (amplitud, frecuencia) de los mechones.
    extra(bm): función opcional para añadir piezas (moño, ala...) al mismo objeto."""
    rng = np.random.default_rng(semilla)
    cx, cy, cz = centro
    ang = [math.radians(a) for a, _ in borde]; zs = [z for _, z in borde]
    fase = rng.random(8) * 6.28
    bm = bmesh.new()
    filas = []
    for i in range(n_phi):
        ph = 2 * math.pi * i / n_phi
        pa = abs(((ph + math.pi) % (2 * math.pi)) - math.pi)          # 0 = frente, π = nuca
        e = (1 + math.cos(ph)) / 2
        ry = ry_atras + (ry_frente - ry_atras) * e
        zb = float(np.interp(pa, ang, zs)) + flequillo * math.sin(17 * ph + fase[0]) * (0.3 + e) + flequillo * 0.25 * math.sin(29 * ph + fase[1])
        el0 = math.asin(max(-0.97, min(0.97, (zb - cz) / rz)))
        fila = []
        for j in range(n_v):
            u = j / n_v
            el = el0 + (math.pi / 2 - el0) * u
            s = 1.0 + ondas[0] * math.sin(ondas[1] * ph + 3 * u + fase[2]) * (1 - 0.6 * u) + ruido * math.sin(7 * ph + 5 * u + fase[3]) \
                + ruido * 0.7 * math.sin(13 * ph - 9 * u + fase[4])
            x = cx + rx * math.cos(el) * math.sin(ph) * s
            y = cy - ry * math.cos(el) * math.cos(ph) * s
            z = cz + rz * math.sin(el) * (1.0 + 0.5 * (s - 1))
            fila.append(bm.verts.new((x, y, z)))
        filas.append(fila)
    ult = np.array([v.co[:] for v in filas_ult_fila(filas, n_v)], np.float32).mean(0)
    polo = bm.verts.new(tuple(ult))
    for i in range(n_phi):
        k = (i + 1) % n_phi
        for j in range(n_v - 1):
            bm.faces.new((filas[i][j], filas[k][j], filas[k][j + 1], filas[i][j + 1]))
        bm.faces.new((filas[i][n_v - 1], filas[k][n_v - 1], polo))
    bm.normal_update(); bm.faces.ensure_lookup_table()
    # normales hacia fuera
    f0 = bm.faces[0]
    if (f0.calc_center_median() - Vector(centro)).dot(f0.normal) < 0:
        for f in bm.faces:
            f.normal_flip()
    if grosor > 0:
        bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=grosor)
    if extra:
        extra(bm)
    if warp:
        warp_bm(bm, warp)
    return a_objeto(nombre, bm, mat, col, padre)


# --- capa de tela que sigue al cuerpo (copia de sus triángulos desplazada a lo largo de la normal)
def capa_cuerpo(nombre, ctx, sel, grosor, mat, padre=None, suav_normales=3):
    """sel(cen0, tv) -> máscara de triángulos (cen0: centroides en el espacio ORIGINAL de la malla).
    grosor: escalar o función(índices de vértices) con el desplazamiento (m) por vértice."""
    me = ctx.me
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    tv = np.empty(nt * 3, np.int32); me.loop_triangles.foreach_get("vertices", tv); tv = tv.reshape(-1, 3)
    cen0 = ctx.c0[tv].mean(1)
    m = sel(cen0, tv)
    if m.sum() < 8:
        log("  AVISO: capa vacía", nombre)
        return None
    tsel = tv[m]
    usados = np.unique(tsel)
    mapa = np.full(len(ctx.c), -1, np.int32); mapa[usados] = np.arange(len(usados))
    F = mapa[tsel]
    nrm = np.empty(len(ctx.c) * 3, np.float32); me.vertex_normals.foreach_get("vector", nrm); nrm = nrm.reshape(-1, 3)[usados]
    ar = np.unique(np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1), axis=0)
    nrm = suavizar_campo(nrm, ar, suav_normales)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
    g = grosor(usados) if callable(grosor) else grosor
    g = np.asarray(g, np.float32)
    g = g[:, None] if g.ndim else g
    P = ctx.c[usados] + nrm * g
    P = suavizar_campo(P, ar, 4) * 0.8 + P * 0.2
    return malla_de_arrays(nombre, P, F, mat, ctx.col, padre)


# --- lámina que se ajusta al cuerpo con Shrinkwrap (delantales, toallas...)
def lamina_ajustada(nombre, ctx, z_sup, z_inf, w_sup, w_inf, y0, offset, mat, nx=28, nz=22, grosor=0.006,
                    cx=0.0, suav=6, padre=None, curva=None):
    bm = bmesh.new()
    filas = []
    for j in range(nz + 1):
        t = j / nz
        z = z_sup + (z_inf - z_sup) * t
        w = w_sup + (w_inf - w_sup) * t
        fila = []
        for i in range(nx + 1):
            fila.append(bm.verts.new((cx + (i / nx - 0.5) * w, y0, z)))
        filas.append(fila)
    for j in range(nz):
        for i in range(nx):
            bm.faces.new((filas[j][i], filas[j][i + 1], filas[j + 1][i + 1], filas[j + 1][i]))
    ob = a_objeto(nombre, bm, mat, ctx.col, padre)
    mod = ob.modifiers.new("ajuste", "SHRINKWRAP")
    mod.target = ctx.ob; mod.wrap_method = "PROJECT"; mod.wrap_mode = "ON_SURFACE"
    mod.use_project_x = False; mod.use_project_y = True; mod.use_project_z = False
    mod.use_negative_direction = False; mod.use_positive_direction = True; mod.cull_face = "OFF"
    mod.offset = offset
    aplicar_modificador(ob, "ajuste")
    # Los vértices cuyo rayo no tocó nada se quedan en y0: se les da la profundidad del vecino más cercano de su fila.
    P = coords(ob.data).reshape(nz + 1, nx + 1, 3)
    fallo = np.abs(P[:, :, 1] - y0) < 1e-3
    if fallo.any():
        for j in range(nz + 1):
            ok = np.nonzero(~fallo[j])[0]
            if len(ok) == 0:
                P[j, :, 1] = P[j - 1, :, 1] if j > 0 else P[j + 1, :, 1]
                continue
            for i in np.nonzero(fallo[j])[0]:
                P[j, i, 1] = P[j, ok[np.argmin(np.abs(ok - i))], 1]
        poner_coords(ob.data, P.reshape(-1, 3))
    if suav:
        sm = ob.modifiers.new("suave", "SMOOTH"); sm.factor = 0.8; sm.iterations = suav
        aplicar_modificador(ob, "suave")
    if grosor:
        so = ob.modifiers.new("grosor", "SOLIDIFY"); so.thickness = grosor; so.offset = 1.0
        aplicar_modificador(ob, "grosor")
    return ob


# --- falda: anillos concéntricos con vuelo y ondulación
def falda(nombre, z_cintura, z_bajo, r_cintura, r_bajo, mat, col, padre=None, centro=(0, 0), ondas=14, amp=0.018,
          n_phi=64, n_z=14, borde_mat=None):
    bm = bmesh.new()
    filas = []
    for j in range(n_z + 1):
        t = j / n_z
        z = z_cintura + (z_bajo - z_cintura) * t
        rx = r_cintura[0] + (r_bajo[0] - r_cintura[0]) * (t ** 0.8)
        ry = r_cintura[1] + (r_bajo[1] - r_cintura[1]) * (t ** 0.8)
        fila = []
        for i in range(n_phi):
            ph = 2 * math.pi * i / n_phi
            o = 1.0 + amp * t * math.sin(ondas * ph + 2.0 * t) + 0.01 * math.sin(5 * ph + 3 * t)
            fila.append(bm.verts.new((centro[0] + rx * o * math.cos(ph), centro[1] + ry * o * math.sin(ph), z)))
        filas.append(fila)
    for j in range(n_z):
        for i in range(n_phi):
            k = (i + 1) % n_phi
            f = bm.faces.new((filas[j][i], filas[j][k], filas[j + 1][k], filas[j + 1][i]))
            if borde_mat is not None and j >= n_z - 2:
                f.material_index = 1
    bm.normal_update(); bm.faces.ensure_lookup_table()
    f0 = bm.faces[0]
    if (f0.calc_center_median() - Vector((centro[0], centro[1], f0.calc_center_median().z))).dot(f0.normal) < 0:
        for f in bm.faces:
            f.normal_flip()
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=0.006)
    ob = a_objeto(nombre, bm, mat, col, padre)
    if borde_mat is not None:
        ob.data.materials.append(borde_mat)
    return ob


def extension(ctx, zlo, zhi):
    """Caja (xmin,xmax,ymin,ymax) del cuerpo deformado entre dos alturas, sin contar los brazos."""
    m = (ctx.c[:, 2] >= zlo) & (ctx.c[:, 2] <= zhi) & (np.abs(ctx.c0[:, 0]) < 0.40)
    p = ctx.c[m]
    return p[:, 0].min(), p[:, 0].max(), p[:, 1].min(), p[:, 1].max()


# ================================================================ cada aldeano
class Ctx:
    """Todo lo que necesitan las piezas de un aldeano: su cuerpo, la deformación y dónde colgar las cosas."""
    pass


def preparar(base, clave, r, col):
    ctx = Ctx()
    ctx.clave, ctx.r, ctx.col = clave, r, col
    raiz = bpy.data.objects.new(f"Aldeano_{clave}_raiz", None)
    raiz.empty_display_type = "ARROWS"; raiz.empty_display_size = 0.35
    col.objects.link(raiz)
    ctx.raiz = raiz
    me = base.ob.data.copy(); me.name = f"{clave}_cuerpo"
    ob = bpy.data.objects.new(f"{clave}_cuerpo", me)
    col.objects.link(ob); ob.parent = raiz
    ctx.ob, ctx.me = ob, me
    ctx.c0 = coords(me).copy()
    ctx.cl = clase_de_vertices(base, me)
    ctx.CL = base.CL
    ctx.c, ctx.info = deformar(base, me, ctx.cl, r)
    ctx.warp = crear_warp(ctx.c0, ctx.c)
    alb, rug = pintar(base, r, clave)
    ia = guardar_imagen(f"{clave}_albedo", alb)
    ir = guardar_imagen(f"{clave}_rugosidad", rug, no_color=True)
    me.materials.clear()
    me.materials.append(mat_cuerpo(f"{clave}_piel_y_ropa", ia, ir))
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    me.update()
    return ctx


def zw(ctx, z0, x0=0.0, y0=-0.2):
    """Altura deformada de una altura z0 del granjero original."""
    return float(ctx.warp([[x0, y0, z0]])[0][2])


def pw(ctx, p0):
    return Vector(ctx.warp([p0])[0])


def mat_pelo(nombre, color, color2=None, var=0.35):
    return mat_proc(nombre, color, rug=0.55, tipo="pelo", color2=color2 or tuple(x * 0.45 for x in color), var=var, bump=0.45)


# ---------------------------------------------------------------- pelo
ESTILOS_PELO = {
    # borde = [(grados desde el frente, z del borde)] en el espacio original del granjero.
    # La cabeza del protagonista mide unos 0,23 m de ancho y su abertura superior está a z ≈ 1,82 m.
    "corto": dict(borde=[(0, 1.862), (55, 1.832), (90, 1.795), (125, 1.750), (180, 1.700)], rx=0.148, ryf=0.158, ryt=0.178, rz=0.170, ondas=(0.008, 56), ruido=0.005),
    "recogido": dict(borde=[(0, 1.866), (60, 1.830), (95, 1.785), (130, 1.735), (180, 1.680)], rx=0.150, ryf=0.158, ryt=0.182, rz=0.172, ondas=(0.007, 44), ruido=0.004),
    "canoso": dict(borde=[(0, 1.858), (60, 1.815), (95, 1.770), (130, 1.730), (180, 1.690)], rx=0.146, ryf=0.156, ryt=0.176, rz=0.168, ondas=(0.008, 50), ruido=0.007),
    "rizado": dict(borde=[(0, 1.866), (55, 1.838), (90, 1.800), (125, 1.755), (180, 1.710)], rx=0.156, ryf=0.164, ryt=0.184, rz=0.178, ondas=(0.011, 34), ruido=0.011),
}


def hacer_pelo(ctx, estilo, mat, extra=None, nombre="pelo", **ov):
    p = dict(ESTILOS_PELO[estilo]); p.update(ov)
    return casquete(f"{ctx.clave}_{nombre}", (0.0, -0.05, 1.775), p["rx"], p["ryf"], p["ryt"], p["rz"], p["borde"], mat, ctx.col,
                    padre=ctx.raiz, ondas=p["ondas"], ruido=p["ruido"], semilla=sum(map(ord, ctx.clave)), extra=extra, warp=ctx.warp)


# ---------------------------------------------------------------- selección de trozos del cuerpo
def sel_manga(ctx, s0, s1, wmin=0.45):
    def f(cen0, tv):
        out = np.zeros(len(tv), bool)
        for (w, s) in ctx.info["brazos"]:
            out |= (w[tv].mean(1) > wmin) & (s[tv].mean(1) >= s0) & (s[tv].mean(1) <= s1)
        return out
    return f


def grosor_manga(ctx, s_puno, g, g_puno):
    wl, sl = ctx.info["brazos"][0]; wr, sr = ctx.info["brazos"][1]
    sv = np.where(wl > wr, sl, sr)

    def f(idx):
        return g + (g_puno - g) * suave(s_puno, s_puno + 0.025, sv[idx])
    return f


def sel_banda(ctx, zlo, zhi, xmax=0.335):
    """Anillo de tronco entre dos alturas originales (cinturón, bufanda...). Excluye piel de los brazos."""
    def f(cen0, tv):
        x, y, z = cen0.T
        return (z >= zlo) & (z <= zhi) & (np.abs(x) < xmax)
    return f


def frente_en(ctx, x0, z0, rad=0.04):
    """y del punto más adelantado (−Y) del cuerpo original cerca de (x0, z0)."""
    m = (np.abs(ctx.c0[:, 0] - x0) < rad) & (np.abs(ctx.c0[:, 2] - z0) < rad) & (ctx.c0[:, 1] < 0.1)
    return float(ctx.c0[m, 1].min()) if m.any() else -0.25


def objetivo_temporal(ctx, extras=()):
    """Objeto oculto con el cuerpo y otras mallas juntas, para que el Shrinkwrap de un delantal las vea todas."""
    bm = bmesh.new()
    bm.from_mesh(ctx.me)
    for e in extras:
        bm.from_mesh(e.data)
    # relleno entre las piernas (las ranuras dejarían pasar los rayos y el delantal saldría disparado hacia delante)
    sx, sy, sz = ctx.info["escala"]
    z0, z1 = zw(ctx, 0.28), zw(ctx, 0.74)
    cy0 = float(ctx.warp([[0.0, 0.0, 0.5]])[0][1])
    bmesh.ops.create_cube(bm, size=1.0, matrix=m_trs((0.0, cy0, (z0 + z1) / 2), (0, 0, 0), (0.17 * sx, 0.20 * sy, z1 - z0)))
    me = bpy.data.meshes.new("tmp_objetivo"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("tmp_objetivo", me); ctx.col.objects.link(ob)
    return ob


def limpiar_objetivo(ob):
    me = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)


def cilindro_eliptico(bm, a, b, rx, ry, seg=24, tapas=False, r2=1.0):
    a = Vector(a); b = Vector(b)
    d = b - a
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=tapas, cap_tris=False, segments=seg, radius1=1.0, radius2=r2, depth=d.length,
                          matrix=Matrix.Translation((a + b) / 2) @ rot @ Matrix.Diagonal((rx, ry, 1.0, 1.0)))


def pieza_en(bm, M):
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)


# ---------------------------------------------------------------- HERRERO
def construir_herrero(ctx):
    sx, sy, sz = ctx.info["escala"]
    cuero = mat_proc("Herrero_cuero", (0.22, 0.125, 0.07), rug=0.5, tipo="cuero", color2=(0.09, 0.05, 0.03), var=0.55, bump=0.55)
    madera = mat_proc("Herrero_madera", (0.30, 0.17, 0.08), rug=0.6, tipo="madera", color2=(0.12, 0.06, 0.03), var=0.7, bump=0.3)
    acero = mat_proc("Herrero_acero", (0.20, 0.20, 0.21), rug=0.4, metal=1.0, tipo="metal", color2=(0.06, 0.06, 0.06), var=0.6, bump=0.15)
    # delantal de cuero que cuelga del babero hasta las rodillas
    tmp = objetivo_temporal(ctx)
    ctx_t = Ctx(); ctx_t.__dict__.update(ctx.__dict__); ctx_t.ob = tmp
    lamina_ajustada("Herrero_delantal", ctx_t, zw(ctx, 1.07), zw(ctx, 0.50), 0.50 * sx, 0.54 * sx, -0.8, 0.014, cuero, padre=ctx.raiz, grosor=0.01)
    limpiar_objetivo(tmp)
    # muñequeras
    bm = bmesh.new()
    for lado in (1, -1):
        a = pw(ctx, (0.600 * lado, 0.070, 1.045)); b = pw(ctx, (0.612 * lado, 0.020, 0.905))
        cilindro_eliptico(bm, a, b, 0.108 * sx, 0.132 * sy, r2=0.93)
    a_objeto("Herrero_munequeras", bm, cuero, ctx.col, ctx.raiz)
    # martillo en la mano derecha (el lado +X de la pantalla)
    hp = pw(ctx, (0.623, 0.017, 0.82))
    bm = bmesh.new()
    cilindro(bm, hp + Vector((0, 0, 0.09)), hp + Vector((0, 0, -0.44)), 0.021, seg=12)
    a_objeto("Herrero_martillo_mango", bm, madera, ctx.col, ctx.raiz)
    bm = bmesh.new()
    caja(bm, hp + Vector((0, 0, -0.46)), (0.085, 0.24, 0.085))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.008, segments=2, affect="EDGES")
    a_objeto("Herrero_martillo_cabeza", bm, acero, ctx.col, ctx.raiz)
    # pelo muy corto y negro
    hacer_pelo(ctx, "corto", mat_pelo("Herrero_pelo", (0.07, 0.055, 0.045), (0.02, 0.016, 0.012), 0.6))


# ---------------------------------------------------------------- TABERNERO
def construir_tabernero(ctx):
    sx, sy, sz = ctx.info["escala"]
    lino = mat_proc("Tabernero_lino", (0.86, 0.82, 0.70), rug=0.9, tipo="tela", color2=(0.62, 0.58, 0.47), var=0.5, bump=0.25)
    delantal_m = mat_proc("Tabernero_delantal", (0.88, 0.85, 0.76), rug=0.92, tipo="tela", color2=(0.60, 0.55, 0.44), var=0.5, bump=0.25)
    paño_m = mat_proc("Tabernero_pano", (0.55, 0.62, 0.70), rug=0.9, tipo="tela", color2=(0.30, 0.36, 0.45), var=0.6, bump=0.2)
    madera = mat_proc("Tabernero_jarra", (0.38, 0.21, 0.09), rug=0.55, tipo="madera", color2=(0.17, 0.08, 0.03), var=0.7, bump=0.25)
    laton = mat_proc("Tabernero_laton", (0.62, 0.42, 0.14), rug=0.35, metal=1.0, tipo="metal", color2=(0.3, 0.2, 0.06), var=0.5, bump=0.1)
    espuma = mat_proc("Tabernero_espuma", (0.95, 0.93, 0.85), rug=0.8, tipo="tela", var=0.2, bump=0.1)
    # mangas remangadas: hasta el codo, con el puño doblado más grueso
    capa_cuerpo("Tabernero_mangas", ctx, sel_manga(ctx, 0.0, 0.50), grosor_manga(ctx, 0.44, 0.016, 0.034), lino, padre=ctx.raiz)
    # delantal largo de cintura
    tmp = objetivo_temporal(ctx)
    ctx_t = Ctx(); ctx_t.__dict__.update(ctx.__dict__); ctx_t.ob = tmp
    lamina_ajustada("Tabernero_delantal", ctx_t, zw(ctx, 1.04), zw(ctx, 0.48), 0.54 * sx, 0.58 * sx, -0.8, 0.02, delantal_m, padre=ctx.raiz, grosor=0.006)
    limpiar_objetivo(tmp)
    # paño al hombro
    def sel_pano(cen0, tv):
        x, y, z = cen0.T
        return (x > 0.13) & (x < 0.28) & (z > 1.27) & (z < 1.64)
    capa_cuerpo("Tabernero_pano", ctx, sel_pano, 0.024, paño_m, padre=ctx.raiz)
    # jarra de madera en la mano izquierda (lado −X)
    hp = pw(ctx, (-0.622, 0.015, 0.82))
    c = hp + Vector((-0.01, -0.095, 0.09))
    bm = bmesh.new()
    cilindro(bm, c - Vector((0, 0, 0.07)), c + Vector((0, 0, 0.07)), 0.058, 0.066, seg=24)
    toro(bm, c + Vector((0, 0, -0.035)), 0.064, 0.0055, seg_m=28, seg_n=6)
    toro(bm, c + Vector((0, 0, 0.040)), 0.067, 0.0055, seg_m=28, seg_n=6)
    toro(bm, c + Vector((0.070, 0, 0.0)), 0.035, 0.009, rot=(math.pi / 2, 0, 0), seg_m=20, seg_n=6, esc=(1, 1.3, 1))
    a_objeto("Tabernero_jarra", bm, madera, ctx.col, ctx.raiz)
    bm = bmesh.new()
    esfera(bm, c + Vector((0, 0, 0.074)), (0.058, 0.058, 0.026), seg=20, anillos=8)
    a_objeto("Tabernero_espuma", bm, espuma, ctx.col, ctx.raiz)
    # pelo corto pelirrojo
    hacer_pelo(ctx, "corto", mat_pelo("Tabernero_pelo", (0.42, 0.18, 0.06), (0.18, 0.06, 0.02), 0.45), ry_dummy=None) if False else \
        hacer_pelo(ctx, "corto", mat_pelo("Tabernero_pelo", (0.42, 0.18, 0.06), (0.18, 0.06, 0.02), 0.45))


# ---------------------------------------------------------------- ALCALDE
def construir_alcalde(ctx):
    sx, sy, sz = ctx.info["escala"]
    lana = mat_proc("Alcalde_chaleco", (0.30, 0.055, 0.075), rug=0.85, tipo="tela", color2=(0.12, 0.02, 0.03), var=0.55, bump=0.35, escala=0.7)
    camisa = mat_proc("Alcalde_camisa", (0.86, 0.84, 0.78), rug=0.9, tipo="tela", color2=(0.62, 0.60, 0.55), var=0.4, bump=0.25)
    oro = mat_proc("Alcalde_oro", (0.85, 0.62, 0.20), rug=0.28, metal=1.0, tipo="metal", color2=(0.5, 0.33, 0.08), var=0.3, bump=0.08)
    cinta = mat_proc("Alcalde_cinta", (0.10, 0.22, 0.45), rug=0.6, tipo="tela", color2=(0.04, 0.09, 0.2), var=0.4, bump=0.2)
    madera = mat_proc("Alcalde_baston", (0.20, 0.10, 0.045), rug=0.4, tipo="madera", color2=(0.07, 0.03, 0.015), var=0.7, bump=0.2)
    # mangas largas de camisa con puño
    capa_cuerpo("Alcalde_mangas", ctx, sel_manga(ctx, 0.0, 0.70), grosor_manga(ctx, 0.66, 0.014, 0.024), camisa, padre=ctx.raiz)

    # chaleco: tronco entero menos el escote en V, con las sisas estrechas
    def sel_chaleco(cen0, tv):
        x, y, z = cen0.T
        ax = np.abs(x)
        lim = 0.335 - 0.45 * np.maximum(0.0, z - 1.32)
        v = (y < 0.05) & (ax < 0.13 * np.clip((z - 1.16) / 0.30, 0, 1) + 0.012)
        cuello = (ax < 0.085) & (z > 1.45)
        no_piel = (ctx.cl[tv] != ctx.CL["piel"]).sum(1) >= 2
        return (z > 1.0) & (z < 1.52) & (ax < lim) & ~v & ~cuello & no_piel
    capa_cuerpo("Alcalde_chaleco", ctx, sel_chaleco, 0.024, lana, padre=ctx.raiz)
    # botones y medalla con cinta
    bm = bmesh.new()
    for z0 in (1.040, 1.095, 1.150):
        y0 = frente_en(ctx, 0.0, z0) - 0.030
        esfera(bm, pw(ctx, (0.0, y0, z0)), (0.0115, 0.008, 0.0115), seg=12, anillos=8)
    a_objeto("Alcalde_botones", bm, oro, ctx.col, ctx.raiz)
    zm = 1.385
    ym = frente_en(ctx, 0.14, zm) - 0.040
    cm = pw(ctx, (0.14, ym, zm))
    bm = bmesh.new()
    cilindro(bm, cm + Vector((0, 0.006, 0)), cm + Vector((0, -0.010, 0)), 0.036 * sx, seg=28)
    a_objeto("Alcalde_medalla", bm, oro, ctx.col, ctx.raiz)
    bm = bmesh.new()
    cilindro(bm, cm + Vector((0, 0.004, 0)), cm + Vector((0, -0.014, 0)), 0.018 * sx, 0.018 * sx, seg=20)
    a_objeto("Alcalde_medalla_centro", bm, cinta, ctx.col, ctx.raiz)
    # bastón en la mano derecha (+X) con empuñadura curva y puntera de latón
    hp = pw(ctx, (0.623, 0.017, 0.82))
    base_p = Vector((hp.x + 0.012, hp.y - 0.04, 0.0)); top = Vector((hp.x, hp.y - 0.02, hp.z + 0.22))
    bm = bmesh.new()
    cilindro(bm, base_p, top, 0.0155, 0.0135, seg=14)
    # empuñadura: arco de 180° en el plano XZ (se ve bien de frente)
    centro = top + Vector((-0.045, 0, 0))
    for i in range(10):
        t0 = math.radians(0 + 18 * i); t1 = math.radians(0 + 18 * (i + 1))
        p0 = centro + Vector((0.045 * math.cos(t0), 0, 0.045 * math.sin(t0)))
        p1 = centro + Vector((0.045 * math.cos(t1), 0, 0.045 * math.sin(t1)))
        cilindro(bm, p0, p1, 0.0135, seg=10, tapas=False)
    a_objeto("Alcalde_baston", bm, madera, ctx.col, ctx.raiz)
    bm = bmesh.new()
    esfera(bm, centro + Vector((-0.045, 0, 0.0)), (0.022, 0.022, 0.022), seg=16, anillos=10)
    cilindro(bm, base_p, base_p + Vector((0, 0, 0.035)), 0.0185, seg=14)
    a_objeto("Alcalde_baston_latón", bm, oro, ctx.col, ctx.raiz)
    # pelo canoso
    hacer_pelo(ctx, "canoso", mat_pelo("Alcalde_pelo", (0.80, 0.80, 0.78), (0.45, 0.45, 0.44), 0.5))


# ---------------------------------------------------------------- MINERO
def construir_minero(ctx):
    sx, sy, sz = ctx.info["escala"]
    lona = mat_proc("Minero_manga", (0.30, 0.26, 0.20), rug=0.95, tipo="tela", color2=(0.07, 0.06, 0.045), var=0.7, bump=0.3)
    cuero = mat_proc("Minero_cuero", (0.11, 0.07, 0.045), rug=0.55, tipo="cuero", color2=(0.04, 0.025, 0.015), var=0.5, bump=0.5)
    casco_m = mat_proc("Minero_casco", (0.62, 0.45, 0.07), rug=0.5, metal=0.4, tipo="metal", color2=(0.20, 0.13, 0.03), var=0.8, bump=0.25)
    laton = mat_proc("Minero_laton", (0.55, 0.38, 0.12), rug=0.4, metal=1.0, tipo="metal", color2=(0.2, 0.13, 0.04), var=0.6, bump=0.15)
    acero = mat_proc("Minero_acero", (0.24, 0.24, 0.25), rug=0.42, metal=1.0, tipo="metal", color2=(0.07, 0.07, 0.07), var=0.7, bump=0.2)
    madera = mat_proc("Minero_mango", (0.26, 0.14, 0.07), rug=0.65, tipo="madera", color2=(0.1, 0.05, 0.025), var=0.7, bump=0.3)
    luz = mat_emisivo("Minero_luz", (1.0, 0.78, 0.38), 14.0)
    # mangas largas sucias y cinturón de cuero
    capa_cuerpo("Minero_mangas", ctx, sel_manga(ctx, 0.0, 0.70), grosor_manga(ctx, 0.66, 0.015, 0.026), lona, padre=ctx.raiz)
    capa_cuerpo("Minero_cinturon", ctx, sel_banda(ctx, 1.02, 1.09), 0.024, cuero, padre=ctx.raiz)
    bm = bmesh.new()
    y0 = frente_en(ctx, 0.0, 1.055) - 0.032
    caja(bm, pw(ctx, (0.0, y0, 1.055)), (0.06 * sx, 0.012, 0.05))
    a_objeto("Minero_hebilla", bm, laton, ctx.col, ctx.raiz)

    # casco: casquete con ala, cresta y lámpara de carburo
    def extra_casco(bm):
        toro(bm, (0.0, -0.05, 1.862), 0.178, 0.011, seg_m=48, seg_n=8, esc=(1.0, 1.08, 0.55))
        cilindro(bm, (0.0, -0.13, 1.935), (0.0, 0.12, 1.958), 0.011, 0.011, seg=10)          # cresta
        cilindro(bm, (0.0, -0.150, 1.925), (0.0, -0.200, 1.925), 0.030, 0.030, seg=20)       # soporte de la lámpara
        cilindro(bm, (0.0, -0.200, 1.925), (0.0, -0.236, 1.925), 0.030, 0.050, seg=20, tapas=False)   # reflector
    hacer_pelo(ctx, "corto", casco_m, extra=extra_casco, nombre="casco", borde=[(0, 1.858), (55, 1.846), (90, 1.826), (125, 1.80), (180, 1.77)],
               rx=0.172, ryf=0.180, ryt=0.200, rz=0.190, ondas=(0.0, 1), ruido=0.002)
    bm = bmesh.new()
    cilindro(bm, pw(ctx, (0.0, -0.2345, 1.925)), pw(ctx, (0.0, -0.2385, 1.925)), 0.034, seg=24)
    a_objeto("Minero_lampara_luz", bm, luz, ctx.col, ctx.raiz)

    # pico apoyado en la mano derecha (+X), inclinado hacia delante
    hp = pw(ctx, (0.623, 0.017, 0.82))
    d = Vector((0.07, -0.22, 1.0)).normalized()
    abajo = hp - d * (hp.z / d.z)
    arriba = hp + d * 0.50
    bm = bmesh.new()
    cilindro(bm, abajo, arriba, 0.021, 0.019, seg=14)
    a_objeto("Minero_pico_mango", bm, madera, ctx.col, ctx.raiz)
    # cabeza del pico: barra curva con las dos puntas afiladas, perpendicular al mango (eje X mundial)
    bm = bmesh.new()
    n = 12
    puntos = []
    for i in range(n + 1):
        t = -1 + 2 * i / n
        puntos.append(Vector((0.21 * t, 0.0, -0.045 * t * t)))
    for i in range(n):
        r0 = 0.024 * (1 - abs(-1 + 2 * i / n) ** 2.2) + 0.004
        r1 = 0.024 * (1 - abs(-1 + 2 * (i + 1) / n) ** 2.2) + 0.004
        cilindro(bm, puntos[i], puntos[i + 1], r0, r1, seg=10, tapas=False)
    caja(bm, Vector((0, 0, 0)), (0.05, 0.05, 0.07))
    z_ax = d
    x_ax = Vector((1, 0, 0)); x_ax = (x_ax - z_ax * x_ax.dot(z_ax)).normalized()
    y_ax = z_ax.cross(x_ax)
    M = Matrix(((x_ax.x, y_ax.x, z_ax.x, arriba.x), (x_ax.y, y_ax.y, z_ax.y, arriba.y), (x_ax.z, y_ax.z, z_ax.z, arriba.z), (0, 0, 0, 1)))
    pieza_en(bm, M)
    a_objeto("Minero_pico_cabeza", bm, acero, ctx.col, ctx.raiz)


# ---------------------------------------------------------------- TENDERA
def construir_tendera(ctx):
    sx, sy, sz = ctx.info["escala"]
    falda_m = mat_proc("Tendera_falda", (0.50, 0.20, 0.11), rug=0.9, tipo="tela", color2=(0.27, 0.09, 0.05), var=0.55, bump=0.3)
    borde_m = mat_proc("Tendera_dobladillo", (0.22, 0.08, 0.05), rug=0.9, tipo="tela", var=0.3, bump=0.3)
    delantal_m = mat_proc("Tendera_delantal", (0.90, 0.84, 0.70), rug=0.92, tipo="tela", color2=(0.65, 0.58, 0.44), var=0.45, bump=0.25)
    chal_m = mat_proc("Tendera_chal", (0.46, 0.12, 0.10), rug=0.95, tipo="tela", color2=(0.22, 0.05, 0.05), var=0.65, bump=0.4, escala=0.6)
    # falda larga hasta media pantorrilla (mide el cuerpo ya deformado)
    z_c, z_b = zw(ctx, 1.06), zw(ctx, 0.36)
    xa, xb, ya, yb = extension(ctx, z_b, z_c)
    wxa, wxb, wya, wyb = extension(ctx, z_c - 0.12, z_c)
    cx_ = 0.0; cy_ = (ya + yb) / 2
    half_x = max(abs(xa), abs(xb)); half_y = (yb - ya) / 2
    f = falda("Tendera_falda", z_c, z_b, (max(abs(wxa), abs(wxb)) + 0.03, (wyb - wya) / 2 + 0.03), (half_x + 0.13, half_y + 0.11), falda_m, ctx.col,
              padre=ctx.raiz, centro=(cx_, cy_), borde_mat=borde_m)
    # delantal sobre la falda
    tmp = objetivo_temporal(ctx, [f])
    ctx_t = Ctx(); ctx_t.__dict__.update(ctx.__dict__); ctx_t.ob = tmp
    lamina_ajustada("Tendera_delantal", ctx_t, zw(ctx, 1.045), z_b + 0.07, 0.48 * sx, 0.56 * sx, -0.9, 0.018, delantal_m, padre=ctx.raiz, grosor=0.006, suav=8)
    limpiar_objetivo(tmp)

    # chal: sobre hombros y espalda, termina en pico por delante
    def sel_chal(cen0, tv):
        x, y, z = cen0.T
        ax = np.abs(x)
        hem = np.where(y < 0, 1.13 + 0.50 * ax, 1.06 + 0.55 * ax)
        lim_z = np.where(ax < 0.2, 1.53, 1.60)
        lim_x = np.where(z < 1.44, 0.335, 0.43)
        no_cuello = ~((ax < 0.095) & (z > 1.44))
        return (z > hem) & (z < lim_z) & (ax < lim_x) & no_cuello
    capa_cuerpo("Tendera_chal", ctx, sel_chal, 0.026, chal_m, padre=ctx.raiz)

    # pelo recogido con moño
    def extra_mono(bm):
        esfera(bm, (0.0, 0.175, 1.835), (0.062, 0.058, 0.055), seg=20, anillos=12)
        toro(bm, (0.0, 0.17, 1.835), 0.052, 0.014, rot=(math.pi / 2, 0.4, 0), seg_m=28, seg_n=8)
    hacer_pelo(ctx, "recogido", mat_pelo("Tendera_pelo", (0.30, 0.19, 0.12), (0.55, 0.52, 0.50), 0.28), extra=extra_mono)


# ---------------------------------------------------------------- NIÑO
def construir_nino(ctx):
    sx, sy, sz = ctx.info["escala"]
    bufanda = mat_proc("Nino_bufanda", (0.75, 0.62, 0.20), rug=0.95, tipo="tela", color2=(0.40, 0.30, 0.08), var=0.6, bump=0.4, escala=0.5)
    # bufanda de lana alrededor del cuello
    capa_cuerpo("Nino_bufanda", ctx, sel_banda(ctx, 1.50, 1.60, xmax=0.2), 0.022, bufanda, padre=ctx.raiz)
    # pelo alborotado
    hacer_pelo(ctx, "rizado", mat_pelo("Nino_pelo", (0.50, 0.33, 0.16), (0.30, 0.17, 0.07), 0.5))


# ---------------------------------------------------------------- recetas
ALDEANOS = {
    "Herrero": dict(
        construir=construir_herrero,
        altura=0.935, ancho=1.02, fondo=1.06, brazo=1.0, ancho_tronco=1.0, barriga=0.04, barba_recoger=0.55,
        piel=(0.72, 0.49, 0.37), pelo=(0.07, 0.05, 0.04), camisa=(0.27, 0.23, 0.20), camisa_contraste=0.55,
        babero=(0.20, 0.115, 0.065), babero_contraste=0.75, cuero_babero=True, pantalon=(0.27, 0.27, 0.29),
        botas=(0.13, 0.09, 0.065), guante=(0.20, 0.12, 0.07), sucio=0.5),
    "Tendera": dict(
        construir=construir_tendera,
        altura=0.865, ancho=0.80, fondo=0.82, brazo=0.55, ancho_tronco=0.88, cabeza=1.0,
        afeitado=True, barba_recoger=1.0, sombra_barba=0.97,
        piel=(0.90, 0.70, 0.60), pelo=(0.3, 0.2, 0.13), camisa=(0.86, 0.78, 0.62), camisa_contraste=0.5,
        babero=(0.52, 0.21, 0.12), pantalon=(0.50, 0.20, 0.11), botas=(0.17, 0.115, 0.085), sucio=0.12),
    "Tabernero": dict(
        construir=construir_tabernero,
        altura=0.905, ancho=1.0, fondo=1.13, brazo=0.78, ancho_tronco=0.96, barriga=0.10, barba_recoger=0.0,
        piel=(0.86, 0.60, 0.50), pelo=(0.44, 0.19, 0.065), pelo_contraste=1.0, camisa=(0.88, 0.83, 0.70), camisa_contraste=0.4,
        babero=(0.30, 0.19, 0.11), pantalon=(0.20, 0.155, 0.12), botas=(0.11, 0.075, 0.055), sucio=0.12),
    "Alcalde": dict(
        construir=construir_alcalde,
        altura=0.885, ancho=0.92, fondo=1.0, brazo=0.64, ancho_tronco=0.90, barriga=0.07, encorvar=7.0, barba_recoger=0.25,
        piel=(0.88, 0.72, 0.64), pelo=(0.82, 0.82, 0.80), pelo_contraste=0.55, camisa=(0.86, 0.84, 0.78), camisa_contraste=0.4,
        babero=(0.30, 0.055, 0.075), pantalon=(0.15, 0.15, 0.17), botas=(0.09, 0.07, 0.06), sucio=0.0),
    "Minero": dict(
        construir=construir_minero,
        altura=0.925, ancho=0.97, fondo=1.0, brazo=0.86, ancho_tronco=0.95, barba_recoger=0.5,
        piel=(0.62, 0.46, 0.38), pelo=(0.06, 0.05, 0.045), camisa=(0.31, 0.27, 0.21), camisa_contraste=0.6,
        babero=(0.26, 0.22, 0.17), pantalon=(0.22, 0.19, 0.15), botas=(0.11, 0.085, 0.065), sucio=0.75, cara_sucia=0.55),
    "Nino": dict(
        construir=construir_nino,
        altura=0.63, ancho=0.70, fondo=0.72, brazo=0.55, ancho_tronco=0.78, cabeza=1.32,
        afeitado=True, barba_recoger=1.0, sombra_barba=0.97,
        piel=(0.92, 0.74, 0.64), pelo=(0.5, 0.33, 0.16), camisa=(0.62, 0.30, 0.18), camisa_contraste=0.6,
        babero=(0.50, 0.40, 0.24), pantalon=(0.40, 0.32, 0.22), botas=(0.25, 0.17, 0.11), sucio=0.22),
}


# ================================================================ escenario de estudio y render
def configurar_gpu(sc):
    sc.render.engine = "CYCLES"
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        for tipo in ("OPTIX", "CUDA"):
            try:
                pr.compute_device_type = tipo; pr.get_devices()
                usadas = [d for d in pr.devices if d.type == tipo]
                if usadas:
                    for d in pr.devices:
                        d.use = d.type == tipo
                    sc.cycles.device = "GPU"
                    log("GPU:", tipo, [d.name for d in usadas])
                    return
            except Exception as ex:
                log("sin", tipo, ex)
    except Exception as ex:
        log("GPU no disponible:", ex)


def cargar_protagonista():
    with bpy.data.libraries.load(PROTAGONISTA, link=False) as (src, dst):
        dst.objects = ["GEO-Farmer_Ultra"]
    ob = dst.objects[0]
    ob.name = "Protagonista"
    bpy.context.scene.collection.objects.link(ob)
    ob.hide_viewport = False; ob.hide_render = False
    return ob


def ciclorama():
    """Fondo de estudio gris neutro: suelo que se curva hasta una pared, sin horizonte."""
    bm = bmesh.new()
    perfil = [(-40.0, 0.0), (6.0, 0.0)]
    R = 4.0
    for i in range(1, 13):
        a = math.pi / 2 * i / 12
        perfil.append((6.0 + R * math.sin(a), R - R * math.cos(a)))
    perfil.append((10.0, 18.0))
    filas = []
    for (y, z) in perfil:
        filas.append([bm.verts.new((-30.0, y, z)), bm.verts.new((30.0, y, z))])
    for i in range(len(filas) - 1):
        bm.faces.new((filas[i][0], filas[i][1], filas[i + 1][1], filas[i + 1][0]))
    m = bpy.data.materials.new("Estudio_gris"); m.use_nodes = True
    bsdf = [n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
    bsdf.inputs["Base Color"].default_value = (0.11, 0.11, 0.11, 1)
    bsdf.inputs["Roughness"].default_value = 0.9
    me = bpy.data.meshes.new("Estudio"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("Estudio", me); bpy.context.scene.collection.objects.link(ob)
    me.materials.append(m)
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    return ob


def luz_area(nombre, pos, objetivo, energia, tam, color=(1, 1, 1)):
    d = bpy.data.lights.new(nombre, "AREA"); d.energy = energia; d.size = tam; d.color = color
    o = bpy.data.objects.new(nombre, d); bpy.context.scene.collection.objects.link(o)
    o.location = pos
    o.rotation_euler = (Vector(objetivo) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
    return o


def montar_estudio(cx, ancho_fila, calidad):
    sc = bpy.context.scene
    ciclorama()
    w = bpy.data.worlds.new("Estudio"); sc.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    bg = [n for n in w.node_tree.nodes if n.type == "BACKGROUND"][0]
    bg.inputs["Color"].default_value = (0.12, 0.12, 0.12, 1); bg.inputs["Strength"].default_value = 0.4
    obj = (cx, 0, 1.0)
    luz_area("Luz_principal", (cx - 7, -10, 8), obj, 1700, 6.0, (1.0, 0.94, 0.86))
    luz_area("Luz_relleno", (cx + 9, -9, 4), obj, 520, 6.0, (0.82, 0.88, 1.0))
    luz_area("Luz_contra", (cx + 1, 8, 7), obj, 1100, 5.0, (1.0, 0.95, 0.88))
    luz_area("Luz_cenital", (cx, -2, 10), obj, 800, 9.0, (1.0, 1.0, 1.0))
    cd = bpy.data.cameras.new("Camara_estudio"); cd.lens = 85; cd.sensor_width = 36; cd.clip_end = 200
    dist = (ancho_fila / 2 + 0.25) / math.tan(math.atan(18.0 / 85.0))
    cam = bpy.data.objects.new("Camara_estudio", cd); sc.collection.objects.link(cam)
    cam.location = (cx, -dist, 1.25)
    cam.rotation_euler = (Vector((cx, 0, 0.98)) - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    configurar_gpu(sc)
    final = calidad == "final"
    sc.render.resolution_x, sc.render.resolution_y = (1280, 720) if final else (960, 540)
    sc.cycles.samples = 256 if final else 48
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 8
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    sc.render.image_settings.file_format = "PNG"


def vistas_de_revision(construidos, carpeta):
    """Opcional (ALDEA_CERCA=carpeta): una vista de cuerpo entero y otra de la cabeza de cada aldeano, para revisarlos."""
    sc = bpy.context.scene
    os.makedirs(carpeta, exist_ok=True)
    cam = sc.camera
    sc.cycles.samples = 32
    for clave, ctx in construidos.items():
        x0 = ctx.raiz.location.x
        h = float(ctx.c[:, 2].max()) + 0.12
        for nombre, objetivo, dist, res, lente, giro in (("cuerpo", (x0, 0, h * 0.5), 5.2, (640, 800), 50, 28),
                                                         ("cabeza", (x0, -0.03, h - 0.14), 2.4, (700, 700), 85, 20),
                                                         ("atras", (x0, 0, h * 0.5), 5.2, (640, 800), 50, 180)):
            cam.data.lens = lente
            a = math.radians(giro)
            cam.location = (objetivo[0] + dist * math.sin(a), objetivo[1] - dist * math.cos(a), objetivo[2] + 0.15)
            cam.rotation_euler = (Vector(objetivo) - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
            sc.render.resolution_x, sc.render.resolution_y = res
            sc.render.filepath = os.path.join(carpeta, f"{clave}_{nombre}.png")
            bpy.ops.render.render(write_still=True)


# ================================================================ programa principal
def objetos_de(col):
    return [o for o in col.objects if o.type == "MESH"]


def ancho_de(col):
    xs = []
    for o in objetos_de(col):
        if len(o.data.vertices):                       # todavía están en el origen: coordenadas locales = mundo
            P = coords(o.data)
            xs.append((float(P[:, 0].min()), float(P[:, 0].max())))
    return min(a for a, b in xs), max(b for a, b in xs)


def main():
    base = cargar_base()
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"; sc.unit_settings.scale_length = 1.0
    quiero = [s for s in os.environ.get("ALDEANOS", "").split(",") if s]
    orden = ["Herrero", "Tabernero", "Minero", "Alcalde", "Tendera", "Nino"]
    construidos = {}
    for clave in orden:
        if quiero and clave.lower() not in [q.lower() for q in quiero]:
            continue
        r = ALDEANOS[clave]
        log("=== construyendo", clave)
        col = bpy.data.collections.new(f"Aldeano_{clave}")
        sc.collection.children.link(col)
        ctx = preparar(base, clave, r, col)
        r["construir"](ctx)
        construidos[clave] = ctx
        log(f"    {clave}: {len(col.objects)} objetos, altura del cuerpo {ctx.c[:, 2].max():.3f} m")
    # El granjero original no se queda en el archivo: solo las colecciones de los aldeanos.
    bpy.data.objects.remove(base.ob, do_unlink=True)
    bpy.data.images.remove(base.imagen_original)
    # Fila: protagonista (a la izquierda) y los aldeanos, de mayor a menor
    x = 0.0
    anchos = {}
    for clave, ctx in construidos.items():
        a, b = ancho_de(ctx.col)
        anchos[clave] = (a, b)
    x_prot_w = 1.45
    cursor = x_prot_w / 2
    x_prot = 0.0
    posiciones = {}
    for clave in construidos:
        a, b = anchos[clave]
        cursor += 0.22 + (-a)
        posiciones[clave] = cursor
        cursor += b
    for clave, ctx in construidos.items():
        ctx.raiz.location = (posiciones[clave], 0.0, 0.0)
        ctx.col.instance_offset = (posiciones[clave], 0.0, 0.0)
    ancho_total = cursor + x_prot_w / 2
    cx = (cursor - x_prot_w / 2) / 2
    # Guardar el .blend (sin protagonista ni estudio)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for d in list(blk):
            if d.users == 0:
                blk.remove(d)
    bpy.ops.wm.save_as_mainfile(filepath=SALIDA_BLEND, compress=True)
    log("GUARDADO", SALIDA_BLEND, f"({os.path.getsize(SALIDA_BLEND) / 1e6:.1f} MB)")
    if os.environ.get("RENDER", "1") == "0":
        return
    # Escena de render: protagonista + aldeanos sobre fondo gris, luz de estudio
    prot = cargar_protagonista()
    prot.location.x = x_prot
    montar_estudio(cx, ancho_total, CALIDAD)
    os.makedirs(DIR_RENDER, exist_ok=True)
    revision = os.environ.get("ALDEA_CERCA")
    if revision:
        vistas_de_revision(construidos, revision)
        return
    sc.render.filepath = os.path.join(DIR_RENDER, f"aldeanos_{CALIDAD}.png")
    t = time.time()
    bpy.ops.render.render(write_still=True)
    log(f"RENDER {CALIDAD} LISTO en {time.time() - t:.0f}s ->", sc.render.filepath)


if os.environ.get("ALDEA_SIN_MAIN") != "1":
    main()
