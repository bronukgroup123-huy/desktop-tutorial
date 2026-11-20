#!/usr/bin/env python3
"""Фон вкладки «Прогноз», крок 2: ресурси для живого фону «Ліс за матовим склом».

  python3 scripts/forecast_bg/build_assets.py BASE.png OUT_DIR

BASE.png — картинка після shrink_mushrooms.py. У OUT_DIR:
  base.webp  — фон із «запеченим» матовим склом (легке розмиття, зерно, нерівність скла);
  fog.png    — запотівання по краях (біла маска з альфою; застосунок «дихає» її прозорістю);
  fern.png   — силует папороті (розмитий, білий з альфою; застосунок фарбує й гойдає);
  leaf.png   — силует листка (розмитий);
  rays.png   — віяло сонячних променів від верхнього лівого кута.
Решту (хмарка, сонце, відблиск, краплі) малює застосунок — фон_painter у forecast_background.dart.
Далі — recolor_base.py: тон туману на base.webp = колір застосунку (#F4F1E1).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
W, H = 540, 1200   # простір макета; застосунок малює в тих самих координатах


def noise(shape, scale, seed):
    r = np.random.default_rng(seed).random((shape[0] // scale + 2, shape[1] // scale + 2)).astype(np.float32)
    return np.asarray(Image.fromarray((r * 255).astype(np.uint8)).resize((shape[1], shape[0]), Image.BICUBIC)).astype(np.float32) / 255


def white_alpha(alpha):
    a = np.clip(alpha, 0, 255).astype(np.uint8)
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = a
    return Image.fromarray(rgba, 'RGBA')


# base: матове скло запечене
base = Image.open(src).convert('RGB')
bw, bh = base.size
b = np.asarray(base.filter(ImageFilter.GaussianBlur(1.6 * bw / W))).astype(np.float32)
b += (np.random.default_rng(3).random((bh, bw)).astype(np.float32) - 0.5)[..., None] * 7
frost = noise((bh, bw), int(6 * bw / W), 4) * 0.6 + noise((bh, bw), int(2 * bw / W), 5) * 0.4
b += (frost[..., None] - 0.5) * 10
Image.fromarray(np.clip(b, 0, 255).astype(np.uint8)).save(os.path.join(out, 'base.webp'), 'WEBP', quality=82, method=6)

# fog: нерівна молочна димка по краях; біля сонця (верхній лівий кут) — тонша
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
edge = np.minimum.reduce([xx, W - 1 - xx, yy, H - 1 - yy]) / 150
fn = noise((H, W), 40, 9) * 0.7 + noise((H, W), 12, 10) * 0.3
sun_d = np.hypot(xx - 28, yy - 40)
fog = np.clip(1 - edge + (fn - 0.5) * 0.9, 0, 1) ** 1.4 * np.clip(sun_d / 380, 0.35, 1)
white_alpha(fog * 255).resize((W // 2, H // 2), Image.LANCZOS).save(os.path.join(out, 'fog.png'), optimize=True)


# fern: три вайї з верхнього правого кута (полотно 900×900, у застосунку — 675×675)
def fern_sprite():
    im = Image.new('L', (900, 900), 0)
    d = ImageDraw.Draw(im)

    def frond(x0, y0, ang, L, thick):
        pts = []
        x, y = x0, y0
        for i in range(60):
            s = i / 59
            a = ang + 0.55 * s * s
            x += math.cos(a) * L / 59
            y += math.sin(a) * L / 59
            pts.append((x, y, a, s))
        d.line([(p[0], p[1]) for p in pts], fill=255, width=thick)
        for i in range(3, 58, 2):
            x, y, a, s = pts[i]
            ln = (1 - s) * L * 0.22 + 10
            for side in (-1, 1):
                bb = a + side * 1.15
                d.polygon([(x, y), (x + math.cos(bb - side * 0.3) * ln * 0.55, y + math.sin(bb - side * 0.3) * ln * 0.55),
                           (x + math.cos(bb) * ln, y + math.sin(bb) * ln),
                           (x + math.cos(bb + side * 0.25) * ln * 0.5, y + math.sin(bb + side * 0.25) * ln * 0.5)], fill=255)
    frond(880, 20, math.radians(140), 760, 9)
    frond(890, 120, math.radians(158), 620, 8)
    frond(860, -10, math.radians(118), 560, 7)
    return im.filter(ImageFilter.GaussianBlur(11))


white_alpha(np.asarray(fern_sprite().resize((450, 450), Image.LANCZOS))).save(os.path.join(out, 'fern.png'), optimize=True)

# leaf: силует листка берези за склом — серцеподібна основа, загострений кінчик, зубчастий край,
# черешок і центральна жилка (полотно 160×220 у застосунку; листок — у верхній частині, черешок — униз)
def leaf_sprite():
    S = 4
    im = Image.new('L', (160 * S, 220 * S), 0)
    d = ImageDraw.Draw(im)
    pts = []
    for i in range(181):
        t = math.pi * 2 * i / 180
        # серцеподібно-ромбічна форма: ширша внизу, гострий кінчик угорі
        r = 1 - 0.55 * math.sin(t / 2) ** 6
        x = math.sin(t) * (0.62 + 0.18 * math.cos(t)) * r * (1 - 0.75 * max(0.0, math.cos(t)) ** 2.2)  # гострий кінчик
        y = -math.cos(t) * (1 if math.cos(t) > 0 else 0.62)
        z = 1 + 0.035 * math.sin(t * 22)  # дрібні зубчики по краю
        pts.append((80 * S + x * 70 * S * z, 95 * S + y * 82 * S * z))
    d.polygon(pts, fill=255)
    d.line([(80 * S, 150 * S), (82 * S, 212 * S)], fill=255, width=4 * S)              # черешок
    d.line([(80 * S, 22 * S), (80 * S, 150 * S)], fill=150, width=2 * S)               # жилка — світліша
    for k in range(5):                                                                  # бічні жилки
        y0 = (40 + k * 22) * S
        for side in (-1, 1):
            d.line([(80 * S, y0 + 18 * S), (80 * S + side * (34 - k * 3) * S, y0)], fill=170, width=S)
    im = im.resize((160, 220), Image.LANCZOS)
    return im.filter(ImageFilter.GaussianBlur(3.2))


white_alpha(np.asarray(leaf_sprite().resize((80, 110), Image.LANCZOS))).save(os.path.join(out, 'leaf.png'), optimize=True)

# rays: віяло з (0,0), вісь віяла — 52°; полотно 700×700 (у застосунку від центру сонця)
R = 700
ry, rx = np.mgrid[0:R, 0:R].astype(np.float32)
th = np.arctan2(ry, rx)
dist = np.hypot(rx, ry)
rays = np.zeros((R, R), np.float32)
a0 = math.radians(52)
for da, wd, st in [(-0.30, 0.06, 1.0), (-0.15, 0.08, 0.8), (0.0, 0.055, 1.0), (0.13, 0.07, 0.75), (0.27, 0.055, 0.9), (0.4, 0.08, 0.6)]:
    rays += st * np.exp(-((th - (a0 + da)) / wd) ** 2)
rays *= np.clip(1 - dist / 1500, 0, 1) ** 1.1 * np.clip(dist / 90, 0, 1) * np.clip((R - dist) / 160, 0, 1)
white_alpha(np.clip(rays / rays.max(), 0, 1) * 255).resize((R // 2, R // 2), Image.LANCZOS).save(os.path.join(out, 'rays.png'), optimize=True)

for f in sorted(os.listdir(out)):
    print(f, os.path.getsize(os.path.join(out, f)) // 1024, 'КБ')
