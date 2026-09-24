#!/usr/bin/env python3
"""
rebuild_facets.py

Перегенерує facets.tree, facets.season, facets.color, facets.stem
на основі реальних attrs видів з фото (has_photo: true).

Запуск: python3 scripts/rebuild_facets.py
"""

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG_JSON = ROOT / "mushroom_catalog.json"
CATALOG_JS = ROOT / "mushroom_catalog.js"

FACET_LABELS = {
    'tree': {
        'pine': 'Сосна', 'spruce': 'Ялина', 'larch': 'Модрина', 'oak': 'Дуб',
        'birch': 'Береза', 'aspen': 'Осика', 'poplar': 'Тополя', 'willow': 'Верба',
        'alder': 'Вільха', 'hornbeam': 'Граб', 'beech': 'Бук', 'elm': "В'яз",
        'hazel': 'Ліщина', 'mixed': 'Мішаний ліс', 'deciduous': 'Листяний ліс',
        'coniferous': 'Хвойний ліс', 'any': 'Будь-який ліс'
    },
    'season': {
        'spring': 'Весна', 'summer': 'Літо', 'autumn': 'Осінь', 'winter': 'Зима'
    },
    'color': {
        'white': 'Білий', 'brown': 'Коричневий', 'grey': 'Сірий', 'red': 'Червоний',
        'orange': 'Оранжевий', 'yellow': 'Жовтий', 'green': 'Зелений', 'pink': 'Рожевий',
        'black': 'Чорний', 'purple': 'Фіолетовий'
    },
    'stem': {
        'ring': 'З кільцем', 'no_ring': 'Без кільця'
    }
}


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
    header = "// mushroom_catalog.js\n// Автогенеровано scripts/rebuild_facets.py. Не редагувати вручну.\n"
    with open(CATALOG_JS, "w", encoding="utf-8") as f:
        f.write(header + "window.MUSHROOM_CATALOG = " + js_body + ";\n")
    kb = round(len(js_body.encode("utf-8")) / 1024.0, 1)
    log(f"[OUT] {CATALOG_JS.name} ({kb} KB)")


def build_facet_array(values_counter, labels, sort_by_count_desc=True):
    items = []
    for value, count in values_counter.items():
        if count <= 0:
            continue
        label = labels.get(value, value)
        items.append({'value': value, 'label': label, 'count': count})
    if sort_by_count_desc:
        items.sort(key=lambda x: x['count'], reverse=True)
    return items


def main():
    log("=== rebuild_facets.py ===")

    catalog = load_catalog()
    species = catalog["species"]
    log(f"[IN ] {len(species)} видів у каталозі")

    with_photo = [sp for sp in species if sp.get("has_photo")]
    log(f"[1] Види з фото: {len(with_photo)}")

    counters = {
        'tree': Counter(),
        'season': Counter(),
        'color': Counter(),
        'stem': Counter()
    }

    for sp in with_photo:
        attrs = sp.get("attrs") or {}
        for facet in ['tree', 'season', 'color', 'stem']:
            raw = attrs.get(facet)
            if isinstance(raw, list):
                vals = raw
            elif raw is None:
                vals = []
            else:
                vals = [raw]
            for v in vals:
                if v:
                    counters[facet][v] += 1

    facet_stats = {}
    new_facets = {}
    for facet in ['tree', 'season', 'color', 'stem']:
        arr = build_facet_array(counters[facet], FACET_LABELS[facet])
        new_facets[facet] = arr
        facet_stats[facet] = len(arr)
        log(f"[2] {facet}: {len(arr)} значень")

    catalog["facets"] = {
        "color": new_facets['color'],
        "stem": new_facets['stem'],
        "tree": new_facets['tree'],
        "season": new_facets['season']
    }

    write_catalog(catalog)
    write_catalog_js(catalog)

    log("\n[3] Top-5 по count за фасетами:")
    for facet in ['tree', 'season', 'color', 'stem']:
        arr = new_facets[facet]
        top5 = arr[:5]
        log(f"  {facet}:")
        for item in top5:
            log(f"    {item['value']}: {item['count']}")

    log("\n[4] Кількість значень у кожному фасеті:")
    for facet in ['tree', 'season', 'color', 'stem']:
        log(f"  {facet}: {facet_stats[facet]}")

    log("\nDone!")


if __name__ == "__main__":
    main()
