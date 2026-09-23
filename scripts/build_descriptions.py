#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_descriptions.py

Збирає всі описи грибів у єдиний JS-об'єкт window.MUSHROOM_DESCRIPTIONS
і додає масив photos до mushroom_catalog.json / .js.

Джерела описів:
  - фото Топ-20 грибів (webp)/<вид>/опис.txt          (Формат A)
  - фото популярні 55 грибів (webp)/<вид>/опис.txt    (Формат A+)
  - Червона книга (webp)/<вид>/опис.txt               (Формат B)
  - Отруйні та смертельно отруйні (webp)/<вид>/опис.txt (Формат C)
  - list_200_detailed.txt                             (Формат D, 200 грибів без фото)

Пріоритет: опис.txt перемагає запис з list_200_detailed.txt.

Результат:
  - mushroom_descriptions.js - window.MUSHROOM_DESCRIPTIONS = {...}
  - mushroom_catalog.json    - додається поле photos[] (замінює photo)
  - mushroom_catalog.js      - той самий JSON в JS-обгортці
"""

import json
import os
import re
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PHOTO_FOLDERS = [
    ("top20",   "фото Топ-20 грибів (webp)"),
    ("popular", "фото популярні 55 грибів (webp)"),
    ("red",     "Червона книга (webp)"),
    ("poison",  "Отруйні та смертельно отруйні (webp)"),
]

LIST_200_PATH   = os.path.join(ROOT, "list_200_detailed.txt")
CATALOG_JSON    = os.path.join(ROOT, "mushroom_catalog.json")
CATALOG_JS      = os.path.join(ROOT, "mushroom_catalog.js")
DESCRIPTIONS_JS = os.path.join(ROOT, "mushroom_descriptions.js")

# Вирішення синонімів: папка з фото названа сучасною латиною,
# каталог - іншою. Розв'язуємо через українську назву.
SYNONYMS_BY_NAME = {
    "Дубовик звичайний":        "boletus-luridus",
    "Альбатрел злитий":         "albatrellus-confluens",
    "Підосичник білоніжковий":  "leccinum-albostipitatum",
    "Рядовка ліловонога":       "lepista-personata",
    "Рядовка фіолетова":        "lepista-nuda",
    "Скрипиця":                 "lactarius-vellereus",
    "Трутовик лускатий":        "polyporus-squamosus",
    "Хрящ-молочник перцевий":   "lactarius-piperatus",
}


def log(msg):
    print(msg, flush=True)


def load_catalog():
    with open(CATALOG_JSON, "r", encoding="utf-8") as f:
        return json.load(f)


def build_latin_index(catalog):
    idx = {}
    for s in catalog["species"]:
        latin = s.get("latin", "").strip().lower()
        if latin:
            idx[latin] = s
    return idx


def build_name_index(catalog):
    idx = {}
    for s in catalog["species"]:
        name = s.get("name", "").strip().lower()
        if name:
            idx[name] = s
    return idx


def build_id_index(catalog):
    return {s["id"]: s for s in catalog["species"]}


def match_species(folder_name, latin_index, name_index, id_index):
    """Папка 'Білий гриб Boletus edulis' або 'Amanita muscaria Мухомор червоний'."""
    clean = re.sub(r"\s+", " ", folder_name).strip()
    toks = clean.split()
    # 1) будь-яка пара двох токенів = латина
    for i in range(len(toks) - 1):
        cand = "{} {}".format(toks[i], toks[i + 1])
        hit = latin_index.get(cand.lower())
        if hit:
            return hit
    # 2) повне ім'я папки = українська назва
    hit = name_index.get(clean.lower())
    if hit:
        return hit
    # 3) синоніми: українська назва з SYNONYMS_BY_NAME є префіксом/рівність
    lower = clean.lower()
    for uk_name, sid in SYNONYMS_BY_NAME.items():
        if lower == uk_name.lower() or lower.startswith(uk_name.lower() + " "):
            return id_index.get(sid)
    # 4) інша українська назва з каталогу як префікс
    for name, s in name_index.items():
        if lower == name or lower.startswith(name + " "):
            return s
    return None
def sort_photos(files):
    """large.webp першим, потім large (1).webp, large (2).webp тощо."""
    def key(name):
        base = os.path.basename(name)
        if base == "large.webp":
            return (0, 0, "")
        m = re.match(r"^large\s*\((\d+)\)\.webp$", base, re.IGNORECASE)
        if m:
            return (1, int(m.group(1)), "")
        m = re.match(r"^large\s*\((\d+)\)_(\d+)\.webp$", base, re.IGNORECASE)
        if m:
            return (2, int(m.group(1)), int(m.group(2)))
        m = re.match(r"^large_(\d+)\.webp$", base, re.IGNORECASE)
        if m:
            return (3, int(m.group(1)), "")
        return (9, 0, base)
    return sorted(files, key=key)


def scan_photo_folders(catalog):
    """Повертає dict: species_id -> {text, folder_tag, photos[]}."""
    latin_index = build_latin_index(catalog)
    name_index = build_name_index(catalog)
    id_index = build_id_index(catalog)

    descriptions = {}
    unmatched = []

    for tag, folder_rel in PHOTO_FOLDERS:
        folder = os.path.join(ROOT, folder_rel)
        if not os.path.isdir(folder):
            log("[WARN] Папка не знайдена: " + folder_rel)
            continue

        for entry in sorted(os.listdir(folder)):
            folder_path = os.path.join(folder, entry)
            if not os.path.isdir(folder_path):
                continue
            files = os.listdir(folder_path)
            webps = [f for f in files if f.lower().endswith(".webp")]
            has_desc = "опис.txt" in files
            if not webps and not has_desc:
                continue

            species = match_species(entry, latin_index, name_index, id_index)
            if not species:
                unmatched.append((tag, entry))
                continue

            sid = species["id"]
            photos = []
            for w in sort_photos(webps):
                photos.append("{}/{}/{}".format(folder_rel, entry, w))

            text = ""
            if has_desc:
                try:
                    with open(os.path.join(folder_path, "опис.txt"), "r", encoding="utf-8") as f:
                        text = f.read().strip()
                except Exception as e:
                    log("[WARN] Помилка читання опису: " + str(e))

            if sid in descriptions and not text and descriptions[sid].get("text"):
                continue

            descriptions[sid] = {
                "text": text,
                "photos": photos,
                "folder_tag": tag,
            }

    if unmatched:
        log("[WARN] Не підібрано папок: " + str(len(unmatched)))
        for tag, entry in unmatched[:15]:
            log("  - [" + tag + "] " + entry)
    return descriptions

ENTRY_SPLIT = re.compile(r"(?m)^\s*(\d+)\.\s*\U0001f344\s*")  # 🍄


def parse_list_200():
    """Повертає список (num, name, latin, body)."""
    with open(LIST_200_PATH, "r", encoding="utf-8") as f:
        txt = f.read()

    parts = ENTRY_SPLIT.split(txt)
    entries = []
    for i in range(1, len(parts), 2):
        num = parts[i]
        content = parts[i + 1] if i + 1 < len(parts) else ""
        lines = [l for l in content.split("\n") if l.strip()]
        if not lines:
            continue
        first = lines[0].strip()

        m = re.match(r"^([^()]+?)\s*\(([^()]+)\)\s*$", first)
        if m and re.match(r"^[A-Z][a-z]+\s+[a-z]+", m.group(2).strip()):
            name = m.group(1).strip()
            latin = m.group(2).strip()
            body = "\n".join(lines[1:])
        else:
            name = first
            latin = lines[1].strip() if len(lines) > 1 else ""
            body = "\n".join(lines[2:])

        entries.append((num, name, latin, body))
    return entries


def merge_list_200(accumulated, catalog):
    """Додаємо описи без фото, якщо їх немає в accumulated."""
    latin_index = build_latin_index(catalog)

    added = 0
    skipped_dup = 0
    unmatched = []

    for num, name, latin, body in parse_list_200():
        hit = latin_index.get(latin.lower().strip())
        if not hit:
            unmatched.append((num, name, latin))
            continue
        sid = hit["id"]
        if sid in accumulated and accumulated[sid].get("text"):
            skipped_dup += 1
            continue
        photos = accumulated.get(sid, {}).get("photos", [])
        accumulated[sid] = {
            "text": body.strip(),
            "photos": photos,
            "folder_tag": "list_200",
        }
        added += 1

    if unmatched:
        log("[WARN] Не підібрано в list_200: " + str(len(unmatched)))
        for u in unmatched[:10]:
            log("  - " + str(u))
    log("[list_200] Додано: " + str(added) + ", пропущено дублікатів: " + str(skipped_dup))
    return accumulated

def update_catalog(catalog, descriptions):
    """Замінюємо photo (рядок) на photos (масив шляхів)."""
    for s in catalog["species"]:
        sid = s.get("id")
        entry = descriptions.get(sid, {})
        photos = entry.get("photos", []) or []
        if not photos:
            old = s.get("photo")
            if old:
                photos = [old]
        if "photo" in s:
            del s["photo"]
        s["photos"] = photos
        s["has_photo"] = len(photos) > 0

    with_photos = sum(1 for s in catalog["species"] if s.get("has_photo"))
    catalog["meta"]["with_photos"] = with_photos
    catalog["meta"]["generated"] = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S")
    return with_photos


def write_catalog(catalog):
    pretty = json.dumps(catalog, ensure_ascii=False, indent=4)
    with open(CATALOG_JSON, "w", encoding="utf-8") as f:
        f.write(pretty)
    kb = round(len(pretty.encode("utf-8")) / 1024.0, 1)
    log("[OUT] " + CATALOG_JSON + " (" + str(kb) + " KB)")
    safe = pretty.replace("</script", r"\<\/script")
    return safe


def write_catalog_js(safe_json):
    header = ("// mushroom_catalog.js\n"
              "// Автогенеровано scripts/build_descriptions.py з mushroom_catalog.json.\n"
              "// Не редагувати вручну.\n")
    content = header + "window.MUSHROOM_CATALOG = " + safe_json + ";\n"
    with open(CATALOG_JS, "w", encoding="utf-8") as f:
        f.write(content)
    kb = round(len(content.encode("utf-8")) / 1024.0, 1)
    log("[OUT] " + CATALOG_JS + " (" + str(kb) + " KB)")


def write_descriptions_js(descriptions):
    """JSON-серіалізація екранує всі спецсимвoli автоматично."""
    obj = {}
    for sid, entry in sorted(descriptions.items()):
        text = entry.get("text", "")
        if not text:
            continue
        obj[sid] = text

    body = json.dumps(obj, ensure_ascii=False, indent=2)
    body = body.replace("</script", r"\<\/script")
    content = ("// mushroom_descriptions.js\n"
               "// Автогенеровано scripts/build_descriptions.py.\n"
               "// Джерела: папки фото/*webp*/опис.txt та list_200_detailed.txt\n"
               "// Ключ - species.id з mushroom_catalog.json. Значення - сирий текст опису.\n"
               "window.MUSHROOM_DESCRIPTIONS = " + body + ";\n")
    with open(DESCRIPTIONS_JS, "w", encoding="utf-8") as f:
        f.write(content)
    kb = round(len(content.encode("utf-8")) / 1024.0, 1)
    log("[OUT] " + DESCRIPTIONS_JS + " (" + str(kb) + " KB, записів: " + str(len(obj)) + ")")


def main():
    log("=== build_descriptions.py ===")

    catalog = load_catalog()
    log("[IN ] " + str(len(catalog["species"])) + " видів у каталозі")

    log("[1] Сканирую папки з фото...")
    descriptions = scan_photo_folders(catalog)
    log("[1] Описів з папок: " + str(len(descriptions)))

    if os.path.exists(LIST_200_PATH):
        log("[2] Додаю list_200_detailed.txt...")
        descriptions = merge_list_200(descriptions, catalog)
        log("[2] Загалом записів: " + str(len(descriptions)))
    else:
        log("[WARN] Не знайдено: " + LIST_200_PATH)

    log("[3] Оновлюю каталог (photo -> photos)...")
    with_photos = update_catalog(catalog, descriptions)
    log("[3] Видів з фото: " + str(with_photos))

    safe = write_catalog(catalog)
    write_catalog_js(safe)
    write_descriptions_js(descriptions)

    total_desc = sum(1 for e in descriptions.values() if e.get("text"))
    total_photo = sum(1 for e in descriptions.values() if e.get("photos"))
    log("[DONE] Описів: " + str(total_desc) + " | З фото: " + str(total_photo))


if __name__ == "__main__":
    main()

