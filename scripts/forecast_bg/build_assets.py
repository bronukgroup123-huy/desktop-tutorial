#!/usr/bin/env python3
"""Фон вкладки «Прогноз», крок 2: ресурси для живого фону «Ліс за матовим склом».

  python3 scripts/forecast_bg/build_assets.py BASE.png OUT_DIR

BASE.png — картинка після shrink_mushrooms.py. У OUT_DIR:
  base.webp  — фон із «запеченим» матовим склом (легке розмиття, зерно, нерівність скла);
  fog.png    — запотівання по краях (біла маска з альфою; застосунок «дихає» її прозорістю);
  fern.png   — силует дубової гілки з жолудями (розмитий, білий з альфою; застосунок фарбує й гойдає);
  leaf.png   — силует дубового листка, що падає (розмитий);
  rays.png   — віяло сонячних променів від верхнього лівого кута.
Решту (хмарка, сонце, відблиск, краплі) малює застосунок — фон_painter у forecast_background.dart.
Далі — recolor_base.py (тон туману = колір застосунку #F4F1E1), потім shrink_bottom.py (менші гриби з травою).
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


# fern.png: тінь дубової гілки з верхнього правого кута (білі гриби ростуть під дубами; рішення PO
# 2026-11-21 — замість розмитої папороті, яку не впізнавали); leaf.png — дубовий листок, що падає.
S = 3  # суперсемплінг


def oak_leaf(cx, cy, L, ang, lobes=5):
    """Лопатевий листок дуба звичайного: основа в (cx,cy), кінчик у напрямку ang."""
    pts = []
    n = 200
    for i in range(n + 1):
        u = i / n                      # 0 → основа, по правому краю до кінчика, далі лівим назад
        side = 1 if u <= 0.5 else -1
        v = u * 2 if u <= 0.5 else (1 - u) * 2      # 0 основа … 1 кінчик
        # загальна форма — обернене яйце: найширше в верхній третині, вузька основа з «вушками»
        env = math.sin(math.pi * min(1, v ** 0.85)) * (0.55 + 0.45 * v) * (1 - 0.25 * v ** 6)
        lobe = 0.62 + 0.38 * abs(math.cos(math.pi * lobes * v))   # глибокі округлі лопаті
        ear = 0.25 * math.exp(-((v - 0.05) / 0.05) ** 2)          # «вушка» біля черешка
        w = (env * lobe + ear) * 0.36
        lx, ly = side * w * L, -v * L
        ca, sa = math.cos(ang + math.pi / 2), math.sin(ang + math.pi / 2)
        pts.append((cx + lx * ca - ly * sa, cy + lx * sa + ly * ca))
    return pts

def acorn(d, x, y, ang, s):
    ca, sa = math.cos(ang), math.sin(ang)
    def P(px, py):
        return ((x + px * ca - py * sa) * S, (y + px * sa + py * ca) * S)
    body = [P(math.cos(t) * s * 0.42, s * 0.25 + math.sin(t) * s * 0.62) for t in np.linspace(0, math.pi, 30)]
    d.polygon([P(-s * 0.42, s * 0.25)] + body + [P(s * 0.42, s * 0.25)], fill=255)
    cap = [P(math.cos(t) * s * 0.5, s * 0.25 - math.sin(t) * s * 0.28) for t in np.linspace(0, math.pi, 30)]
    d.polygon(cap, fill=255)
    d.line([P(0, -s * 0.05), P(0, -s * 0.4)], fill=255, width=2 * S)

def oak_branch():
    im = Image.new('L', (900 * S, 900 * S), 0)
    d = ImageDraw.Draw(im)
    rng = np.random.default_rng(5)

    def gnarled(x0, y0, ang, L, n=7):
        pts = [(x0, y0)]; x, y = x0, y0
        for i in range(n):
            a = ang + rng.uniform(-0.35, 0.35) + 0.1 * i / n
            x += math.cos(a) * L / n; y += math.sin(a) * L / n
            pts.append((x, y))
        return pts

    def stroke(pts, w0, w1):
        for i in range(len(pts) - 1):
            w = w0 + (w1 - w0) * i / (len(pts) - 1)
            d.line([(pts[i][0] * S, pts[i][1] * S), (pts[i + 1][0] * S, pts[i + 1][1] * S)], fill=255, width=max(1, int(w * S)))
            r = w / 2
            d.ellipse([(pts[i + 1][0] - r) * S, (pts[i + 1][1] - r) * S, (pts[i + 1][0] + r) * S, (pts[i + 1][1] + r) * S], fill=255)

    def cluster(x, y, base_ang, k, size):
        # у дуба листки зібрані пучками на кінцях пагонів
        for j in range(k):
            a = base_ang + (j - (k - 1) / 2) * 0.85 + rng.uniform(-0.1, 0.1)
            ex, ey = x + math.cos(a) * 8, y + math.sin(a) * 8
            d.polygon([(px * S, py * S) for px, py in oak_leaf(ex, ey, size * rng.uniform(0.82, 1.08), a)], fill=255)

    def leaf_at(x, y, a, size):
        ex, ey = x + math.cos(a) * 14, y + math.sin(a) * 14
        d.line([(x * S, y * S), (ex * S, ey * S)], fill=255, width=3 * S)
        d.polygon([(px * S, py * S) for px, py in oak_leaf(ex, ey, size, a)], fill=255)

    main = gnarled(915, 30, math.radians(168), 640)
    stroke(main, 14, 6)
    # листки поодинці вздовж гілки, по черзі з боків, трохи обвисають
    for i, side, size in [(2, -1, 150), (3, 1, 135), (4, -1, 160), (6, 1, 150)]:
        (x, y), (nx, ny) = main[i], main[i + 1]
        a = math.atan2(ny - y, nx - x) + side * math.radians(68)
        a = a * 0.75 + math.radians(90) * 0.25
        leaf_at(x, y, a, size)
    tip = main[-1]
    leaf_at(tip[0], tip[1], math.radians(160), 170)
    leaf_at(tip[0], tip[1], math.radians(205), 150)
    tw = gnarled(*main[5], math.radians(108), 170, 3)
    stroke(tw, 6, 3)
    leaf_at(tw[-1][0], tw[-1][1], math.radians(95), 160)
    leaf_at(tw[1][0], tw[1][1], math.radians(30), 130)
    # жолуді на плодоніжці
    jx, jy = main[1]
    for (dx, dy, a) in [(-30, 78, math.radians(14)), (26, 86, math.radians(-12))]:
        d.line([(jx * S, jy * S), ((jx + dx * 0.8) * S, (jy + dy - 30) * S)], fill=255, width=4 * S)
        acorn(d, jx + dx, jy + dy, a, 56)
    return im.resize((900, 900), Image.LANCZOS).filter(ImageFilter.GaussianBlur(3.2))

def falling_leaf():
    im = Image.new('L', (160 * S, 220 * S), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(x * S, y * S) for x, y in oak_leaf(80, 196, 178, -math.pi / 2)], fill=255)
    d.line([(80 * S, 196 * S), (80 * S, 214 * S)], fill=255, width=4 * S)
    d.line([(80 * S, 30 * S), (80 * S, 196 * S)], fill=160, width=2 * S)
    return im.resize((160, 220), Image.LANCZOS).filter(ImageFilter.GaussianBlur(2.6))

white_alpha(np.asarray(oak_branch().resize((450, 450), Image.LANCZOS))).save(os.path.join(out, 'fern.png'), optimize=True)
white_alpha(np.asarray(falling_leaf().resize((80, 110), Image.LANCZOS))).save(os.path.join(out, 'leaf.png'), optimize=True)

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
