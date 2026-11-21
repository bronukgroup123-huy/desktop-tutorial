#!/usr/bin/env python3
"""Текстура темного дуба для полички трофеїв (PO 2026-11-21): дошки з річними кільцями,
порами, дубовими «променями» (світлі пластівці), сучками й швами між дошками.

  python3 scripts/textures/oak.py flutter_client/assets/textures

На виході: oak_dark.webp (задня стінка, 1024×640) і oak_plank.webp (полиця, 1024×96).
Процедурно (numpy, сталий seed) — щоб можна було перегенерувати без зовнішніх файлів.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

rng = np.random.default_rng(21)


def noise(h, w, scale_y, scale_x, octaves=4):
    """Фрактальний шум 0..1: сума збільшених випадкових сіток."""
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        gy, gx = max(2, int(h / scale_y * 2 ** o)), max(2, int(w / scale_x * 2 ** o))
        g = rng.random((gy, gx))
        out += amp * ndimage.zoom(g, (h / gy, w / gx), order=3)[:h, :w]
        total += amp
        amp *= 0.5
    out /= total
    return (out - out.min()) / (out.max() - out.min())


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def plank(h, w, tone, knots=()):
    """Дошка тангенціального розпилу: «соборні» дуги кілець, пориста рання деревина (дуб —
    кільцесудинний), темна пізня деревина, промені-пластівці, сучки з волокнами довкола."""
    y, x = np.mgrid[0:h, 0:w].astype(float)
    warp = noise(h, w, h * 1.2, w * 0.45, 3) * 34 + noise(h, w, h * 0.25, w * 0.1, 3) * 5
    # сучки відштовхують волокна — кільця огинають їх
    for (ky, kx, kr) in knots:
        r2 = ((y - ky) / 0.6) ** 2 + (x - kx) ** 2
        warp += kr * 2.2 * np.exp(-r2 / (kr * 3.2) ** 2) * np.sign(y - ky + 0.01)
    cy = h * rng.uniform(-0.8, 1.8)  # серцевина дерева поза дошкою — видно дуги
    x0 = w * rng.uniform(0.2, 0.8)
    k = rng.uniform(0.035, 0.075)
    d = np.sqrt((y + warp - cy) ** 2 + ((x - x0) * k) ** 2)
    period = rng.uniform(13, 20)
    frac = (d / period) % 1.0
    late = smooth(0.45, 0.92, frac) * (1 - smooth(0.96, 1.0, frac))  # пізня деревина — темна
    early = 1 - smooth(0.0, 0.22, frac)  # рання — світліша й пориста
    pores = np.clip((noise(h, w, 1.6, 30, 2) - 0.5) / 0.5, 0, 1) ** 1.6
    fine = noise(h, w, 1.2, 9, 2)
    rays = np.clip((noise(h, w, 2.5, 18, 2) - 0.82) / 0.18, 0, 1) * (frac < 0.5)
    tonal = noise(h, w, h * 1.5, w * 0.6, 2)
    base = np.array(tone, float)
    col = base[None, None, :] * (0.82 + 0.32 * tonal[..., None])
    col *= (1 - 0.48 * late[..., None])
    col *= (1 + 0.10 * early[..., None])
    col *= (1 - (0.30 + 0.35 * early[..., None]) * pores[..., None])  # пори глибші в ранній
    col *= (0.93 + 0.12 * fine[..., None])
    col = col * (1 - 0.45 * rays[..., None]) + base * 1.45 * 0.45 * rays[..., None]
    for (ky, kx, kr) in knots:
        col = knot(col, ky, kx, kr)
    return col


def knot(img, cy, cx, r):
    """Сучок: темне серце, кільця довкола, тріщинка."""
    h, w, _ = img.shape
    y, x = np.mgrid[0:h, 0:w].astype(float)
    d = np.sqrt(((y - cy) / 0.62) ** 2 + (x - cx) ** 2)
    m = np.clip(1 - d / (r * 2.2), 0, 1)
    rings = (np.sin(d / 1.8) * 0.5 + 0.5) * m
    img *= (1 - 0.4 * rings[..., None])
    heart = np.clip(1 - d / r, 0, 1) ** 0.6
    img *= (1 - 0.7 * heart[..., None])
    rim = np.exp(-((d - r) / 1.5) ** 2)
    img *= (1 - 0.35 * rim[..., None])
    return img


def board(w, h, planks):
    tones = [(74, 46, 25), (64, 40, 22), (80, 51, 28), (70, 44, 24)]  # темний морений дуб
    rows, y0 = [], 0
    heights = np.diff(np.linspace(0, h, planks + 1).astype(int))
    for i, ph in enumerate(heights):
        kn = [(ph * rng.uniform(0.35, 0.65), w * rng.uniform(0.15, 0.85), rng.uniform(9, 15))] if i % 2 == 0 else []
        p = plank(ph, w, tones[i % len(tones)], kn)
        # шов між дошками: темна щілина, під нею світла фаска
        p[:3] *= np.array([0.35, 0.5, 0.75])[:, None, None]
        p[3:5] = p[3:5] * 0.8 + np.array([150, 105, 65]) * 0.2
        rows.append(p)
        y0 += ph
    img = np.concatenate(rows, 0)
    # легкий лак: віньєтка і м'який відблиск зліва згори
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    vign = 1 - 0.35 * (((xx / w - 0.5) * 1.6) ** 2 + ((yy / h - 0.5) * 1.4) ** 2)
    sheen = 1 + 0.10 * np.exp(-(((xx / w - 0.25) / 0.35) ** 2 + ((yy / h - 0.15) / 0.4) ** 2))
    img = img * vign[..., None] * sheen[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).filter(ImageFilter.UnsharpMask(1.2, 60, 2))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    board(1024, 640, 4).save(os.path.join(out, 'oak_dark.webp'), 'WEBP', quality=82, method=6)
    p = plank(96, 1024, (88, 56, 31))
    Image.fromarray(np.clip(p, 0, 255).astype(np.uint8)).filter(ImageFilter.UnsharpMask(1.2, 60, 2)).save(
        os.path.join(out, 'oak_plank.webp'), 'WEBP', quality=82, method=6)
    for n in ('oak_dark.webp', 'oak_plank.webp'):
        print(n, os.path.getsize(os.path.join(out, n)) // 1024, 'КБ')


main()
