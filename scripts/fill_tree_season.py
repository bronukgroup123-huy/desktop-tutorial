#!/usr/bin/env python3
"""
fill_tree_season.py

Заповнює attrs.tree і attrs.season для видів з фото
на основі описів.txt і вже заповнених months.

Запуск: python3 scripts/fill_tree_season.py
"""

import json
import os
import re
import sys
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parent.parent
TOP20_FOLDER = ROOT / "фото Топ-20 грибів (webp)"
POPULAR_FOLDER = ROOT / "фото популярні 55 грибів (webp)"
RED_BOOK_FOLDER = ROOT / "Червона книга (webp)"
POISONOUS_FOLDER = ROOT / "Отруйні та смертельно отруйні (webp)"
CATALOG_JSON = ROOT / "mushroom_catalog.json"
CATALOG_JS = ROOT / "mushroom_catalog.js"

EXCLUDE_FOLDERS = {"README.md", "поширення.txt", ".gitignore"}
PHOTO_FOLDERS = [TOP20_FOLDER, POPULAR_FOLDER, RED_BOOK_FOLDER, POISONOUS_FOLDER]

MONTH_GROUPS = {
    'spring': [3, 4, 5],
    'summer': [6, 7, 8],
    'autumn': [9, 10, 11],
    'winter': [12, 1, 2]
}

TREE_KEYWORDS = [
    ('сосн', 'pine'),
    ('ялин', 'spruce'),
    ('дуб', 'oak'),
    ('берез', 'birch'),
    ('осик', 'aspen'),
    ('мішан', 'mixed'),
    ('змішан', 'mixed'),
    ('листян', 'deciduous'),
    ('хвойн', 'coniferous'),
    ('будь-як', 'any'),
]

HEADING_RE = re.compile(
    r'^(🌲\s*)?(Де росте|Місце зростання|Де росте\?)',
    re.IGNORECASE
)


def log(msg):
    print(msg, flush=True)


def load_catalog():
    with open(CATALOG_JSON, "r", encoding="utf-8") as f:
        return json.load(f)


def write_catalog(catalog):
    pretty = json.dumps(catalog, ensure_ascii=False, indent=2)
    with open(CATALOG_JSON, "w", encoding="utf-8") as f:
        f.write(pretty)
    kb = round(len(pretty.encode("utf-8")) / 1024.0, 1)
    log(f"[OUT] {CATALOG_JSON.name} ({kb} KB)")


def write_catalog_js(catalog):
    js_body = json.dumps(catalog, ensure_ascii=False, separators=(',', ':'))
    js_body = js_body.replace("</script", r"<\/script")
    header = "// mushroom_catalog.js\n// Автогенеровано scripts/fill_tree_season.py. Не редагувати вручну.\n"
    with open(CATALOG_JS, "w", encoding="utf-8") as f:
        f.write(header + "window.MUSHROOM_CATALOG = " + js_body + ";\n")
    kb = round(len(js_body.encode("utf-8")) / 1024.0, 1)
    log(f"[OUT] {CATALOG_JS.name} ({kb} KB)")


def get_folders(path):
    if not path.exists():
        return []
    return [
        name
        for name in os.listdir(path)
        if (path / name).is_dir() and name not in EXCLUDE_FOLDERS
    ]


def find_opis_folder(species):
    photos = species.get("photos", []) or []
    for p in photos:
        parts = p.split("/")
        if len(parts) < 2:
            continue
        folder_name = parts[1]
        for base in PHOTO_FOLDERS:
            folder = base / folder_name
            if folder.exists() and (folder / "опис.txt").exists():
                return folder
    return None


def parse_tree_from_text(text):
    if not text:
        return []
    lines = text.split('\n')
    found = []
    for line in lines:
        if HEADING_RE.match(line.strip()):
            content = line.split('\t', 1)[-1].strip() if '\t' in line else line
            content = re.sub(r'^[^\w]*', '', content)
            lower = content.lower()
            for kw, value in TREE_KEYWORDS:
                if kw in lower:
                    if value not in found:
                        found.append(value)
                    if value == 'mixed':
                        return ['mixed']
            return found
    return found


def months_to_season(months):
    if not months:
        return []
    result = []
    for season, mlist in MONTH_GROUPS.items():
        if any(m in months for m in mlist):
            result.append(season)
    return sorted(result, key=lambda s: list(MONTH_GROUPS.keys()).index(s))


def build_facets(species_list):
    cnt_tree = {}
    cnt_season = {}
    for sp in species_list:
        attrs = sp.get("attrs") or {}
        for v in (attrs.get("tree") or []):
            cnt_tree[v] = cnt_tree.get(v, 0) + 1
        for v in (attrs.get("season") or []):
            cnt_season[v] = cnt_season.get(v, 0) + 1

    tree_labels = {
        'pine': 'Сосна', 'spruce': 'Ялина', 'larch': 'Модрина', 'oak': 'Дуб',
        'birch': 'Береза', 'aspen': 'Осика', 'poplar': 'Тополя', 'willow': 'Верба',
        'alder': 'Вільха', 'hornbeam': 'Граб', 'beech': 'Бук', 'lime': 'Липа',
        'maple': 'Клен', 'elm': "В'яз", 'ash': 'Ясен', 'hazel': 'Ліщина',
        'chestnut': 'Каштан', 'mixed': 'Мішаний ліс', 'deciduous': 'Листяний ліс',
        'coniferous': 'Хвойний ліс', 'any': 'Будь-який ліс'
    }
    season_labels = {'spring': 'Весна', 'summer': 'Літо', 'autumn': 'Осінь', 'winter': 'Зима'}

    tree_order = [
        'pine', 'spruce', 'larch', 'oak', 'birch', 'aspen', 'poplar', 'willow',
        'alder', 'hornbeam', 'beech', 'lime', 'maple', 'elm', 'ash', 'hazel',
        'chestnut', 'mixed', 'deciduous', 'coniferous', 'any'
    ]

    def sort_key(item):
        value = item['value']
        if value in tree_order:
            return (0, tree_order.index(value))
        return (1, -item['count'])

    tree_facets = []
    for k, v in cnt_tree.items():
        tree_facets.append({'value': k, 'label': tree_labels.get(k, k), 'count': v})
    tree_facets.sort(key=sort_key)

    season_facets = []
    for k, v in cnt_season.items():
        season_facets.append({'value': k, 'label': season_labels.get(k, k), 'count': v})
    season_facets.sort(key=lambda x: list(MONTH_GROUPS.keys()).index(x['value']))

    return tree_facets, season_facets


def main():
    log("=== fill_tree_season.py ===")

    catalog = load_catalog()
    species = catalog["species"]
    log(f"[IN ] {len(species)} видів у каталозі")

    with_photo = [sp for sp in species if sp.get("has_photo")]
    log(f"[1] Види з фото: {len(with_photo)}")

    updated_tree = 0
    updated_season = 0
    skipped_no_folder = 0
    skipped_no_opis = 0
    tree_stats = {}
    season_stats = {}

    for sp in with_photo:
        sid = sp.get("id")
        name = sp.get("name", "")

        folder = find_opis_folder(sp)
        if not folder:
            skipped_no_folder += 1
            continue

        opis_path = folder / "опис.txt"
        if not opis_path.exists():
            skipped_no_opis += 1
            continue

        opis_text = opis_path.read_text(encoding="utf-8", errors="ignore")

        # tree
        tree_values = parse_tree_from_text(opis_text)
        attrs = sp.get("attrs") or {}
        old_tree = attrs.get("tree") or []
        if tree_values != old_tree:
            updated_tree += 1
            attrs["tree"] = tree_values
            sp["attrs"] = attrs
        for v in tree_values:
            tree_stats[v] = tree_stats.get(v, 0) + 1

        # season з months
        months = sp.get("months") or []
        season_values = months_to_season(months)
        old_season = attrs.get("season") or []
        if season_values != old_season:
            updated_season += 1
            attrs["season"] = season_values
            sp["attrs"] = attrs
        for v in season_values:
            season_stats[v] = season_stats.get(v, 0) + 1

    # Оновлюємо facets
    tree_facets, season_facets = build_facets(species)
    catalog["facets"] = {
        "color": catalog["facets"].get("color", []),
        "stem": catalog["facets"].get("stem", {"value": "", "label": "", "count": 0}),
        "tree": tree_facets,
        "season": season_facets
    }

    write_catalog(catalog)
    write_catalog_js(catalog)

    with_photo_after = [sp for sp in species if sp.get("has_photo")]
    tree_filled = sum(1 for sp in with_photo_after if sp.get("attrs") and sp["attrs"].get("tree") and sp["attrs"]["tree"])
    season_filled = sum(1 for sp in with_photo_after if sp.get("attrs") and sp["attrs"].get("season") and sp["attrs"]["season"])
    tree_empty = len(with_photo_after) - tree_filled
    season_empty = len(with_photo_after) - season_filled

    log(f"\n[2] Оновлено tree: {updated_tree}")
    log(f"[3] Оновлено season: {updated_season}")
    log(f"[4] Пропущено (немає папки): {skipped_no_folder}")
    log(f"[5] Пропущено (немає опис.txt): {skipped_no_opis}")

    log(f"\n[6] Після оновлення:")
    log(f"  tree заповнено: {tree_filled}")
    log(f"  tree порожньо: {tree_empty}")
    log(f"  season заповнено: {season_filled}")
    log(f"  season порожньо: {season_empty}")

    log(f"\n[7] Top-5 tree:")
    for k, v in sorted(tree_stats.items(), key=lambda x: -x[1])[:5]:
        log(f"  {k}: {v}")

    log(f"\n[8] Season розбивка:")
    for k in ['spring', 'summer', 'autumn', 'winter']:
        log(f"  {k}: {season_stats.get(k, 0)}")

    log(f"\nDone!")


if __name__ == "__main__":
    main()
