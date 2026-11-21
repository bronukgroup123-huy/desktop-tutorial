#!/usr/bin/env python3
"""Готові аватари (ADR-021 §21.7): PNG на білому фоні → WebP з прозорим фоном.

  python3 scripts/avatars/build.py IN_DIR flutter_client/assets/avatars

IN_DIR — <id>.png (traveler_01.png … master_04.png), id — як у `_shared/v1/avatars.ts`.
Рамки рівнів виступають за коло (жолуді, гриби, роги, корона), тому фон вирізаємо не колом,
а заливкою білого від країв картинки; край м'яко згладжуємо. Квадрат 384 px — аватар у профілі
(112 pt) на екрані з густиною до 3.4.
"""
import os
import sys
import numpy as np
from scipy import ndimage
from PIL import Image, ImageFilter

SIZE = 384
WHITE = 238  # «білий фон»: усі канали не нижче


def background(a: np.ndarray) -> np.ndarray:
    """Білий фон, з'єднаний із краєм картинки (білі деталі всередині рамки лишаються)."""
    lab, _ = ndimage.label(a.min(-1) >= WHITE)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    return np.isin(lab, edge[edge > 0])


def cutout(path: str) -> Image.Image:
    im = Image.open(path).convert('RGB')
    a = np.asarray(im)
    bg = background(a)
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8))
    # прибрати світлу облямівку від білого фону й згладити край
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
    rgba = im.convert('RGBA')
    rgba.putalpha(alpha)
    x0, y0, x1, y1 = rgba.getbbox()
    side = max(x1 - x0, y1 - y0)
    sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    sq.paste(rgba.crop((x0, y0, x1, y1)), ((side - (x1 - x0)) // 2, (side - (y1 - y0)) // 2))
    return sq.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    total = 0
    for name in sorted(os.listdir(src)):
        if not name.endswith('.png'):
            continue
        aid = name[:-4]
        p = os.path.join(out, f'{aid}.webp')
        cutout(os.path.join(src, name)).save(p, 'WEBP', quality=82, method=6)
        total += os.path.getsize(p)
        print(aid, os.path.getsize(p) // 1024, 'КБ')
    print('усього', total // 1024, 'КБ')


main()
