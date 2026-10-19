"""Рисует фоновые иллюстрации тем приложения «Мой цикл».

Все рисунки оригинальные, собраны из простых фигур. Рисуем с
увеличением SS и уменьшаем — так получается сглаживание.
Запуск: python draw_themes.py <папка_вывода>
"""
import math
import random
import sys
from PIL import Image, ImageDraw

W, H = 1200, 1050          # итоговый размер
SS = 3                     # суперсэмплинг


def hexc(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


class Layer:
    """Отдельный слой под один элемент: рисуем, поворачиваем, вставляем."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def s(self, v):
        return v * SS

    def ellipse(self, cx, cy, rx, ry, fill):
        s = self.s
        self.d.ellipse([s(cx - rx), s(cy - ry), s(cx + rx), s(cy + ry)], fill=fill)

    def circle(self, cx, cy, r, fill):
        self.ellipse(cx, cy, r, r, fill)

    def poly(self, pts, fill):
        self.d.polygon([(self.s(x), self.s(y)) for x, y in pts], fill=fill)

    def line(self, pts, width, fill):
        p = [(self.s(x), self.s(y)) for x, y in pts]
        self.d.line(p, fill=fill, width=int(self.s(width)), joint='curve')
        r = width / 2
        for x, y in (pts[0], pts[-1]):
            self.circle(x, y, r * 0.98, fill)

    def rrect(self, x0, y0, x1, y1, r, fill):
        s = self.s
        self.d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s(r), fill=fill)

    def arc(self, cx, cy, r, a0, a1, width, fill):
        pts = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
               for a in frange(a0, a1, 24)]
        self.line(pts, width, fill)

    def done(self, angle=0, scale=1.0):
        im = self.im.resize((max(1, int(self.w * scale)), max(1, int(self.h * scale))), Image.LANCZOS)
        if angle:
            im = im.rotate(angle, resample=Image.BICUBIC, expand=True)
        return im


def frange(a, b, n):
    return [a + (b - a) * i / n for i in range(n + 1)]


def bez(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        out.append((x, y))
    return out


class Canvas:
    def __init__(self):
        self.im = Image.new('RGBA', (W, H), (0, 0, 0, 0))

    def put(self, layer_img, cx, cy):
        x = int(cx - layer_img.width / 2)
        y = int(cy - layer_img.height / 2)
        self.im.alpha_composite(layer_img, (x, y)) if 0 <= x and 0 <= y and \
            x + layer_img.width <= W and y + layer_img.height <= H else self._paste_clip(layer_img, x, y)

    def _paste_clip(self, li, x, y):
        tmp = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        tmp.paste(li, (x, y), li)
        self.im.alpha_composite(tmp)

    def save(self, path):
        self.im.save(path, optimize=True)


# ---------------------------------------------------------------- котики

def face(L, cx, cy, r, dark, closed=True):
    """Мордочка: глаза-дуги, носик, усы."""
    w = max(2.2, r * 0.07)
    if closed:
        L.arc(cx - r * 0.38, cy + r * 0.02, r * 0.17, 20, 160, w, dark)
        L.arc(cx + r * 0.38, cy + r * 0.02, r * 0.17, 20, 160, w, dark)
    else:
        L.circle(cx - r * 0.36, cy + r * 0.05, r * 0.09, dark)
        L.circle(cx + r * 0.36, cy + r * 0.05, r * 0.09, dark)
    L.poly([(cx - r * 0.1, cy + r * 0.28), (cx + r * 0.1, cy + r * 0.28), (cx, cy + r * 0.4)], dark)
    for sgn in (-1, 1):
        for dy in (-0.04, 0.1):
            L.line([(cx + sgn * r * 0.55, cy + r * (0.32 + dy)),
                    (cx + sgn * r * 1.15, cy + r * (0.24 + dy * 1.8))], w * 0.55, dark)


def ears(L, cx, cy, r, col, inner):
    for sgn in (-1, 1):
        base1 = (cx + sgn * r * 0.15, cy - r * 0.75)
        base2 = (cx + sgn * r * 0.95, cy - r * 0.2)
        tip = (cx + sgn * r * 0.88, cy - r * 1.18)
        L.poly([base1, tip, base2], col)
        if inner:
            L.poly([(cx + sgn * r * 0.38, cy - r * 0.68), (cx + sgn * r * 0.82, cy - r * 1.0),
                    (cx + sgn * r * 0.82, cy - r * 0.42)], inner)


def sitting_cat(col, belly, dark, stripes=None, size=1.0):
    L = Layer(260, 300)
    cx = 130
    # хвост
    L.line(bez((175, 268), (250, 262), (250, 180), (222, 140)), 20, col)
    # тело
    L.ellipse(cx, 200, 78, 92, col)
    L.ellipse(cx, 222, 44, 62, belly)
    # лапки
    L.ellipse(cx - 30, 284, 24, 14, col)
    L.ellipse(cx + 30, 284, 24, 14, col)
    # голова
    ears(L, cx, 98, 62, col, belly)
    L.ellipse(cx, 98, 66, 58, col)
    if stripes:
        for dx in (-14, 0, 14):
            L.line([(cx + dx, 44), (cx + dx * 1.3, 62)], 6, stripes)
        for dy in (170, 196, 222):
            L.line([(cx - 76, dy), (cx - 52, dy + 6)], 7, stripes)
            L.line([(cx + 76, dy), (cx + 52, dy + 6)], 7, stripes)
    face(L, cx, 98, 58, dark)
    return L, size


def sleeping_cat(col, belly, dark, size=1.0):
    L = Layer(320, 200)
    # тело калачиком
    L.ellipse(170, 120, 130, 70, col)
    L.ellipse(185, 140, 90, 38, belly)
    # хвост вокруг
    L.line(bez((290, 140), (300, 200), (120, 205), (60, 170)), 22, col)
    # голова
    ears(L, 82, 98, 52, col, belly)
    L.ellipse(82, 100, 56, 48, col)
    face(L, 82, 100, 48, dark)
    return L, size


def loaf_cat(col, belly, dark, stripes=None, size=1.0):
    L = Layer(330, 190)
    L.rrect(60, 70, 300, 175, 52, col)
    # хвост вверх
    L.line(bez((290, 120), (340, 90), (320, 30), (300, 20)), 18, col)
    # лапки
    L.ellipse(110, 172, 28, 14, belly)
    L.ellipse(170, 172, 28, 14, belly)
    if stripes:
        for x in (190, 220, 250):
            L.line([(x, 72), (x - 8, 104)], 9, stripes)
    ears(L, 92, 78, 56, col, belly)
    L.ellipse(92, 80, 60, 52, col)
    face(L, 92, 80, 52, dark, closed=False)
    return L, size


def peeking_cat(col, belly, dark, size=1.0):
    """Мордочка, выглядывающая снизу (обрезана нижней кромкой слоя)."""
    L = Layer(200, 150)
    ears(L, 100, 110, 70, col, belly)
    L.ellipse(100, 115, 76, 66, col)
    face(L, 100, 108, 64, dark, closed=False)
    # лапки на краю
    L.ellipse(50, 148, 26, 16, col)
    L.ellipse(150, 148, 26, 16, col)
    return L, size


def yarn(col, line_col, size=1.0):
    L = Layer(170, 150)
    L.circle(70, 70, 56, col)
    for a in (-35, 0, 35):
        L.arc(70 + a * 0.6, 70, 52, 200, 340, 4, line_col)
    L.arc(70, 70, 40, 100, 250, 4, line_col)
    L.line(bez((118, 92), (150, 110), (130, 140), (165, 145)), 4.5, col)
    return L, size


def fishbone(col, size=1.0):
    L = Layer(240, 110)
    L.line([(40, 55), (180, 55)], 6, col)
    for x in range(60, 170, 22):
        L.line([(x, 55), (x + 12, 25)], 5, col)
        L.line([(x, 55), (x + 12, 85)], 5, col)
    # голова
    L.poly([(180, 30), (232, 55), (180, 80)], col)
    L.circle(205, 52, 4.5, (0, 0, 0, 0))
    # хвост
    L.poly([(40, 55), (12, 28), (20, 55), (12, 82)], col)
    return L, size


def paw(col, size=1.0):
    L = Layer(80, 80)
    L.ellipse(40, 50, 18, 15, col)
    for dx, dy in ((-20, 26), (-7, 16), (7, 16), (20, 26)):
        L.ellipse(40 + dx, dy + 8, 7, 9, col)
    return L, size


def sprig(col, size=1.0, n=5):
    L = Layer(120, 230)
    stem = bez((60, 225), (55, 160), (68, 90), (58, 12))
    L.line(stem, 4, col)
    for i in range(n):
        t = 0.15 + i * 0.75 / max(1, n - 1)
        x, y = stem[int(t * (len(stem) - 1))]
        for sgn in (-1, 1):
            leaf = Layer(70, 34)
            leaf.ellipse(35, 17, 32, 13, col)
            li = leaf.im.rotate(sgn * 35 + 10, resample=Image.BICUBIC, expand=True)
            lx = int(x * SS + sgn * 28 * SS - li.width / 2)
            ly = int(y * SS - li.height / 2)
            tmp = Image.new('RGBA', L.im.size, (0, 0, 0, 0))
            tmp.paste(li, (lx, ly), li)
            L.im.alpha_composite(tmp)
    return L, size


def dots_scatter(c, col, n, rng, area, rmin=3, rmax=6):
    x0, y0, x1, y1 = area
    for _ in range(n):
        L = Layer(20, 20)
        L.circle(10, 10, rng.uniform(rmin, rmax) / 2, col)
        c.put(L.done(), rng.uniform(x0, x1), rng.uniform(y0, y1))


def dashes(c, col, n, rng, area):
    x0, y0, x1, y1 = area
    for _ in range(n):
        L = Layer(30, 30)
        L.line([(8, 15), (22, 15)], 5, col)
        c.put(L.done(angle=rng.uniform(0, 180)), rng.uniform(x0, x1), rng.uniform(y0, y1))


def place(c, made, cx, cy, angle=0):
    L, size = made
    c.put(L.done(angle=angle, scale=size), cx, cy)


def theme_cats(out):
    rng = random.Random(7)
    c = Canvas()
    tan, tan_l = hexc('#C99A6B'), hexc('#E2C29E')
    grey, grey_l = hexc('#9A9AA2'), hexc('#C4C4CA')
    navy = hexc('#3C4A78')
    ink = hexc('#2B2B30')
    teal = hexc('#3E6B66')
    stripe = hexc('#8C6340')
    dashes(c, teal, 40, rng, (0, 0, W, H))
    dots_scatter(c, hexc('#5A6A9A'), 40, rng, (0, 0, W, H))
    place(c, sprig(navy, 1.0), 1080, 560, -25)
    place(c, sprig(navy, 0.8), 70, 40, 160)
    place(c, sprig(hexc('#4F7F78'), 0.9), 640, 980, 80)
    place(c, sitting_cat(grey, grey_l, ink, size=1.15), 330, 150, 6)
    place(c, sleeping_cat(tan, tan_l, ink, size=1.05), 170, 470, -8)
    place(c, loaf_cat(grey, grey_l, ink, size=1.0), 230, 770, -12)
    place(c, sitting_cat(tan, tan_l, ink, stripes=stripe, size=1.0), 1020, 330, -4)
    place(c, peeking_cat(grey, grey_l, ink, size=1.0), 860, 940, 0)
    place(c, loaf_cat(tan, tan_l, ink, stripes=stripe, size=0.85), 980, 760, -160)
    place(c, yarn(navy, hexc('#2A3558'), 0.9), 560, 70, 0)
    place(c, yarn(hexc('#B5677A'), hexc('#8A4A5A'), 0.75), 60, 650, 30)
    place(c, fishbone(grey_l, 0.9), 860, 90, 70)
    place(c, fishbone(grey_l, 0.8), 80, 950, -20)
    place(c, paw(hexc('#5A6A9A'), 0.8), 700, 230, 20)
    place(c, paw(hexc('#5A6A9A'), 0.7), 470, 900, -30)
    c.save(f'{out}/cats.png')


# ---------------------------------------------------------------- ночь

def star5(col, r, size=1.0):
    L = Layer(int(r * 2.4), int(r * 2.4))
    cx = cy = r * 1.2
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    L.poly(pts, col)
    return L, size


def sparkle(col, r, size=1.0):
    L = Layer(int(r * 2.4), int(r * 2.4))
    cx = cy = r * 1.2
    pts = []
    for i in range(8):
        a = -math.pi / 2 + i * math.pi / 4
        rr = r if i % 2 == 0 else r * 0.22
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    L.poly(pts, col)
    return L, size


def moon(col, bg_cut, size=1.0):
    L = Layer(200, 200)
    L.circle(100, 100, 80, col)
    # вырез — рисуем «прозрачным» кругом
    L.d.ellipse([L.s(135 - 70), L.s(70 - 70), L.s(135 + 70), L.s(70 + 70)], fill=(0, 0, 0, 0))
    return L, size


def cloud(col, size=1.0):
    L = Layer(260, 140)
    L.rrect(20, 70, 240, 125, 28, col)
    L.circle(85, 72, 46, col)
    L.circle(150, 58, 58, col)
    L.circle(205, 85, 36, col)
    return L, size


def rainbow(cols, size=1.0):
    L = Layer(240, 140)
    r = 105
    for i, col in enumerate(cols):
        L.arc(120, 128, r - i * 20, 180, 360, 14, col)
    return L, size


def heart(col, size=1.0):
    L = Layer(80, 74)
    L.circle(26, 26, 20, col)
    L.circle(54, 26, 20, col)
    L.poly([(8, 34), (72, 34), (40, 70)], col)
    return L, size


def theme_night(out):
    rng = random.Random(11)
    c = Canvas()
    gold, pink, lav = hexc('#F1D29A'), hexc('#E9A6B8'), hexc('#B7A8E6')
    cloud_c = hexc('#D9D6E4')
    for _ in range(26):
        r = rng.uniform(12, 24)
        place(c, star5(rng.choice([gold, pink, lav]), r), rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0, 70))
    for _ in range(22):
        place(c, sparkle(rng.choice([gold, cloud_c]), rng.uniform(10, 20)), rng.uniform(0, W), rng.uniform(0, H))
    dots_scatter(c, hexc('#8C86B8'), 60, rng, (0, 0, W, H), 3, 7)
    place(c, moon(gold, None, 1.5), 1020, 190, -20)
    place(c, cloud(cloud_c, 1.5), 210, 150, 0)
    place(c, cloud(cloud_c, 1.2), 1040, 720, 0)
    place(c, cloud(cloud_c, 1.1), 130, 840, 0)
    place(c, cloud(cloud_c, 0.8), 640, 60, 0)
    place(c, rainbow([pink, gold, lav], 1.4), 140, 500, -8)
    place(c, rainbow([lav, pink, gold], 1.2), 1080, 470, 10)
    place(c, rainbow([gold, pink, lav], 1.1), 620, 990, 0)
    for x, y in ((420, 90), (860, 920), (330, 960), (780, 130), (60, 300), (1150, 980)):
        place(c, heart(pink, 0.9), x, y, rng.uniform(-20, 20))
    c.save(f'{out}/night.png')


# ---------------------------------------------------------------- цветы

def flower(petal, center, n=5, r=48, size=1.0):
    L = Layer(int(r * 3), int(r * 3))
    cx = cy = r * 1.5
    for i in range(n):
        a = i * 360 / n
        pl = Layer(int(r * 1.6), int(r * 0.9))
        pl.ellipse(r * 0.8, r * 0.45, r * 0.62, r * 0.36, petal)
        pi = pl.im.rotate(a, resample=Image.BICUBIC, expand=True)
        dx = math.cos(math.radians(a)) * r * 0.62
        dy = -math.sin(math.radians(a)) * r * 0.62
        tmp = Image.new('RGBA', L.im.size, (0, 0, 0, 0))
        tmp.paste(pi, (int((cx + dx) * SS - pi.width / 2), int((cy + dy) * SS - pi.height / 2)), pi)
        L.im.alpha_composite(tmp)
    L.circle(cx, cy, r * 0.3, center)
    return L, size


def tulip(petal, stem, size=1.0):
    L = Layer(120, 240)
    L.line(bez((60, 235), (58, 180), (64, 130), (60, 95)), 6, stem)
    leaf = [(60, 200), (20, 150), (30, 120), (60, 170)]
    L.poly(leaf, stem)
    L.ellipse(60, 70, 36, 42, petal)
    L.poly([(24, 60), (36, 22), (48, 50), (60, 18), (72, 50), (84, 22), (96, 60)], petal)
    return L, size


def theme_flowers(out):
    rng = random.Random(5)
    c = Canvas()
    pinks = [hexc('#E58FA7'), hexc('#F2A08A'), hexc('#C8A2E8'), hexc('#F6C1CF')]
    centers = [hexc('#F4D27A'), hexc('#E9B864')]
    green, green2 = hexc('#6E9C7E'), hexc('#8DB79A')
    dots_scatter(c, hexc('#F6C1CF', 160), 50, rng, (0, 0, W, H), 4, 8)
    for x, y, a in ((70, 120, 150), (1120, 520, -30), (600, 1000, 90), (120, 640, 200), (1100, 980, -60)):
        place(c, sprig(rng.choice([green, green2]), 0.9), x, y, a)
    spots = [(250, 130, 2.3), (950, 120, 2.0), (80, 400, 1.8), (1120, 360, 2.2), (190, 880, 2.2),
             (1010, 850, 2.3), (440, 1000, 1.6), (790, 990, 1.5), (560, 50, 1.4), (740, 40, 1.2),
             (60, 640, 1.3), (1150, 620, 1.4), (380, 230, 1.0), (840, 250, 1.0)]
    for x, y, sz in spots:
        place(c, flower(rng.choice(pinks), rng.choice(centers), n=rng.choice([5, 6, 8]), size=sz), x, y,
              rng.uniform(0, 60))
    place(c, tulip(pinks[0], green, 1.4), 1150, 760, 15)
    place(c, tulip(pinks[2], green, 1.4), 40, 520, -12)
    place(c, tulip(pinks[3], green, 1.2), 640, 990, 5)
    c.save(f'{out}/flowers.png')


# ---------------------------------------------------------------- листья

def branch(col, berry, size=1.0, n=7):
    L = Layer(160, 340)
    stem = bez((80, 335), (60, 240), (100, 140), (78, 10))
    L.line(stem, 5, col)
    for i in range(n):
        t = 0.08 + i * 0.85 / (n - 1)
        x, y = stem[int(t * (len(stem) - 1))]
        sgn = -1 if i % 2 else 1
        L.circle(x + sgn * 26, y, 20 - i * 0.8, col)
    if berry:
        for dx, dy in ((-30, 30), (-18, 44), (-40, 48)):
            L.circle(80 + dx, 60 + dy, 7, berry)
    return L, size


def theme_leaves(out):
    rng = random.Random(3)
    c = Canvas()
    greens = [hexc('#7FA88A'), hexc('#A3C4A8'), hexc('#5E8B70'), hexc('#C6D9C2')]
    berry = hexc('#D98C7A')
    dots_scatter(c, hexc('#A3C4A8', 150), 50, rng, (0, 0, W, H), 4, 8)
    for x, y, a, sz in ((120, 160, 30, 1.2), (1080, 160, -30, 1.2), (60, 620, 10, 1.1), (1140, 620, -15, 1.1),
                        (320, 960, 70, 1.0), (880, 960, -70, 1.0), (560, 40, 90, 0.8), (1000, 900, -40, 0.9),
                        (200, 400, -20, 0.8)):
        place(c, branch(rng.choice(greens), berry if rng.random() < .5 else None, sz), x, y, a)
    for x, y, a in ((380, 100, 30), (820, 120, -40), (700, 1000, 60)):
        place(c, sprig(rng.choice(greens), 0.8), x, y, a)
    c.save(f'{out}/leaves.png')


# ---------------------------------------------------------------- горошек и формы

def theme_shapes(out):
    rng = random.Random(9)
    c = Canvas()
    sand, terra, rose, cream = hexc('#E8C9A0'), hexc('#D98C6A'), hexc('#E6A3A3'), hexc('#F4E3CC')
    for row in range(0, H + 60, 70):
        for col in range(0, W + 60, 70):
            x = col + (35 if (row // 70) % 2 else 0)
            L = Layer(20, 20)
            L.circle(10, 10, 4.5, hexc('#F4E3CC', 120))
            c.put(L.done(), x, row)
    for x, y, r, colr in ((90, 130, 110, terra), (1110, 260, 130, sand), (160, 860, 120, rose),
                          (1050, 900, 100, terra), (600, 1010, 70, sand), (1120, 640, 60, rose), (70, 520, 70, sand)):
        L = Layer(int(r * 2 + 10), int(r * 2 + 10))
        L.circle(r + 5, r + 5, r, colr)
        c.put(L.done(), x, y)
    for x, y, a in ((330, 80, 0), (880, 60, 0), (420, 960, 0)):
        L = Layer(220, 120)
        L.arc(110, 115, 90, 180, 360, 22, cream)
        L.arc(110, 115, 58, 180, 360, 22, rose)
        c.put(L.done(angle=a), x, y)
    c.save(f'{out}/shapes.png')


# ---------------------------------------------------------------- зайчики

def bunny(col, inner, dark, size=1.0):
    L = Layer(200, 260)
    for sgn in (-1, 1):
        L.ellipse(100 + sgn * 26, 70, 20, 62, col)
        L.ellipse(100 + sgn * 26, 74, 9, 44, inner)
    L.ellipse(100, 200, 64, 56, col)
    L.ellipse(100, 150, 56, 48, col)
    L.circle(70, 162, 9, hexc('#F2B8C6'))
    L.circle(130, 162, 9, hexc('#F2B8C6'))
    face(L, 100, 146, 44, dark)
    return L, size


def carrot(col, leaf, size=1.0):
    L = Layer(80, 180)
    L.poly([(22, 50), (58, 50), (40, 170)], col)
    for dx in (-12, 0, 12):
        L.line([(40, 52), (40 + dx * 1.5, 12)], 6, leaf)
    return L, size


def theme_bunnies(out):
    rng = random.Random(21)
    c = Canvas()
    white, beige, grey = hexc('#EDE6DE'), hexc('#D8C2A8'), hexc('#B9B4BE')
    inner = hexc('#F2B8C6')
    ink = hexc('#3A3236')
    dots_scatter(c, hexc('#E9A6B8'), 50, rng, (0, 0, W, H), 4, 8)
    dashes(c, hexc('#9FB7A0'), 30, rng, (0, 0, W, H))
    for x, y, a, colr, sz in ((180, 140, -8, white, 1.0), (1030, 250, 8, beige, 1.0), (120, 760, 6, grey, 0.95),
                              (1060, 820, -6, white, 0.95), (560, 990, 0, beige, 0.7)):
        place(c, bunny(colr, inner, ink, sz), x, y, a)
    for x, y, a in ((420, 80, 30), (840, 980, -30), (1150, 520, 10), (40, 470, -10), (760, 60, -20)):
        place(c, carrot(hexc('#EFA26B'), hexc('#7FA88A'), 0.8), x, y, a)
    for x, y in ((320, 900), (900, 100)):
        place(c, heart(hexc('#E9A6B8'), 0.6), x, y, 0)
    c.save(f'{out}/bunnies.png')


if __name__ == '__main__':
    out = sys.argv[1]
    which = sys.argv[2:] or ['cats']
    for name in which:
        globals()[f'theme_{name}'](out)
        print('ok', name)
