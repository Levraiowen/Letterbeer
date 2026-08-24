"""
LETTERBEER — génère les icônes PNG de l'app à partir de la géométrie du logo.

    python make-icons.py

Produit icon-192.png et icon-512.png pour le manifeste et l'écran d'accueil
iOS. Le SVG (logo.svg) reste la source pour le favicon ; ce script redessine
la même forme, parce qu'iOS n'accepte pas de SVG en apple-touch-icon.
"""

from PIL import Image, ImageDraw

BG     = (10, 10, 12, 255)      # --bg
CREAM  = (244, 239, 232, 255)   # --text
DARK   = (20, 20, 23, 255)      # corps de la canette
ORANGE = (255, 90, 31, 255)     # --accent

SS = 4  # suréchantillonnage, pour un anticrénelage propre


def cubic(p0, p1, p2, p3, n=28):
    """Échantillonne une courbe de Bézier cubique en n points."""
    pts = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u*u*t * p1[0] + 3 * u*t*t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u*u*t * p1[1] + 3 * u*t*t * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def can_outline():
    """La silhouette de la canette, dans le même repère 100x100 que le SVG."""
    pts = [(36, 14), (64, 14), (64, 19)]
    pts += cubic((64, 19), (68.5, 21), (70, 24), (70, 28))
    pts.append((70, 79))
    pts += cubic((70, 79), (70, 83.5), (67, 87), (63, 87))
    pts.append((37, 87))
    pts += cubic((37, 87), (33, 87), (30, 83.5), (30, 79))
    pts.append((30, 28))
    pts += cubic((30, 28), (30, 24), (31.5, 21), (36, 19))
    return pts


def render(size):
    W = size * SS
    k = W / 100.0                      # facteur d'échelle vers le repère du SVG
    s = lambda v: v * k

    img = Image.new("RGBA", (W, W), BG)
    d = ImageDraw.Draw(img)

    # pastille crème — r=44 et non 48 : on garde une marge pour que rien
    # ne soit rogné quand Android applique son masque rond ou arrondi.
    d.ellipse([s(6), s(6), s(94), s(94)], fill=CREAM)

    # le corps, peint à plat puis découpé à la forme de la canette
    body = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rectangle([s(26), s(12), s(74), s(55)], fill=DARK)
    bd.rectangle([s(26), s(55), s(74), s(89)], fill=ORANGE)

    # reflet et couture par-dessus : ImageDraw écrase les pixels au lieu de
    # les mélanger, donc un aplat semi-transparent trouerait la canette.
    # On les peint sur un calque à part que l'on compose ensuite.
    over = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    od.rectangle([s(33), s(12), s(40), s(89)], fill=(244, 239, 232, 38))       # reflet
    od.rectangle([s(26), s(19.4), s(74), s(21.1)], fill=(244, 239, 232, 235))  # couture
    body = Image.alpha_composite(body, over)

    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon([(s(x), s(y)) for x, y in can_outline()], fill=255)
    img.paste(body, (0, 0), mask)

    # la note : quatre points pleins, un vide
    for cx in (39, 44.5, 50, 55.5):
        d.ellipse([s(cx - 2.15), s(67 - 2.15), s(cx + 2.15), s(67 + 2.15)], fill=CREAM)
    d.ellipse([s(61 - 1.75), s(67 - 1.75), s(61 + 1.75), s(67 + 1.75)],
              outline=(244, 239, 232, 204), width=max(1, int(s(1.15))))

    return img.resize((size, size), Image.LANCZOS)


for n in (192, 512):
    render(n).save(f"icon-{n}.png")
    print(f"icon-{n}.png")
