#!/usr/bin/env python3
"""Фон вкладки «Прогноз», крок 4: нижня частина (гриби з травою) — менша (рішення PO 2026-11-21).

  python3 scripts/forecast_bg/shrink_bottom.py base.webp base.webp [--k 0.78] [--grass 0.65]

Працює з готовою base.webp (841×1870, уже з матовим склом і тоном застосунку):
  1) гриби прибираються (діра заповнюється туманом і травою довкола — нормалізоване розмиття);
  2) смуга трави нижчає: рядки трави стискаються до `--grass` висоти, туман над нею
     розтягується (він гладкий — розтягнення не видно);
  3) гриби повертаються меншими (`--k`) на нову лінію землі, на тих самих місцях по горизонталі;
     краї латки розчиняються, тон туману латки підганяється під місце.
"""
import argparse

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

p = argparse.ArgumentParser()
p.add_argument('src')
p.add_argument('out')
p.add_argument('--k', type=float, default=0.78)
p.add_argument('--grass', type=float, default=0.65)
a = p.parse_args()

im = Image.open(a.src).convert('RGB')
W, H = im.size
img = np.asarray(im).astype(np.float32)

GROUND = 1814       # де стоять гриби
GRASS_TOP = 1745    # звідки починається смуга трави
TOP = 1380          # вище — нічого не змінюємо
GROUPS = [  # (x0, y0, x1, y1) — латка з грибами й туманом довкола
    (488, 1520, 830, GROUND + 14),   # боровики
    (58, 1688, 240, GROUND + 14),    # лисички
]


def nblur(x, w, s):
    wb = ndimage.gaussian_filter(w, s)
    out = np.stack([ndimage.gaussian_filter(x[..., c] * w, s) for c in range(3)], -1)
    return out / np.maximum(wb, 1e-4)[..., None], wb


# 1) прибрати гриби
zones = Image.new('L', (W, H), 0)
dz = ImageDraw.Draw(zones)
for x0, y0, x1, y1 in GROUPS:
    dz.rounded_rectangle([x0 + 8, y0 + 8, x1 - 8, y1 - 4], 40, fill=255)
Z = np.asarray(zones.filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255
keep = (Z < 0.02).astype(np.float32)
fill = None
for sig in (160, 70, 30, 12):
    f, wgt = nblur(img, keep, sig)
    if fill is None:
        fill = f
    else:
        t = np.clip(wgt / 0.3, 0, 1)[..., None]
        fill = f * t + fill * (1 - t)
fill += (np.random.default_rng(2).random((H, W)) - 0.5)[..., None] * 6   # зерно скла
clean = img * (1 - Z[..., None]) + fill * Z[..., None]

# 2) нижча трава: вихідний рядок y → вхідний рядок src(y)
g_out = H - (H - GRASS_TOP) * a.grass
ys = np.arange(H, dtype=np.float32)
src = ys.copy()
m = ys >= g_out
src[m] = GRASS_TOP + (ys[m] - g_out) / a.grass
m2 = (ys >= TOP) & (ys < g_out)
src[m2] = TOP + (ys[m2] - TOP) * (GRASS_TOP - TOP) / (g_out - TOP)
yy = np.repeat(src[:, None], W, 1)
xx = np.repeat(np.arange(W, dtype=np.float32)[None, :], H, 0)
warped = np.stack([ndimage.map_coordinates(clean[..., c], [yy, xx], order=1, mode='nearest') for c in range(3)], -1)

# 3) гриби — меншими, на нову землю
ground_out = H - (H - GROUND) * a.grass
out = warped.copy()
for x0, y0, x1, y1 in GROUPS:
    patch = Image.fromarray(np.clip(img[y0:y1, x0:x1], 0, 255).astype(np.uint8))
    nw, nh = int((x1 - x0) * a.k), int((y1 - y0) * a.k)
    patch = np.asarray(patch.resize((nw, nh), Image.LANCZOS)).astype(np.float32)
    mg = max(8, int(nw * 0.06))
    mask = Image.new('L', (nw, nh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([mg, mg, nw - mg, nh - mg // 2], 30, fill=255)
    mask = np.asarray(mask.filter(ImageFilter.GaussianBlur(mg * 0.8))).astype(np.float32)[..., None] / 255
    cx = (x0 + x1) / 2
    px = int(np.clip(cx - nw / 2, 0, W - nw))
    py = int(ground_out + 14 * a.k - nh)
    region = out[py:py + nh, px:px + nw]
    ring = np.zeros((nh, nw), np.float32)
    bw = mg * 2
    ring[:bw] = 1
    ring[:, :bw] = 1
    ring[:, -bw:] = 1
    corr, _ = nblur(region - patch + 1000, ring, max(nw, nh) / 5)
    patch = patch + (corr - 1000)
    out[py:py + nh, px:px + nw] = region * (1 - mask) + patch * mask

Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(a.out, 'WEBP', quality=82, method=6)
print('гриби ×', a.k, '· трава ×', a.grass, '· земля', GROUND, '→', round(ground_out))
