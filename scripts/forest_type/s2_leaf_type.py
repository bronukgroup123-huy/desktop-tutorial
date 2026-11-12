"""
Пілот: тип лісу (хвойний / листяний / мішаний) із Sentinel-2 — без Google Earth Engine.

Ідея (фенологія): хвойний ліс зелений цілий рік, листяний узимку/ранньою весною голий.
Для кожної клітинки лісу беремо медіану NDVI влітку (листя є) і в безлистий період
(листопад, кінець березня — квітень) і дивимось на відношення «безлисте / літнє».

Джерела (відкриті, без акаунтів, комерційне використання дозволене з атрибуцією):
  * Sentinel-2 L2A COG — Earth Search (AWS Open Data), © Copernicus Sentinel data;
  * ESA WorldCover 2021 v200 (CC BY 4.0) — маска «деревна рослинність»;
  * мітки для перевірки — ліси OpenStreetMap з leaf_type / species (ODbL).

Пороги калібруються на половині позначених лісів, точність рахується на іншій половині.

Використання (GitHub Actions):
  python s2_leaf_type.py --bbox 27.19,49.58,29.74,51.69 --labels labels.geojsonseq --out out/
"""
import argparse
import hashlib
import json
import math
import os
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.features import rasterize
from rasterio.transform import from_origin
from rasterio.warp import reproject, transform_bounds, transform_geom
from rasterio.windows import from_bounds

RES = 40.0  # м — роздільність сітки пілоту
DST_CRS = "EPSG:32635"  # UTM 35N — уся Житомирщина в зоні 35
STAC = "https://earth-search.aws.element84.com/v1"
WORLDCOVER = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{tile}_Map.tif"

# SCL Sentinel-2: 4 рослинність, 5 без рослинності, 6 вода, 7 некласифіковано, 2 темні ділянки
# (низьке зимове сонце над густим хвойним лісом часто дає «темні»). Хмари/тіні/сніг — геть.
VALID_SCL_ON = {4, 5, 6, 7}
VALID_SCL_OFF = {2, 4, 5, 6, 7}

SEASONS = {
    "on": ["2024-06-10/2024-08-20", "2025-06-10/2025-08-20"],
    # Справді безлистий період: з середини листопада до кінця березня (у квітні 2024–2025
    # береза й осика на Поліссі вже розпускались — перший прогін через це не розрізняв ліси).
    "off": ["2022-11-15/2023-03-25", "2023-11-15/2024-03-25", "2024-11-15/2025-03-25"],
}
MAX_DATES = {"on": 18, "off": 24}
MAX_PER_MONTH = 3  # щоб не набрати всі дати з одного (найяснішого) місяця


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


# ─── Сітка ────────────────────────────────────────────────────────────────
def make_grid(bbox):
    minx, miny, maxx, maxy = transform_bounds("EPSG:4326", DST_CRS, *bbox, densify_pts=21)
    minx, miny = math.floor(minx / RES) * RES, math.floor(miny / RES) * RES
    maxx, maxy = math.ceil(maxx / RES) * RES, math.ceil(maxy / RES) * RES
    width, height = int((maxx - minx) / RES), int((maxy - miny) / RES)
    return from_origin(minx, maxy, RES, RES), width, height


# ─── Маска лісу: ESA WorldCover ───────────────────────────────────────────
def worldcover_tiles(bbox):
    minx, miny, maxx, maxy = bbox
    tiles = []
    for lat in range(int(math.floor(miny / 3) * 3), int(math.ceil(maxy / 3) * 3), 3):
        for lon in range(int(math.floor(minx / 3) * 3), int(math.ceil(maxx / 3) * 3), 3):
            ns = f"N{lat:02d}" if lat >= 0 else f"S{-lat:02d}"
            ew = f"E{lon:03d}" if lon >= 0 else f"W{-lon:03d}"
            tiles.append(ns + ew)
    return tiles


def forest_mask(bbox, transform, width, height):
    out = np.zeros((height, width), dtype=np.uint8)
    for tile in worldcover_tiles(bbox):
        url = WORLDCOVER.format(tile=tile)
        try:
            with rasterio.open(url) as src:
                win = from_bounds(*bbox, transform=src.transform).round_offsets().round_lengths()
                win = win.intersection(rasterio.windows.Window(0, 0, src.width, src.height))
                # ≈ 40 м у градусах: читаємо з огляду (mode — переважний клас)
                step = 4
                arr = src.read(1, window=win, out_shape=(int(win.height // step), int(win.width // step)),
                               resampling=Resampling.mode)
                wt = src.window_transform(win) * rasterio.Affine.scale(win.width / arr.shape[1], win.height / arr.shape[0])
                tmp = np.zeros_like(out)
                reproject(arr, tmp, src_transform=wt, src_crs=src.crs, dst_transform=transform, dst_crs=DST_CRS,
                          resampling=Resampling.nearest, src_nodata=0, dst_nodata=0)
                out = np.where(tmp > 0, tmp, out)
                log(f"WorldCover {tile}: ok")
        except Exception as e:  # тайл може бути відсутній (море/кордон)
            log(f"WorldCover {tile}: {e}")
    return out == 10  # 10 = Tree cover


# ─── Sentinel-2 ───────────────────────────────────────────────────────────
def search_items(bbox, season):
    from pystac_client import Client
    cat = Client.open(STAC)
    items = []
    for dt in SEASONS[season]:
        res = cat.search(collections=["sentinel-2-l2a"], bbox=bbox, datetime=dt,
                         query={"eo:cloud_cover": {"lt": 40}}, max_items=2000)
        items += list(res.items())
    # лише зона UTM 35 (уся область у ній), щоб не дублювати тайли зони 36
    def epsg(it):
        p = it.properties
        return p.get("proj:epsg") or int(str(p.get("proj:code", "0")).split(":")[-1] or 0)
    items = [it for it in items if epsg(it) == 32635]
    by_date = defaultdict(list)
    for it in items:
        by_date[it.datetime.date().isoformat()].append(it)
    # найменш хмарні дати першими, але не більше MAX_PER_MONTH на місяць
    ranked = sorted(by_date, key=lambda d: np.mean([i.properties.get("eo:cloud_cover", 100) for i in by_date[d]]))
    per_month, dates = defaultdict(int), []
    for d in ranked:
        if per_month[d[:7]] >= MAX_PER_MONTH:
            continue
        per_month[d[:7]] += 1
        dates.append(d)
        if len(dates) >= MAX_DATES[season]:
            break
    log(f"season {season}: {len(items)} items, using {len(dates)} dates: {sorted(dates)}")
    return {d: by_date[d] for d in dates}


def band_params(asset, item):
    rb = (asset.extra_fields.get("raster:bands") or [{}])[0]
    scale = rb.get("scale", 0.0001)
    offset = rb.get("offset")
    if offset is None:
        pb = str(item.properties.get("s2:processing_baseline", "00.00"))
        offset = -0.1 if pb >= "04.00" else 0.0
    return scale, offset


def read_overview(href, level):
    with rasterio.open(href, overview_level=level) as src:
        return src.read(1), src.transform, src.crs


def item_ndvi(item, valid_scl):
    a = item.assets
    red_a, nir_a, scl_a = a["red"], a["nir"], a["scl"]
    red, t10, crs = read_overview(red_a.href, 1)  # 10 м → огляд 40 м
    nir, _, _ = read_overview(nir_a.href, 1)
    scl, t20, _ = read_overview(scl_a.href, 0)  # 20 м → огляд 40 м
    h = min(red.shape[0], nir.shape[0], scl.shape[0])
    w = min(red.shape[1], nir.shape[1], scl.shape[1])
    red, nir, scl = red[:h, :w], nir[:h, :w], scl[:h, :w]
    rs, ro = band_params(red_a, item)
    ns, no = band_params(nir_a, item)
    r = red.astype(np.float32) * rs + ro
    n = nir.astype(np.float32) * ns + no
    with np.errstate(divide="ignore", invalid="ignore"):
        ndvi = (n - r) / (n + r)
    ok = np.isin(scl, list(valid_scl)) & (red > 0) & (nir > 0) & np.isfinite(ndvi)
    ndvi[~ok] = np.nan
    return ndvi, t10, crs


def season_median(bbox, season, transform, width, height, forest):
    dates = search_items(bbox, season)
    valid_scl = VALID_SCL_ON if season == "on" else VALID_SCL_OFF
    stack = []
    for d, items in sorted(dates.items()):
        mosaic = np.full((height, width), np.nan, dtype=np.float32)
        t0 = time.time()
        with ThreadPoolExecutor(max_workers=6) as ex:
            futs = {ex.submit(item_ndvi, it, valid_scl): it.id for it in items}
            for f in as_completed(futs):
                try:
                    ndvi, t, crs = f.result()
                except Exception as e:
                    log(f"  {futs[f]}: {e}")
                    continue
                tmp = np.full((height, width), np.nan, dtype=np.float32)
                reproject(ndvi, tmp, src_transform=t, src_crs=crs, dst_transform=transform, dst_crs=DST_CRS,
                          resampling=Resampling.nearest, src_nodata=np.nan, dst_nodata=np.nan)
                fill = np.isnan(mosaic) & ~np.isnan(tmp)
                mosaic[fill] = tmp[fill]
        on_forest = mosaic[forest & ~np.isnan(mosaic)]
        cover = on_forest.size / max(1, np.count_nonzero(forest))
        med = float(np.median(on_forest)) if on_forest.size else float("nan")
        log(f"  {season} {d}: {len(items)} tiles, valid on forest {cover:.0%}, median forest NDVI {med:.2f}, "
            f"{time.time() - t0:.0f} s")
        stack.append(mosaic.astype(np.float16))
    stack = np.stack(stack) if stack else np.full((1, height, width), np.nan, dtype=np.float16)
    med = np.full((height, width), np.nan, dtype=np.float32)
    cnt = np.zeros((height, width), dtype=np.uint8)
    for r0 in range(0, height, 256):  # по смугах — менше пам'яті
        part = stack[:, r0:r0 + 256].astype(np.float32)
        with np.errstate(all="ignore"):
            med[r0:r0 + 256] = np.nanmedian(part, axis=0)
        cnt[r0:r0 + 256] = np.count_nonzero(~np.isnan(part), axis=0)
    return med, cnt, len(dates)


# ─── Мітки OSM ────────────────────────────────────────────────────────────
CONIFER = ("pinus", "pine", "сосн", "picea", "spruce", "ялин", "larix", "larch", "модрин", "abies", "fir", "ялиц")
BROAD = ("quercus", "oak", "дуб", "betula", "birch", "берез", "populus", "aspen", "осик", "alnus", "alder", "вільх",
         "fagus", "beech", "бук", "carpinus", "hornbeam", "граб", "fraxinus", "ясен", "acer", "клен", "tilia", "лип",
         "robinia", "акаці", "salix", "верб")


def osm_label(tags):
    text = " ".join(str(tags.get(k, "")) for k in ("species", "genus", "taxon", "species:uk", "genus:uk")).lower()
    c = any(k in text for k in CONIFER)
    b = any(k in text for k in BROAD)
    if c and b:
        return 3
    if c:
        return 1
    if b:
        return 2
    lt = str(tags.get("leaf_type", "")).lower()
    wood = str(tags.get("wood", "")).lower()
    if lt == "needleleaved" or wood == "coniferous":
        return 1
    if lt == "broadleaved" or wood == "deciduous":
        return 2
    if lt == "mixed" or wood == "mixed":
        return 3
    return 0


def load_labels(path, transform, width, height):
    shapes_train, shapes_test, n = [], [], defaultdict(int)
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.lstrip("\x1e").strip()
            if not line:
                continue
            f = json.loads(line)
            lab = osm_label(f.get("properties") or {})
            if not lab:
                continue
            geom = transform_geom("EPSG:4326", DST_CRS, f["geometry"])
            split = int(hashlib.md5(str(f.get("id")).encode()).hexdigest(), 16) % 2  # стабільний поділ
            (shapes_test if split else shapes_train).append((geom, lab))
            n[lab] += 1
    log(f"labels: {dict(n)} (1 conifer, 2 broadleaf, 3 mixed); train {len(shapes_train)}, test {len(shapes_test)}")
    r = lambda s: rasterize(s, out_shape=(height, width), transform=transform, fill=0, dtype="uint8") if s else np.zeros((height, width), np.uint8)
    return r(shapes_train), r(shapes_test), dict(n)


# ─── Класифікація ─────────────────────────────────────────────────────────
def classify(ratio, t_lo, t_hi):
    out = np.zeros(ratio.shape, dtype=np.uint8)
    ok = np.isfinite(ratio)
    out[ok & (ratio >= t_hi)] = 1  # хвойний
    out[ok & (ratio <= t_lo)] = 2  # листяний
    out[ok & (ratio > t_lo) & (ratio < t_hi)] = 3  # мішаний / непевний
    return out


def calibrate(ratio, lab):
    c = ratio[(lab == 1) & np.isfinite(ratio)]
    b = ratio[(lab == 2) & np.isfinite(ratio)]
    best = (0, 0.5)
    for t in np.arange(-0.2, 1.2, 0.005):
        bal = 0.5 * (np.mean(c >= t) + np.mean(b < t))
        if bal > best[0]:
            best = (bal, float(t))
    # «мішаний» — смуга невизначеності довкола порогу (≈ 10% кожного класу з боку порогу)
    t = best[1]
    lo = float(np.quantile(b, 0.90)) if b.size else t - 0.05
    hi = float(np.quantile(c, 0.10)) if c.size else t + 0.05
    t_lo, t_hi = min(lo, t - 0.02), max(hi, t + 0.02)
    return t, t_lo, t_hi, best[0], c.size, b.size


def evaluate(pred, lab, forest):
    m = forest & (lab > 0) & (pred > 0)
    conf = np.zeros((4, 4), dtype=np.int64)
    np.add.at(conf, (lab[m], pred[m]), 1)
    binary = (lab[m] != 3) & (pred[m] != 3)
    acc_bin = float(np.mean(lab[m][binary] == pred[m][binary])) if binary.any() else float("nan")
    decided = float(np.mean(pred[m][lab[m] != 3] != 3)) if m.any() else float("nan")
    return {"confusion_label_x_pred": conf[1:, 1:].tolist(), "accuracy_conifer_vs_broadleaf": acc_bin,
            "share_decided_not_mixed": decided, "pixels": int(m.sum())}


def save_preview(cls, forest, path, step=4):
    from PIL import Image
    small = cls[::step, ::step]
    fm = forest[::step, ::step]
    rgb = np.full(small.shape + (3,), 245, dtype=np.uint8)
    rgb[fm] = (200, 200, 200)
    rgb[small == 1] = (27, 94, 32)  # хвойний — темно-зелений
    rgb[small == 2] = (174, 213, 129)  # листяний — світло-зелений
    rgb[small == 3] = (255, 193, 7)  # мішаний — жовтий
    Image.fromarray(rgb).save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bbox", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--out", default="out")
    a = ap.parse_args()
    bbox = [float(x) for x in a.bbox.split(",")]
    os.makedirs(a.out, exist_ok=True)
    t0 = time.time()

    transform, width, height = make_grid(bbox)
    log(f"grid {width}×{height} @ {RES} m ({width * height / 1e6:.1f} M cells)")
    forest = forest_mask(bbox, transform, width, height)
    log(f"forest cells: {forest.sum()} ({forest.mean():.1%})")

    on, on_n, on_dates = season_median(bbox, "on", transform, width, height, forest)
    off, off_n, off_dates = season_median(bbox, "off", transform, width, height, forest)
    with np.errstate(all="ignore"):
        ratio = np.where(forest & (on > 0.4) & (on_n >= 2) & (off_n >= 2), off / on, np.nan).astype(np.float32)
    log(f"forest cells with enough observations: {np.isfinite(ratio).sum()} of {forest.sum()}")
    log(f"median NDVI over forest: summer {np.nanmedian(on[forest]):.2f}, leaf-off {np.nanmedian(off[forest]):.2f}")

    lab_train, lab_test, label_counts = load_labels(a.labels, transform, width, height)
    t, t_lo, t_hi, bal_train, nc, nb = calibrate(ratio, lab_train)
    log(f"threshold {t:.3f} (balanced acc on train {bal_train:.1%}, conifer px {nc}, broadleaf px {nb}); "
        f"mixed band {t_lo:.3f}…{t_hi:.3f}")
    cls = classify(ratio, t_lo, t_hi)
    cls[~forest] = 0

    test = evaluate(cls, lab_test, forest)
    train = evaluate(cls, lab_train, forest)
    shares = {name: float(np.count_nonzero(cls == v) / max(1, np.count_nonzero(cls))) for v, name in
              ((1, "conifer"), (2, "broadleaf"), (3, "mixed"))}
    report = {
        "bbox": bbox, "resolution_m": RES, "grid": [width, height],
        "scenes": {"leaf_on_dates": on_dates, "leaf_off_dates": off_dates},
        "forest_cells": int(forest.sum()), "classified_cells": int(np.count_nonzero(cls)),
        "coverage_of_forest": float(np.count_nonzero(cls) / max(1, forest.sum())),
        "threshold": t, "mixed_band": [t_lo, t_hi], "labels": label_counts,
        "train": train, "test": test, "class_shares": shares,
        "median_ndvi_by_label": {
            name: {"summer": float(np.nanmedian(on[lab_train == v])) if (lab_train == v).any() else None,
                   "leaf_off": float(np.nanmedian(off[lab_train == v])) if (lab_train == v).any() else None}
            for v, name in ((1, "conifer"), (2, "broadleaf"), (3, "mixed"))},
        "median_ratio": {"conifer_train": float(np.nanmedian(ratio[lab_train == 1])) if (lab_train == 1).any() else None,
                          "broadleaf_train": float(np.nanmedian(ratio[lab_train == 2])) if (lab_train == 2).any() else None},
        "minutes": round((time.time() - t0) / 60, 1),
    }
    json.dump(report, open(os.path.join(a.out, "report.json"), "w"), indent=2, ensure_ascii=False)
    print(json.dumps(report, indent=2, ensure_ascii=False))

    profile = dict(driver="GTiff", width=width, height=height, count=1, dtype="uint8", crs=DST_CRS,
                   transform=transform, compress="deflate", nodata=0, tiled=True)
    with rasterio.open(os.path.join(a.out, "forest_type_40m.tif"), "w", **profile) as dst:
        dst.write(cls, 1)
    save_preview(cls, forest, os.path.join(a.out, "preview.png"))
    log("done")


if __name__ == "__main__":
    sys.exit(main())
