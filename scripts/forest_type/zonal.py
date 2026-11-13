"""
Тип лісу для полігонів OSM за супутниковою картою (вихід s2_leaf_type.py).

Карта — GeoTIFF uint8: ймовірність «хвойний» 0…100 для кожної клітинки лісу 40 м,
255 — не ліс / немає даних. Для полігона беремо середнє по клітинках усередині нього
(малі гаї — клітинки, яких він торкається). Пороги типу — у scripts/forests/lib.ts
(satelliteForestType), тут лише числа.

Використання (workflow «Forests data»):
  python zonal.py --input osm/forests.geojsonseq --rasters rasters/ --out osm/satellite.json
Вихід: {"w123": 87, "r45": 12, …} — ключі в тому ж форматі, що й id лісів у файлах областей.
"""
import argparse
import glob
import json
import sys
import time

import numpy as np
import rasterio
from rasterio.features import bounds as geom_bounds
from rasterio.features import rasterize
from rasterio.warp import transform_bounds, transform_geom
from rasterio.windows import Window, from_bounds

NODATA = 255


def normalize_osm_id(raw):
    """Як normalizeOsmId у lib.ts: osmium `-u type_id` дає a<2·id> (way) / a<2·id+1> (relation)."""
    s = str(raw or "")
    if s.startswith("a") and s[1:].isdigit():
        n = int(s[1:])
        return f"w{n // 2}" if n % 2 == 0 else f"r{(n - 1) // 2}"
    return s.replace("/", "").replace("way", "w", 1).replace("relation", "r", 1)


def polygon_prob(geom, prob, transform, all_touched=True):
    """Середня ймовірність «хвойний» (0…100) усередині геометрії (у CRS карти) і кількість клітинок."""
    h, w = prob.shape
    try:
        win = from_bounds(*geom_bounds(geom), transform=transform)
    except Exception:
        return None, 0
    c0, r0 = int(np.floor(win.col_off)), int(np.floor(win.row_off))
    c1, r1 = int(np.ceil(win.col_off + win.width)), int(np.ceil(win.row_off + win.height))
    c0, r0, c1, r1 = max(c0, 0), max(r0, 0), min(c1, w), min(r1, h)
    if c1 <= c0 or r1 <= r0:
        return None, 0
    window = Window(c0, r0, c1 - c0, r1 - r0)
    wt = rasterio.windows.transform(window, transform)
    mask = rasterize([(geom, 1)], out_shape=(r1 - r0, c1 - c0), transform=wt, fill=0, dtype="uint8",
                     all_touched=all_touched).astype(bool)
    vals = prob[r0:r1, c0:c1][mask]
    vals = vals[vals != NODATA]
    if vals.size == 0:
        return None, 0
    return float(vals.mean()), int(vals.size)


class Raster:
    def __init__(self, path):
        with rasterio.open(path) as src:
            self.prob = src.read(1)
            self.transform = src.transform
            self.crs = src.crs
            self.bbox = transform_bounds(src.crs, "EPSG:4326", *src.bounds, densify_pts=21)
        self.path = path

    def covers(self, b):
        return not (b[2] < self.bbox[0] or b[0] > self.bbox[2] or b[3] < self.bbox[1] or b[1] > self.bbox[3])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="ліси OSM, geojsonseq (EPSG:4326)")
    ap.add_argument("--rasters", required=True, help="тека з forest-type-<slug>.tif")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    rasters = [Raster(p) for p in sorted(glob.glob(f"{a.rasters}/forest-type-*.tif"))]
    if not rasters:
        print("no rasters — nothing to do")
        json.dump({}, open(a.out, "w"))
        return
    for r in rasters:
        print(f"{r.path}: bbox {[round(v, 2) for v in r.bbox]}, {r.crs}")

    out, seen, t0 = {}, 0, time.time()
    with open(a.input, encoding="utf-8") as fh:
        for line in fh:
            line = line.lstrip("\x1e").strip()
            if not line:
                continue
            seen += 1
            f = json.loads(line)
            g = f.get("geometry") or {}
            if g.get("type") not in ("Polygon", "MultiPolygon"):
                continue
            b = geom_bounds(g)
            for r in rasters:
                if not r.covers(b):
                    continue
                p, n = polygon_prob(transform_geom("EPSG:4326", r.crs, g), r.prob, r.transform)
                if p is not None:
                    out[normalize_osm_id(f.get("id"))] = int(round(p))
                    break
            if seen % 100_000 == 0:
                print(f"  … {seen} forests, {len(out)} with satellite type, {time.time() - t0:.0f} s", flush=True)
    json.dump(out, open(a.out, "w"), separators=(",", ":"))
    print(f"done: {seen} forests, {len(out)} with satellite type, {time.time() - t0:.0f} s")


if __name__ == "__main__":
    sys.exit(main())
