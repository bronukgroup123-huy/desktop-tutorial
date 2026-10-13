#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate_regions_seed.py — Group 9.1

Генерує міграцію supabase/migrations/20260912000014_regions_seed.sql:
seed 27 адміністративних одиниць України (24 області + АР Крим + Київ + Севастополь).

Джерела:
  - Геометрія: geoBoundaries UKR-ADM1 simplified (OpenStreetMap / Wambacher, ODbL)
    https://www.geoboundaries.org/api/current/gbOpen/UKR/ADM1/
  - koatuu + katottg + UA-назви: OCHA/HDX ukr_admgz_adm1_20240305.csv
    (крос-перевірено з katottg.com.ua — збігається 25/27; UA80/UA85 з katottg.com.ua)
  - slug: scripts/regions_map.py (словник каталогу mushroom_catalog.zones)

Формат полігонів: колонка regions.polygon = extensions.GEOMETRY(MultiPolygon, 4326),
а GeoJSON містить ЗМІШАНІ типи (Polygon + MultiPolygon) → ST_Multi() обов'язково.
CRS файлу = CRS84 (= EPSG:4326, lon/lat) → ST_Transform не потрібен.

Запуск:
  curl -sL -o /tmp/ukr_adm1.geojson \
    "https://github.com/wmgeolab/geoBoundaries/raw/main/releaseData/gbOpen/UKR/ADM1/geoBoundaries-UKR-ADM1_simplified.geojson"
  python3 scripts/generate_regions_seed.py
"""

import json
import re
import sys
from pathlib import Path

GEOJSON_PATH = "/tmp/ukr_adm1.geojson"
OUT_PATH = Path("supabase/migrations/20260912000014_regions_seed.sql")

# ISO 3166-2:UA (shapeGeoJSON) → (name_ua, koatuu, katottg, slug)
# koatuu = 10-значний КОАТУУ області; NULL для міст республіканського підпорядкування
# (HDX gazetteer не містить їх кодів — лише katottg.com.ua дає katottg).
# katottg — крос-валідовані 2 джерелами (HDX + katottg.com.ua), формат UA + 17 цифр.
# ПОРЯДОК = порядок INSERT-ів (за КОАТУУ).
REGIONS = [
    # (shapeISO,  name_ua,                  koatuu,       katottg,                  slug)
    ("UA-43",     "АР Крим",                "0100000000", "UA01000000000013043",   "krym"),
    ("UA-05",     "Вінницька",              "0500000000", "UA05000000000010236",   "vinnytska"),
    ("UA-07",     "Волинська",              "0700000000", "UA07000000000024379",   "volynska"),
    ("UA-12",     "Дніпропетровська",       "1200000000", "UA12000000000090473",   "dnipropetrovska"),
    ("UA-14",     "Донецька",               "1400000000", "UA14000000000091971",   "donetska"),
    ("UA-18",     "Житомирська",            "1800000000", "UA18000000000041385",   "zhytomyrska"),
    ("UA-21",     "Закарпатська",           "2100000000", "UA21000000000011690",   "zakarpatska"),
    ("UA-23",     "Запорізька",             "2300000000", "UA23000000000064947",   "zaporizka"),
    ("UA-26",     "Івано-Франківська",      "2600000000", "UA26000000000069363",   "ivano-frankivska"),
    ("UA-32",     "Київська",               "3200000000", "UA32000000000030281",   "kyivska"),
    ("UA-35",     "Кіровоградська",         "3500000000", "UA35000000000016081",   "kirovohradska"),
    ("UA-09",     "Луганська",              "4400000000", "UA44000000000018893",   "luhanska"),
    ("UA-46",     "Львівська",              "4600000000", "UA46000000000026241",   "lvivska"),
    ("UA-48",     "Миколаївська",           "4800000000", "UA48000000000039575",   "mykolaivska"),
    ("UA-51",     "Одеська",                "5100000000", "UA51000000000030770",   "odeska"),
    ("UA-53",     "Полтавська",             "5300000000", "UA53000000000028050",   "poltavska"),
    ("UA-56",     "Рівненська",             "5600000000", "UA56000000000066151",   "rivnenska"),
    ("UA-59",     "Сумська",                "5900000000", "UA59000000000057109",   "sumska"),
    ("UA-61",     "Тернопільська",          "6100000000", "UA61000000000060328",   "ternopilska"),
    ("UA-63",     "Харківська",             "6300000000", "UA63000000000041885",   "kharkivska"),
    ("UA-65",     "Херсонська",             "6500000000", "UA65000000000030969",   "khersonska"),
    ("UA-68",     "Хмельницька",            "6800000000", "UA68000000000099709",   "khmelnytska"),
    ("UA-71",     "Черкаська",              "7100000000", "UA71000000000010357",   "cherkaska"),
    ("UA-77",     "Чернівецька",            "7300000000", "UA73000000000044923",   "chernivetska"),
    ("UA-74",     "Чернігівська",           "7400000000", "UA74000000000025378",   "chernihivska"),
    ("UA-30",     "Київ",                   None,         "UA80000000000093317",   "kyiv"),
    ("UA-40",     "Севастополь",            None,         "UA85000000000065278",   "sevastopol"),
]

HEADER = """-- ============================================================================
-- Regions seed — 27 адміністративних одиниць України (Група 9.1)
-- 24 області + АР Крим + Київ (місто) + Севастополь.
--
-- Джерело геометрії: geoBoundaries UKR-ADM1 simplified
--   (OpenStreetMap / Wambacher) — Open Data Commons ODbL 1.0
--   https://www.geoboundaries.org/api/current/gbOpen/UKR/ADM1/
-- Джерело атрибутів: OCHA/HDX ukr_admgz_adm1_20240305.csv
--   + katottg.com.ua (Київ/Севастополь); slug — scripts/regions_map.py
--   (словник mushroom_catalog.zones).
--
-- Генератор: scripts/generate_regions_seed.py — НЕ редагувати вручну.
-- ============================================================================

"""

ORPHAN_FIX = """
-- ────────────────────────────────────────────────────────────────────
-- Orphan fix: тестова forest_zone з групи 8.1 мала region_id = NULL,
-- бо seed 00002 шукав regions.koatuu = '8036600000' (не обласний код),
-- а таблиця regions була порожня. Прив'язуємо до Києва (slug='kyiv').
-- ────────────────────────────────────────────────────────────────────
UPDATE forest_zones
SET region_id = (SELECT id FROM regions WHERE slug = 'kyiv')
WHERE region_id IS NULL;
"""


def sql_str(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def validate(regions_rows) -> None:
    if len(regions_rows) != 27:
        sys.exit(f"ERROR: очікувалось 27 записів у мапінгу, зараз {len(regions_rows)}")
    for iso, name, koatuu, katottg, slug in regions_rows:
        if not re.fullmatch(r"UA-\d{2}", iso):
            sys.exit(f"ERROR: невалідний shapeISO {iso!r}")
        if koatuu is not None and not re.fullmatch(r"\d{10}", koatuu):
            sys.exit(f"ERROR: невалідний koatuu {koatuu!r} для {iso}")
        # Wikidata P9435 format constraint: UA + 17 цифр (19 символів)
        if not re.fullmatch(r"UA\d{17}", katottg):
            sys.exit(f"ERROR: невалідний katottg {katottg!r} для {iso}")
        if not re.fullmatch(r"[a-z-]+", slug):
            sys.exit(f"ERROR: невалідний slug {slug!r} для {iso}")
    slugs = [r[4] for r in regions_rows]
    if len(set(slugs)) != len(slugs):
        sys.exit("ERROR: дублікати slug у мапінгу")


def main() -> None:
    if not Path(GEOJSON_PATH).exists():
        sys.exit(
            f"ERROR: {GEOJSON_PATH} не знайдено. Завантаж:\n"
            "  curl -sL -o /tmp/ukr_adm1.geojson "
            '"https://github.com/wmgeolab/geoBoundaries/raw/main/releaseData/'
            'gbOpen/UKR/ADM1/geoBoundaries-UKR-ADM1_simplified.geojson"'
        )

    gj = json.loads(Path(GEOJSON_PATH).read_text(encoding="utf-8"))

    crs = gj.get("crs", {}).get("properties", {}).get("name", "")
    if "CRS84" not in crs and "4326" not in crs:
        sys.exit(
            f"ERROR: неочікувана CRS {crs!r} — потрібен ST_Transform або інше джерело"
        )

    geoms = {}
    for feature in gj["features"]:
        props = feature["properties"]
        iso = props.get("shapeISO", "")
        if iso in geoms:
            sys.exit(f"ERROR: дублікат shapeISO {iso} у GeoJSON")
        gtype = feature["geometry"]["type"]
        if gtype not in ("Polygon", "MultiPolygon"):
            sys.exit(f"ERROR: неочікуваний geometry type {gtype} для {iso}")
        geoms[iso] = feature["geometry"]

    validate(REGIONS)

    missing = [iso for iso, *_ in REGIONS if iso not in geoms]
    if missing:
        sys.exit(f"ERROR: немає геометрії для {missing}")
    extra = [iso for iso in geoms if iso not in {r[0] for r in REGIONS}]
    if extra:
        sys.exit(f"ERROR: зайві feature у GeoJSON (нема в мапінгу): {extra}")

    lines = [HEADER]
    for iso, name, koatuu, katottg, slug in REGIONS:
        geom_json = json.dumps(geoms[iso], ensure_ascii=False, separators=(",", ":"))
        geom_json = geom_json.replace("'", "''")  # SQL single-quote escaping
        koatuu_sql = sql_str(koatuu) if koatuu else "NULL"
        # ST_Multi обов'язково: колонка — MultiPolygon, а GeoJSON змішаний
        # (Polygon для деяких областей → вставка без ST_Multi впаде).
        polygon_sql = (
            f"extensions.ST_Multi(extensions.ST_SetSRID("
            f"extensions.ST_GeomFromGeoJSON('{geom_json}'), 4326))"
        )
        lines.append(
            f"INSERT INTO regions (name, koatuu, katottg, slug, polygon)\n"
            f"VALUES ({sql_str(name)}, {koatuu_sql}, {sql_str(katottg)}, "
            f"{sql_str(slug)},\n"
            f"  {polygon_sql})\n"
            f"ON CONFLICT DO NOTHING;\n"
        )
    lines.append(ORPHAN_FIX)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines), encoding="utf-8")

    size_kb = OUT_PATH.stat().st_size / 1024
    print(f"OK: {OUT_PATH}")
    print(f"   27 INSERT-ів + 1 UPDATE, розмір {size_kb:.0f} KB")
    print(f"   перший: {REGIONS[0][1]} ({REGIONS[0][4]}), "
          f"останній: {REGIONS[-1][1]} ({REGIONS[-1][4]})")


if __name__ == "__main__":
    main()
