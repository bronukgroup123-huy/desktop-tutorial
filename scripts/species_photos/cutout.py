#!/usr/bin/env python3
"""Фото гриба на білому тлі → WebP із прозорим тлом (довідник, ADR-015 §15.8 п.20).

  python3 scripts/species_photos/cutout.py OUT_DIR SIZE species_id=photo.png[#solid] [...]

#solid — гриб суцільний (без просвітів між ніжками): білі блиски всередині силуету не чіпати.

Тло — майже біле, з'єднане з краями кадру (світлі ніжки й білі шапки всередині силуету
лишаються); замкнені «кишені» тла між ніжками — лише чисто білі. Край пом'якшено, колір краю
очищено від білого ореолу. Обрізка по грибу, квадрат SIZE×SIZE, WebP з альфою.
Потрібно: Pillow, numpy, scipy.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


def cutout(path, pockets=True):
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    lo, hi = rgb.min(-1), rgb.max(-1)
    near_white = (lo >= 238) & (hi - lo <= 14)
    labels, n = ndimage.label(near_white)
    border = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    bg = np.isin(labels, border[border > 0])
    # замкнені кишені тла (між ніжками куща) — лише чисто білі й не крихітні
    pure = (lo >= 250) & (hi - lo <= 5) & ~bg
    pl, pn = ndimage.label(pure)
    if pn and pockets:
        sizes = ndimage.sum(np.ones_like(lo), pl, index=np.arange(1, pn + 1))
        bg |= np.isin(pl, np.nonzero(sizes > 250)[0] + 1)
    fg = ~bg
    fg = ndimage.binary_opening(fg, iterations=1)
    fg = ndimage.binary_fill_holes(fg) & ~(bg & (lo >= 250))
    alpha = ndimage.gaussian_filter(fg.astype(np.float32), 0.9)
    alpha = np.clip((alpha - 0.08) / 0.84, 0, 1)
    a = alpha[..., None]
    # прибрати білий ореол на краю: c = (c - (1-a)*255) / a
    clean = np.where(a > 0.02, (rgb - (1 - a) * 255) / np.maximum(a, 1e-3), 0)
    clean = np.clip(clean, 0, 255)
    return np.concatenate([clean, alpha[..., None] * 255], -1).astype(np.uint8)


def frame(rgba, size, margin=0.03):
    ys, xs = np.nonzero(rgba[..., 3] > 6)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    side = int(max(y1 - y0, x1 - x0) * (1 + 2 * margin))
    canvas = np.zeros((side, side, 4), np.uint8)
    oy, ox = (side - (y1 - y0)) // 2, (side - (x1 - x0)) // 2
    canvas[oy:oy + y1 - y0, ox:ox + x1 - x0] = rgba[y0:y1, x0:x1]
    im = Image.fromarray(canvas, 'RGBA').convert('RGBa')      # зменшення без темного ореолу
    return im.resize((size, size), Image.LANCZOS).convert('RGBA')


def main():
    out, size = sys.argv[1], int(sys.argv[2])
    os.makedirs(out, exist_ok=True)
    for arg in sys.argv[3:]:
        sid, path = arg.split('=', 1)
        path, _, flag = path.partition('#')
        im = frame(cutout(path, pockets=flag != 'solid'), size)
        dst = os.path.join(out, f'{sid}.webp')
        im.save(dst, 'WEBP', quality=86, alpha_quality=90, method=6)
        print(f'{sid}: {os.path.getsize(dst) // 1024} КБ')


if __name__ == '__main__':
    main()
