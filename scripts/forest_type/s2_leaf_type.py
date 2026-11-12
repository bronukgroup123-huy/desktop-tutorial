"""
Пілот: тип лісу (хвойний / листяний / мішаний) із Sentinel-2 — без Google Earth Engine.

Ідея (фенологія): хвойний ліс зелений цілий рік, листяний узимку/ранньою весною голий.
Для кожної клітинки лісу беремо медіану NDVI влітку (листя є) і в безлистий період
(листопад, кінець березня — квітень) і дивимось на відношення «безлисте / літнє».

Джерела (відкриті, без акаунтів, комерційне використання дозволене з атрибуцією):
  * Sentinel-2 L2A COG — Earth Search (AWS Open Data), © Copernicus Sentinel data;
  * ESA WorldCover 2021 v200 (CC BY 4.0) — маска «деревна рослинність»;
  * мітки для перевірки — ліси OpenStreetMap з leaf_type / species (ODbL).

Ознаки: NDVI, NIR (B08) і NDMI (B08/B11) влітку й у безлистий період + відношення NDVI.
Класифікатор — Random Forest, навчений на половині позначених лісів (полігони ≤ 200 га,
класи збалансовані); точність рахується на іншій половині (поділ за md5 id полігону).

Використання (GitHub Actions):
  python s2_leaf_type.py --slug zhytomyrska --bbox 27.19,49.58,29.74,51.69 --labels labels.geojsonseq --out out/

Вихід: forest-type-<slug>.tif — ймовірність «хвойний» 0…100 на клітинку лісу 40 м (255 — не ліс),
її читає zonal.py під час збірки файлів лісів; report.json; preview.png.
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

from zonal import NODATA, polygon_prob

# Тип полігона за середньою ймовірністю «хвойний» — ті самі пороги, що в lib.ts (satelliteForestType).
POLY_CONIFER_MIN, POLY_BROADLEAF_MAX = 60, 40

RES = 40.0  # м — роздільність сітки пілоту
DST_CRS = "EPSG:32635"  # перевизначається в main() — зона UTM центру області
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
    # Тайли всіх зон UTM: область на межі зон інакше лишилася б без частини знімків.
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
    """Масштаб і зсув із метаданих STAC (зсув перевіряється ще й за даними — див. item_ndvi)."""
    rb = (asset.extra_fields.get("raster:bands") or [{}])[0]
    offset = rb.get("offset", 0.0)
    # Earth Search позначає, що зсув +1000 уже прибрано з самих даних.
    if item.properties.get("earthsearch:boa_offset_applied") is True:
        offset = 0.0
    return rb.get("scale", 0.0001), offset


def read_overview(href, level):
    with rasterio.open(href, overview_level=level) as src:
        return src.read(1), src.transform, src.crs


FEATURES = ("ndvi", "nir", "ndmi")


def item_ndvi(item, valid_scl):
    """Ознаки знімка на сітці 40 м: NDVI, NIR (B08) і NDMI = (NIR − SWIR1) / (NIR + SWIR1)."""
    a = item.assets
    red_a, nir_a, scl_a, sw_a = a["red"], a["nir"], a["scl"], a["swir16"]
    red, t10, crs = read_overview(red_a.href, 1)  # 10 м → огляд 40 м
    nir, _, _ = read_overview(nir_a.href, 1)
    scl, t20, _ = read_overview(scl_a.href, 0)  # 20 м → огляд 40 м
    sw, _, _ = read_overview(sw_a.href, 0)
    h = min(red.shape[0], nir.shape[0], scl.shape[0], sw.shape[0])
    w = min(red.shape[1], nir.shape[1], scl.shape[1], sw.shape[1])
    red, nir, scl, sw = red[:h, :w], nir[:h, :w], scl[:h, :w], sw[:h, :w]
    rs, ro = band_params(red_a, item)
    ns, no = band_params(nir_a, item)
    ss, so = band_params(sw_a, item)
    # Перевірка за даними: з урахованим зсувом +1000 червоний канал рослинності ≥ ~1000 DN.
    # Якщо медіана нижча — зсув уже прибраний (а метадані кажуть інакше): не віднімаємо вдруге.
    veg = (scl == 4) & (red > 0)
    if ro < 0 and np.count_nonzero(veg) > 1000 and float(np.median(red[veg])) < 900:
        ro = no = so = 0.0
    r = red.astype(np.float32) * rs + ro
    n = nir.astype(np.float32) * ns + no
    sw1 = sw.astype(np.float32) * ss + so
    with np.errstate(divide="ignore", invalid="ignore"):
        ndvi = (n - r) / (n + r)
        ndmi = (n - sw1) / (n + sw1)
    ok = np.isin(scl, list(valid_scl)) & (red > 0) & (nir > 0) & np.isfinite(ndvi) & (r > 0) & (n > 0)
    ndvi[~ok] = np.nan
    bad = np.count_nonzero(np.abs(ndvi[ok]) > 1.0001)
    if bad > 0.001 * max(1, np.count_nonzero(ok)):
        raise ValueError(f"NDVI out of [-1, 1] in {bad} px — wrong scale/offset (scale {rs}, offset {ro})")
    ndmi[~ok | ~np.isfinite(ndmi) | (sw1 <= 0)] = np.nan
    nir_r = np.where(ok, n, np.nan).astype(np.float32)
    return {"ndvi": np.clip(ndvi, -1, 1), "nir": nir_r, "ndmi": np.clip(ndmi, -1, 1)}, t10, crs


def season_median(bbox, season, transform, width, height, forest):
    """Медіани ознак за сезон: {feature: масив}, кількість спостережень, кількість дат."""
    dates = search_items(bbox, season)
    valid_scl = VALID_SCL_ON if season == "on" else VALID_SCL_OFF
    stacks = {f: [] for f in FEATURES}
    for d, items in sorted(dates.items()):
        mosaic = {f: np.full((height, width), np.nan, dtype=np.float32) for f in FEATURES}
        t0 = time.time()
        with ThreadPoolExecutor(max_workers=6) as ex:
            futs = {ex.submit(item_ndvi, it, valid_scl): it.id for it in items}
            for fu in as_completed(futs):
                try:
                    feats, t, crs = fu.result()
                except Exception as e:
                    log(f"  {futs[fu]}: {e}")
                    continue
                for f in FEATURES:
                    tmp = np.full((height, width), np.nan, dtype=np.float32)
                    reproject(feats[f], tmp, src_transform=t, src_crs=crs, dst_transform=transform, dst_crs=DST_CRS,
                              resampling=Resampling.nearest, src_nodata=np.nan, dst_nodata=np.nan)
                    fill = np.isnan(mosaic[f]) & ~np.isnan(tmp)
                    mosaic[f][fill] = tmp[fill]
        on_forest = mosaic["ndvi"][forest & ~np.isnan(mosaic["ndvi"])]
        cover = on_forest.size / max(1, np.count_nonzero(forest))
        med = float(np.median(on_forest)) if on_forest.size else float("nan")
        log(f"  {season} {d}: {len(items)} tiles, valid on forest {cover:.0%}, median forest NDVI {med:.2f}, "
            f"{time.time() - t0:.0f} s")
        if cover < 0.10:
            continue  # майже вся дата — хмари/сніг: мало користі, а пам'ять займає
        for f in FEATURES:
            stacks[f].append(mosaic[f].astype(np.float16))
    out, cnt = {}, np.zeros((height, width), dtype=np.uint8)
    for f in FEATURES:
        st = np.stack(stacks[f]) if stacks[f] else np.full((1, height, width), np.nan, dtype=np.float16)
        med = np.full((height, width), np.nan, dtype=np.float32)
        for r0 in range(0, height, 256):  # по смугах — менше пам'яті
            part = st[:, r0:r0 + 256].astype(np.float32)
            with np.errstate(all="ignore"):
                med[r0:r0 + 256] = np.nanmedian(part, axis=0)
            if f == "ndvi":
                cnt[r0:r0 + 256] = np.count_nonzero(~np.isnan(part), axis=0)
        out[f] = med
        stacks[f] = None
    return out, cnt, len(dates)


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


MAX_LABEL_HA = 200  # великі загальні контури OSM часто змішують хвойні й листяні ділянки


def ring_area(ring):
    return abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(ring, ring[1:] + ring[:1]))) / 2


def geom_area_m2(g):
    polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
    return sum(ring_area(p[0]) - sum(ring_area(h) for h in p[1:]) for p in polys)


def load_labels(path, transform, width, height):
    shapes_train, shapes_test, n = [], [], defaultdict(int)
    skipped_big = 0
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
            if geom_area_m2(geom) > MAX_LABEL_HA * 10_000:
                skipped_big += 1
                continue
            split = int(hashlib.md5(str(f.get("id")).encode()).hexdigest(), 16) % 2  # стабільний поділ
            (shapes_test if split else shapes_train).append((geom, lab))
            n[lab] += 1
    log(f"labels ≤ {MAX_LABEL_HA} ha: {dict(n)} (1 conifer, 2 broadleaf, 3 mixed); train {len(shapes_train)}, "
        f"test {len(shapes_test)}; skipped big {skipped_big}")
    r = lambda s: rasterize(s, out_shape=(height, width), transform=transform, fill=0, dtype="uint8") if s else np.zeros((height, width), np.uint8)
    return r(shapes_train), r(shapes_test), dict(n), shapes_test


# ─── Класифікація ─────────────────────────────────────────────────────────
def evaluate(pred, lab, forest):
    m = forest & (lab > 0) & (pred > 0)
    conf = np.zeros((4, 4), dtype=np.int64)
    np.add.at(conf, (lab[m], pred[m]), 1)
    binary = (lab[m] != 3) & (pred[m] != 3)
    acc_bin = float(np.mean(lab[m][binary] == pred[m][binary])) if binary.any() else float("nan")
    decided = float(np.mean(pred[m][lab[m] != 3] != 3)) if m.any() else float("nan")
    recall = {name: float(conf[v, v] / max(1, conf[v, 1] + conf[v, 2])) for v, name in ((1, "conifer"), (2, "broadleaf"))}
    return {"confusion_label_x_pred": conf[1:, 1:].tolist(), "accuracy_conifer_vs_broadleaf": acc_bin,
            "recall_decided": recall, "balanced_accuracy": (recall["conifer"] + recall["broadleaf"]) / 2,
            "share_decided_not_mixed": decided, "pixels": int(m.sum())}


def evaluate_polygons(shapes, prob8, transform):
    """Точність на рівні полігонів (як у застосунку): середня ймовірність → тип за порогами."""
    conf = np.zeros((4, 4), dtype=np.int64)  # мітка × прогноз (1 хвойний, 2 листяний, 3 мішаний)
    missing = 0
    for geom, lab in shapes:
        p, _ = polygon_prob(geom, prob8, transform)
        if p is None:
            missing += 1
            continue
        pred = 1 if p >= POLY_CONIFER_MIN else 2 if p <= POLY_BROADLEAF_MAX else 3
        conf[lab, pred] += 1
    recall = {name: float(conf[v, v] / max(1, conf[v, 1] + conf[v, 2])) for v, name in ((1, "conifer"), (2, "broadleaf"))}
    decided = {name: float((conf[v, 1] + conf[v, 2]) / max(1, conf[v, 1:].sum())) for v, name in ((1, "conifer"), (2, "broadleaf"))}
    return {"confusion_label_x_pred": conf[1:, 1:].tolist(), "recall_decided": recall,
            "balanced_accuracy": (recall["conifer"] + recall["broadleaf"]) / 2,
            "share_decided_not_mixed": decided, "polygons": int(conf.sum()), "no_data": missing}


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
    ap.add_argument("--slug", default="zhytomyrska")
    ap.add_argument("--bbox", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--out", default="out")
    a = ap.parse_args()
    bbox = [float(x) for x in a.bbox.split(",")]
    global DST_CRS
    DST_CRS = f"EPSG:{32600 + int((((bbox[0] + bbox[2]) / 2) + 180) // 6) + 1}"
    log(f"CRS {DST_CRS}")
    os.makedirs(a.out, exist_ok=True)
    t0 = time.time()

    transform, width, height = make_grid(bbox)
    log(f"grid {width}×{height} @ {RES} m ({width * height / 1e6:.1f} M cells)")
    forest = forest_mask(bbox, transform, width, height)
    log(f"forest cells: {forest.sum()} ({forest.mean():.1%})")

    on, on_n, on_dates = season_median(bbox, "on", transform, width, height, forest)
    off, off_n, off_dates = season_median(bbox, "off", transform, width, height, forest)
    ok = forest & (on["ndvi"] > 0.4) & (on_n >= 2) & (off_n >= 2)
    with np.errstate(all="ignore"):
        ratio = np.where(ok, off["ndvi"] / on["ndvi"], np.nan).astype(np.float32)
    feats = [on["ndvi"], off["ndvi"], ratio, on["ndmi"], off["ndmi"], on["nir"], off["nir"]]
    names = ["ndvi_on", "ndvi_off", "ndvi_ratio", "ndmi_on", "ndmi_off", "nir_on", "nir_off"]
    for fa in feats:
        ok &= np.isfinite(fa)
    log(f"forest cells with all features: {ok.sum()} of {forest.sum()}")
    log(f"median over forest: NDVI summer {np.nanmedian(on['ndvi'][forest]):.2f}, "
        f"leaf-off {np.nanmedian(off['ndvi'][forest]):.2f}")

    lab_train, lab_test, label_counts, test_shapes = load_labels(a.labels, transform, width, height)

    # Random Forest на пікселях навчальних лісів (хвойний / листяний), класи збалансовані.
    from sklearn.ensemble import RandomForestClassifier
    rng = np.random.default_rng(0)
    xs, ys = [], []
    for cls_id in (1, 2):
        idx = np.flatnonzero(ok & (lab_train == cls_id))
        if idx.size > 40_000:
            idx = rng.choice(idx, 40_000, replace=False)
        xs.append(np.stack([fa.ravel()[idx] for fa in feats], axis=1))
        ys.append(np.full(idx.size, cls_id))
    X, y = np.concatenate(xs), np.concatenate(ys)
    log(f"training on {len(y)} px: conifer {np.sum(y == 1)}, broadleaf {np.sum(y == 2)}")
    rf = RandomForestClassifier(n_estimators=150, max_depth=14, min_samples_leaf=20, class_weight="balanced",
                                n_jobs=-1, random_state=0).fit(X, y)
    importances = dict(zip(names, (round(float(v), 3) for v in rf.feature_importances_)))
    log(f"feature importances: {importances}")

    cls = np.zeros((height, width), dtype=np.uint8)
    prob_conifer = np.full((height, width), np.nan, dtype=np.float32)
    flat_ok = np.flatnonzero(ok)
    for c0 in range(0, flat_ok.size, 2_000_000):
        idx = flat_ok[c0:c0 + 2_000_000]
        p = rf.predict_proba(np.stack([fa.ravel()[idx] for fa in feats], axis=1))[:, list(rf.classes_).index(1)]
        prob_conifer.ravel()[idx] = p
    MIXED = 0.2  # |p − 0.5| < MIXED → «мішаний / непевний»
    cls[ok & (prob_conifer >= 0.5 + MIXED)] = 1
    cls[ok & (prob_conifer <= 0.5 - MIXED)] = 2
    cls[ok & (prob_conifer > 0.5 - MIXED) & (prob_conifer < 0.5 + MIXED)] = 3
    t_lo, t_hi = 0.5 - MIXED, 0.5 + MIXED

    prob8 = np.full((height, width), NODATA, dtype=np.uint8)
    prob8[ok] = np.clip(np.round(prob_conifer[ok] * 100), 0, 100).astype(np.uint8)
    poly_test = evaluate_polygons(test_shapes, prob8, transform)
    log(f"polygon-level test: {poly_test}")

    test = evaluate(cls, lab_test, forest)
    train = evaluate(cls, lab_train, forest)
    shares = {name: float(np.count_nonzero(cls == v) / max(1, np.count_nonzero(cls))) for v, name in
              ((1, "conifer"), (2, "broadleaf"), (3, "mixed"))}
    report = {
        "bbox": bbox, "resolution_m": RES, "grid": [width, height],
        "scenes": {"leaf_on_dates": on_dates, "leaf_off_dates": off_dates},
        "forest_cells": int(forest.sum()), "classified_cells": int(np.count_nonzero(cls)),
        "coverage_of_forest": float(np.count_nonzero(cls) / max(1, forest.sum())),
        "model": "RandomForest", "feature_importances": importances,
        "mixed_band_prob_conifer": [t_lo, t_hi], "labels_max_ha": MAX_LABEL_HA, "labels": label_counts,
        "train": train, "test": test, "test_polygons": poly_test, "class_shares": shares,
        "median_ndvi_by_label": {
            name: {"summer": float(np.nanmedian(on["ndvi"][lab_train == v])) if (lab_train == v).any() else None,
                   "leaf_off": float(np.nanmedian(off["ndvi"][lab_train == v])) if (lab_train == v).any() else None}
            for v, name in ((1, "conifer"), (2, "broadleaf"), (3, "mixed"))},
        "minutes": round((time.time() - t0) / 60, 1),
    }
    json.dump(report, open(os.path.join(a.out, "report.json"), "w"), indent=2, ensure_ascii=False)
    print(json.dumps(report, indent=2, ensure_ascii=False))

    profile = dict(driver="GTiff", width=width, height=height, count=1, dtype="uint8", crs=DST_CRS,
                   transform=transform, compress="deflate", nodata=0, tiled=True)
    with rasterio.open(os.path.join(a.out, f"forest-type-{a.slug}.tif"), "w",
                       **{**profile, "nodata": NODATA, "predictor": 2}) as dst:
        dst.write(prob8, 1)
        dst.update_tags(slug=a.slug, created=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        meaning="probability of coniferous forest, percent; 255 = not forest",
                        source="Copernicus Sentinel-2 L2A (Earth Search), ESA WorldCover 2021, OSM labels")
    save_preview(cls, forest, os.path.join(a.out, "preview.png"))
    log("done")


if __name__ == "__main__":
    sys.exit(main())
