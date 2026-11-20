"""Фон вкладки «Прогноз», крок 1: на картинці PO зменшити гриби (прибрати, заповнити туманом,
поставити меншими на ту саму «землю»).

  python3 scripts/forecast_bg/shrink_mushrooms.py SRC.png OUT.png

Координати зон — під картинку PO 841×1870 (ліс за матовим склом, гриби внизу).
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
K = 0.66

im = Image.open(SRC).convert('RGB')
W, H = im.size
a = np.asarray(im).astype(np.float32)
GROUND = 1832  # лінія «землі», на якій стоять гриби

# Зони з грибами (з запасом): боровики праворуч і лисички ліворуч
zones = Image.new('L', (W, H), 0)
d = ImageDraw.Draw(zones)
d.rounded_rectangle([345, 1385, 835, GROUND + 10], 60, fill=255)  # зона прибирання
d.rounded_rectangle([30, 1625, 275, GROUND + 10], 50, fill=255)
Z = np.asarray(zones.filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255

# «Чистий» фон: нормалізоване розмиття у float без зон з грибами (кольори довкола затікають у діру)
from scipy import ndimage


def nblur(img, w, s):
    wb = ndimage.gaussian_filter(w, s)
    out = np.stack([ndimage.gaussian_filter(img[..., c] * w, s) for c in range(3)], -1)
    return out / np.maximum(wb, 1e-4)[..., None], wb


keep = (Z < 0.02).astype(np.float32)
fill = None
for sig in (220, 90, 40, 18):                          # від грубого до дрібного: дрібне — лише де вистачає сусідів
    f, w = nblur(a, keep, sig)
    if fill is None:
        fill = f
    else:
        t = np.clip(w / 0.3, 0, 1)[..., None]
        fill = f * t + fill * (1 - t)
# мох знизу: колір рядка з місця без грибів
moss_rows = a[:, 290:330].mean(1)
for y in range(GROUND - 10, H):
    k = np.clip((y - (GROUND - 10)) / 12, 0, 1)
    fill[y] = fill[y] * (1 - k) + moss_rows[y] * k
fill = fill + (np.random.default_rng(1).random((H, W)) - 0.5)[..., None] * 3
base = a * (1 - Z[..., None]) + fill * Z[..., None]

# Перенести групи цілими (разом із туманом довкола) і м'яко розчинити краї — туман зливається з туманом
out = base.copy()
for (x0, y0, x1, y1), anchor_x in [((330, 1360, 841, GROUND + 6), 655), ((15, 1605, 290, GROUND + 6), 150)]:
    patch = Image.fromarray(np.clip(a[y0:y1, x0:x1], 0, 255).astype(np.uint8))
    nw, nh = int((x1 - x0) * K), int((y1 - y0) * K)
    patch = np.asarray(patch.resize((nw, nh), Image.LANCZOS)).astype(np.float32)
    m = Image.new('L', (nw, nh), 0)
    mg = max(8, int(nw * 0.045))
    ImageDraw.Draw(m).rounded_rectangle([mg, mg, nw - mg, nh + 60], 40, fill=255)
    m = np.asarray(m.filter(ImageFilter.GaussianBlur(mg * 0.9))).astype(np.float32)[..., None] / 255
    px = int(anchor_x - nw / 2)
    py = GROUND + 6 - nh
    region = out[py:py + nh, px:px + nw]
    # вирівняти тон туману латки під місце, куди ставимо (щоб не було «квадрата»)
    # плавне поле поправки тону: різниця «місце − латка» по кільцю біля країв, розтягнута всередину
    ring = np.zeros((nh, nw), np.float32)
    bw = mg * 2
    ring[:bw] = 1
    ring[:, :bw] = 1
    ring[:, -bw:] = 1
    corr, _w = nblur(region - patch + 1000, ring, max(nw, nh) / 5)
    patch = patch + (corr - 1000)
    out[py:py + nh, px:px + nw] = region * (1 - m) + patch * m
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(OUT)
print('ok')
