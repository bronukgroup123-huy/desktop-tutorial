#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
parse_zones.py

Розбирає файли поширення грибів (Топ-20 та Популярні 55),
додає поле zones [] у mushroom_catalog.json і перегенерує mushroom_catalog.js.
"""

import csv
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

try:
    from regions_map import REGIONS, GEO_REGIONS, ALL_REGIONS, REGION_LABELS
except ImportError:
    sys.exit("[ERR] Не знайдено regions_map.py поруч із parse_zones.py")


ROOT = Path(__file__).resolve().parent.parent
CATALOG_JSON = ROOT / "mushroom_catalog.json"
CATALOG_JS = ROOT / "mushroom_catalog.js"


def find_distribution_files():
    paths = [
        p for p in ROOT.glob("**/*поширення*.txt")
        if ".kilo" not in str(p) and "node_modules" not in str(p)
    ]
    top20 = None
    top55 = None
    for p in paths:
        name = p.name
        parent = p.parent.name
        if "топ-20" in parent.lower() or "топ-20" in name.lower():
            top20 = p
        elif "популярні 55" in parent.lower() or "популярні 55" in name.lower():
            top55 = p
    return top20, top55


def build_lower_maps():
    geo_lower = {k.lower(): v for k, v in GEO_REGIONS.items()}
    region_lower = {k.lower(): v for k, v in REGIONS.items()}
    all_keys = sorted(
        list(geo_lower.keys()) + list(region_lower.keys()),
        key=len,
        reverse=True,
    )
    return geo_lower, region_lower, all_keys


GEO_LOWER, REGION_LOWER, ALL_KEYS = build_lower_maps()


def parse_zones(text: str):
    result = set()
    text_lower = text.lower()

    for key in ALL_KEYS:
        if key in text_lower:
            if key in GEO_LOWER:
                result.update(GEO_LOWER[key])
            else:
                result.add(REGION_LOWER[key])
            text_lower = text_lower.replace(key, " " * len(key))

    if any(p in text_lower for p in ["по всій", "всі області", "по всій території", "майже по всій"]):
        result.update(ALL_REGIONS)

    return result


def parse_top20(path: Path):
    out = {}
    with open(path, encoding="utf-8-sig") as f:
        content = f.read()

    blocks = re.split(r"\n(?=\d+\.\s)", content)
    for block in blocks:
        m = re.match(r"(\d+)\.\s+(.+?)\s+[-—–]\s+(.+?)\n", block)
        if not m:
            continue
        sci = m.group(3).strip()
        zm = re.search(r"Області?:\s*(.+)", block, re.DOTALL)
        if zm:
            out[sci] = parse_zones(zm.group(1))
    return out


def parse_top55(path: Path):
    out = {}
    with open(path, encoding="utf-8-sig") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 4:
                continue
            try:
                int(parts[0])
            except ValueError:
                continue
            sci = parts[2].strip()
            zones_text = parts[3]
            out[sci] = parse_zones(zones_text)
    return out


def load_catalog():
    with open(CATALOG_JSON, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(catalog):
    pretty = json.dumps(catalog, ensure_ascii=False, indent=2)
    with open(CATALOG_JSON, "w", encoding="utf-8") as f:
        f.write(pretty)
    kb = round(len(pretty.encode("utf-8")) / 1024.0, 1)
    print(f"[OUT] {CATALOG_JSON.name} ({kb} KB)")


def write_js(catalog):
    js_body = json.dumps(catalog, ensure_ascii=False, separators=(",", ":"))
    js_body = js_body.replace("</script", r"<\/script")
    header = "// mushroom_catalog.js\n// Автогенеровано scripts/parse_zones.py. Не редагувати вручну.\n"
    with open(CATALOG_JS, "w", encoding="utf-8") as f:
        f.write(header + "window.MUSHROOM_CATALOG = " + js_body + ";\n")
    kb = round(len(js_body.encode("utf-8")) / 1024.0, 1)
    print(f"[OUT] {CATALOG_JS.name} ({kb} KB)")


def build_lookup(species):
    by_name = {}
    by_latin = {}
    for sp in species:
        by_name[sp.get("name", "")] = sp
        by_latin[sp.get("latin", "")] = sp
    return by_name, by_latin


def sorted_zones(slugs):
    return sorted(slugs, key=lambda s: REGION_LABELS.get(s, s))


def main():
    print("=== parse_zones.py ===")

    top20_path, top55_path = find_distribution_files()
    if not top20_path or not top55_path:
        sys.exit(f"[ERR] Не знайдено обидва файли поширення.\n  top20={top20_path}\n  top55={top55_path}")

    print(f"[IN ] top20: {top20_path}")
    print(f"[IN ] top55: {top55_path}")

    d20 = parse_top20(top20_path)
    d55 = parse_top55(top55_path)
    print(f"[1]  Розпарсено: top20={len(d20)} видів, top55={len(d55)} видів")

    merged = {}
    for k, v in d20.items():
        merged[k] = set(v)
    for k, v in d55.items():
        merged.setdefault(k, set()).update(v)

    catalog = load_catalog()
    species = catalog.get("species", [])
    by_name, by_latin = build_lookup(species)

    matched = 0
    unmatched = []
    zones_count = Counter()

    for sci, zones in merged.items():
        sp = by_name.get(sci) or by_latin.get(sci)
        if not sp:
            unmatched.append(sci)
            continue
        sp["zones"] = sorted_zones(zones)
        matched += 1
        for z in sp["zones"]:
            zones_count[z] += 1

    with_zones = sum(1 for sp in species if sp.get("zones"))
    without_zones = len(species) - with_zones

    write_json(catalog)
    write_js(catalog)

    print(f"\n[2] Оновлено видів: {matched}")
    print(f"    Види з zones: {with_zones}")
    print(f"    Види без zones: {without_zones}")
    if unmatched:
        print(f"\n[WARN] Не знайдено в каталозі ({len(unmatched)}):")
        for u in unmatched:
            print(f"  - {u}")

    print("\n[3] Топ-10 областей за кількістю видів:")
    for slug, count in zones_count.most_common(10):
        print(f"  {REGION_LABELS.get(slug, slug)} ({slug}): {count}")

    print("\nDone!")


if __name__ == "__main__":
    main()
