#!/usr/bin/env python3
"""
fix_top20_popular.py

Приводить поля top20/popular у mushroom_catalog.json у відповідність
до реальних папок з фото:
  - фото Топ-20 грибів (webp)/
  - фото популярні 55 грибів (webp)/

Запуск: python3 scripts/fix_top20_popular.py
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOP20_FOLDER = ROOT / "фото Топ-20 грибів (webp)"
POPULAR_FOLDER = ROOT / "фото популярні 55 грибів (webp)"
CATALOG_JSON = ROOT / "mushroom_catalog.json"
CATALOG_JS = ROOT / "mushroom_catalog.js"

EXCLUDE_FOLDERS = {"README.md", "поширення.txt", ".gitignore"}


def log(msg):
    print(msg, flush=True)


def load_catalog():
    with open(CATALOG_JSON, "r", encoding="utf-8") as f:
        return json.load(f)


def get_folders(path):
    if not path.exists():
        log(f"[WARN] Папка не знайдена: {path}")
        return []
    return [
        name
        for name in os.listdir(path)
        if (path / name).is_dir() and name not in EXCLUDE_FOLDERS
    ]


def build_photo_index(catalog):
    """
    Будує індекс: species_id -> {top20: bool, popular: bool}
    На основі поля photos[] у JSON.
    """
    index = {}
    for sp in catalog["species"]:
        sid = sp.get("id")
        photos = sp.get("photos", []) or []
        in_top20 = any(p.startswith("фото Топ-20 грибів (webp)/") for p in photos)
        in_popular = any(p.startswith("фото популярні 55 грибів (webp)/") for p in photos)
        index[sid] = {
            "top20": in_top20,
            "popular": in_popular,
            "name": sp.get("name", ""),
        }
    return index


def write_catalog(catalog):
    pretty = json.dumps(catalog, ensure_ascii=False, indent=2)
    with open(CATALOG_JSON, "w", encoding="utf-8") as f:
        f.write(pretty)
    kb = round(len(pretty.encode("utf-8")) / 1024.0, 1)
    log(f"[OUT] {CATALOG_JSON.name} ({kb} KB)")


def write_catalog_js(catalog):
    js_body = json.dumps(catalog, ensure_ascii=False, separators=(',', ':'))
    js_body = js_body.replace("</script", r"<\/script")
    header = "// mushroom_catalog.js\n// Автогенеровано scripts/fix_top20_popular.py. Не редагувати вручну.\n"
    with open(CATALOG_JS, "w", encoding="utf-8") as f:
        f.write(header + "window.MUSHROOM_CATALOG = " + js_body + ";\n")
    kb = round(len(js_body.encode("utf-8")) / 1024.0, 1)
    log(f"[OUT] {CATALOG_JS.name} ({kb} KB)")


def main():
    log("=== fix_top20_popular.py ===")

    catalog = load_catalog()
    species = catalog["species"]
    log(f"[IN ] {len(species)} видів у каталозі")

    top20_folders = get_folders(TOP20_FOLDER)
    popular_folders = get_folders(POPULAR_FOLDER)

    log(f"[1] Папок Топ-20: {len(top20_folders)}")
    log(f"[2] Папок Популярні: {len(popular_folders)}")

    top20_set = set(top20_folders)
    popular_set = set(popular_folders)
    overlap = top20_set & popular_set
    log(f"[3] Спільних папок: {len(overlap)}")
    if overlap:
        for f in sorted(overlap):
            log(f"      {f}")

    updated_top20 = 0
    updated_popular = 0
    unmatched_top20 = []
    unmatched_popular = []
    no_photo_species = []

    for sp in species:
        sid = sp.get("id")
        name = sp.get("name", "")
        photos = sp.get("photos", []) or []

        in_top20 = any(p.startswith("фото Топ-20 грибів (webp)/") for p in photos)
        in_popular = any(p.startswith("фото популярні 55 грибів (webp)/") for p in photos)

        new_top20 = in_top20
        new_popular = in_popular

        if sp.get("top20") != new_top20:
            updated_top20 += 1
        if sp.get("popular") != new_popular:
            updated_popular += 1

        sp["top20"] = new_top20
        sp["popular"] = new_popular

        if not photos:
            no_photo_species.append(name)

    # Звіт по папках, для яких не знайшли відповідника
    for folder in sorted(top20_set | popular_set):
        found = any(
            sp.get("photos", []) and any(
                p.startswith("фото Топ-20 грибів (webp)/" + folder) or
                p.startswith("фото популярні 55 грибів (webp)/" + folder)
                for p in sp.get("photos", [])
            )
            for sp in species
        )
        if not found:
            if folder in top20_set:
                unmatched_top20.append(folder)
            if folder in popular_set:
                unmatched_popular.append(folder)

    log(f"\n[4] Оновлено top20: {updated_top20}")
    log(f"[5] Оновлено popular: {updated_popular}")

    log(f"\n[6] Папки Топ-20 без відповідника в JSON ({len(unmatched_top20)}):")
    for f in unmatched_top20:
        log(f"      {f}")

    log(f"\n[7] Папки Популярні без відповідника в JSON ({len(unmatched_popular)}):")
    for f in unmatched_popular:
        log(f"      {f}")

    log(f"\n[8] Види без фото (has_photo=false): {len(no_photo_species)}")

    write_catalog(catalog)
    write_catalog_js(catalog)

    total_top20 = sum(1 for sp in species if sp.get("top20"))
    total_popular = sum(1 for sp in species if sp.get("popular"))
    total_both = sum(1 for sp in species if sp.get("top20") and sp.get("popular"))
    total_any = sum(1 for sp in species if sp.get("top20") or sp.get("popular"))

    log(f"\n=== Результат ===")
    log(f"  top20:      {total_top20}")
    log(f"  popular:    {total_popular}")
    log(f"  top20 && popular: {total_both}")
    log(f"  top20 || popular: {total_any}")
    log(f"\nDone!")


if __name__ == "__main__":
    main()
