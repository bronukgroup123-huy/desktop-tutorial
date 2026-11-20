#!/usr/bin/env python3
"""Фон вкладки «Прогноз», крок 3: тон підкладки — як колір застосунку (рішення PO 2026-11-21).

  python3 scripts/forecast_bg/recolor_base.py base.webp base.webp [--target F4F1E1]

Туман на картинці був жовто-зеленуватий і помітно відрізнявся від кольору застосунку
(AppTheme.backgroundColor #F4F1E1). Зсуваємо весь кадр на одну різницю «колір застосунку −
тон туману» (тон туману — медіана світлих пікселів): туман стає кольору застосунку, а тіні,
гриби, листя зберігають свій малюнок і контраст (відносно туману нічого не змінюється).
"""
import argparse

import numpy as np
from PIL import Image

p = argparse.ArgumentParser()
p.add_argument('src')
p.add_argument('out')
p.add_argument('--target', default='F4F1E1')
a = p.parse_args()

target = np.array([int(a.target[i:i + 2], 16) for i in (0, 2, 4)], np.float32)
img = np.asarray(Image.open(a.src).convert('RGB')).astype(np.float32)
lum = img @ np.array([0.299, 0.587, 0.114], np.float32)
haze = np.median(img[lum >= np.percentile(lum, 40)], axis=0)
delta = target - haze
print('тон туману', haze.round(1), '→', target, 'зсув', delta.round(1))
out = np.clip(img + delta, 0, 255).astype(np.uint8)
Image.fromarray(out).save(a.out, 'WEBP', quality=82, method=6)
