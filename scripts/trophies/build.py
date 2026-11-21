#!/usr/bin/env python3
"""Трофеї-медальйони (ADR-021 §21.2.2): PNG на білому фоні → WebP з прозорим фоном.

  python3 scripts/trophies/build.py IN_DIR flutter_client/assets/trophies

IN_DIR — 01.png … 24.png у порядку каталогу (`supabase/functions/_shared/v1/trophy-catalog.ts`).
Медальйон — коло: межу беремо за рамкою «не білого», вирізаємо згладженим колом трохи всередину
(білі відблиски срібного обідка не з'їдаються, як було б із заливкою білого фону), легка
неточність генератора (еліпс на ~1 %) вирівнюється до кола. На виході:
  large/<id>.webp — 512 px (картка трофея), small/<id>.webp — 192 px (ряд у профілі).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

IDS = [
    'first_find', 'basket', 'full_basket', 'collection_5', 'collection_10', 'season_forager',
    'king_of_forest', 'chanterelle_trail', 'rare_guardian', 'first_hike', 'wanderer', 'forest_veteran',
    'ready_for_forest', 'home_on_time', 'own_footsteps', 'under_watch', 'loyal_guardian', 'mushroom_company',
    'invited_friend', 'twin_expert', 'mycologist', 'recognizer', 'spring_morels', 'winter_honey',
]
SIZES = {'large': 512, 'small': 192}
SS = 4  # суперсемплінг краю кола


def medal(path: str) -> Image.Image:
    im = Image.open(path).convert('RGB')
    a = np.asarray(im).astype(int)
    m = a.min(-1) < 235
    rows = np.where(m.sum(1) > 8)[0]
    cols = np.where(m.sum(0) > 8)[0]
    x0, x1, y0, y1 = cols[0], cols[-1] + 1, rows[0], rows[-1] + 1
    return im.crop((x0, y0, x1, y1))


def circle_alpha(size: int, inset: float) -> Image.Image:
    big = Image.new('L', (size * SS, size * SS), 0)
    r = inset * SS
    ImageDraw.Draw(big).ellipse([r, r, size * SS - r - 1, size * SS - r - 1], fill=255)
    return big.resize((size, size), Image.LANCZOS)


def main():
    src, out = sys.argv[1], sys.argv[2]
    for d in SIZES:
        os.makedirs(os.path.join(out, d), exist_ok=True)
    total = 0
    for i, tid in enumerate(IDS, 1):
        m = medal(os.path.join(src, f'{i:02d}.png'))
        for d, s in SIZES.items():
            img = m.resize((s, s), Image.LANCZOS).convert('RGBA')
            img.putalpha(circle_alpha(s, inset=max(1.0, s * 0.004)))
            p = os.path.join(out, d, f'{tid}.webp')
            img.save(p, 'WEBP', quality=80 if d == 'large' else 82, method=6)
            total += os.path.getsize(p)
        print(f'{i:02d} {tid}')
    print('усього', total // 1024, 'КБ')


main()
