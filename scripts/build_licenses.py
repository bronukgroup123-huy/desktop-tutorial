#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_licenses.py

Збирає ліцензії та джерела Червоной книги з текстових файлів у папках з фото
і додає їх до mushroom_catalog.json / mushroom_catalog.js.

Скановує:
  - фото Топ-20 грибів (webp)/<вид>/
  - фото популярні 55 грибів (webp)/<вид>/
  - Червона книга (webp)/<вид>/
  - Отруйні та смертельно отруйні (webp)/<вид>/

Файли:
  - ліцензія*.txt / *license*.txt
  - посилання.txt / source.txt
"""

import json
import os
import re
from datetime import datetime
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PHOTO_FOLDERS = [
    ("top20",   "фото Топ-20 грибів (webp)"),
    ("popular", "фото популярні 55 грибів (webp)"),
    ("red",     "Червона книга (webp)"),
    ("poison",  "Отруйні та смертельно отруйні (webp)"),
]

CATALOG_JSON = os.path.join(ROOT, "mushroom_catalog.json")
CATALOG_JS   = os.path.join(ROOT, "mushroom_catalog.js")


def log(msg):
    print(msg, flush=True)


def load_catalog():
    with open(CATALOG_JSON, "r", encoding="utf-8") as f:
        return json.load(f)


def build_photo_prefix_index(catalog):
    idx = {}
    for s in catalog["species"]:
        photos = s.get("photos") or []
        if photos:
            idx[photos[0]] = s["id"]
    return idx


def match_species(folder_name, photo_prefix_index):
    for photo, sid in photo_prefix_index.items():
        if folder_name in photo:
            return sid
    return None


def read_utf8(path):
    try:
        return path.read_text(encoding="utf-8")
    except Exception as e:
        log(f"  [WARN] Не вдалося прочитати {path}: {e}")
        return None


def parse_license(text):
    raw = text.strip()
    if not raw:
        return None, False

    result = {"raw": raw}
    author = None
    license_type = None
    license_url = None
    sources = []
    first_block_done = False

    blocks = re.split(r"\n\s*\n", raw)
    for block in blocks:
        lines = block.strip().splitlines()
        block_author = None
        block_type = None
        block_url = None
        block_sources = []
        in_sources = False

        for line in lines:
            line = line.strip()
            if not line:
                in_sources = False
                continue
            if line.startswith("Фото:"):
                block_author = line.split(":", 1)[1].strip()
                in_sources = False
            elif line.startswith("Ліцензія:"):
                payload = line.split(":", 1)[1].strip()
                if "—" in payload:
                    left, right = payload.split("—", 1)
                elif "-" in payload:
                    left, right = payload.split("-", 1)
                else:
                    left, right = payload, None
                block_type = left.strip() or None
                block_url = right.strip() if right else None
                in_sources = False
            elif line.startswith("Джерела:") or line.startswith("Джерело:"):
                in_sources = True
                # some files put URL right after the marker on the same line
                rest = line.split(":", 1)[1].strip()
                if rest and (rest.startswith("http://") or rest.startswith("https://")):
                    block_sources.append(rest)
            elif in_sources and (line.startswith("http://") or line.startswith("https://")):
                block_sources.append(line)

        if not first_block_done:
            if block_author:
                author = block_author
            if block_type:
                license_type = block_type
            if block_url:
                license_url = block_url
            if block_author or block_type or block_url or block_sources:
                first_block_done = True
        sources.extend(block_sources)

    if author is not None:
        result["author"] = author.rstrip(".")
    if license_type is not None:
        result["type"] = license_type
    if license_url is not None:
        result["url"] = license_url
    if sources:
        result["sources"] = sources

    parsed = bool(author or license_type or license_url or sources)
    return result, parsed


def parse_source(text):
    raw = text.strip()
    if not raw:
        return None, False

    result = {"raw": raw}
    parsed = False

    m = re.search(r"Джерело:\s*(.+?)URL:\s*(.+)", raw, re.DOTALL)
    if m:
        text_part = m.group(1).strip()
        url_part = m.group(2).strip()
        result["text"] = text_part
        if url_part:
            result["url"] = url_part
            parsed = True
        else:
            parsed = bool(text_part)
    else:
        result["text"] = raw
        parsed = True

    return result, parsed


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)


def write_js(path, data):
    meta = data.get("meta", {})
    # keep generated updated
    meta["generated"] = datetime.now().isoformat(timespec="seconds")
    data["meta"] = meta
    js = "// mushroom_catalog.js\n// Автогенеровано build_licenses.py з mushroom_catalog.json.\n// Не редагувати вручну.\nwindow.MUSHROOM_CATALOG = " + json.dumps(data, ensure_ascii=False, indent=4) + ";\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(js)


def main():
    log("Завантаження каталогу...")
    catalog = load_catalog()
    photo_prefix_index = build_photo_prefix_index(catalog)
    species_index = {s["id"]: s for s in catalog["species"]}

    license_count = 0
    redbook_count = 0
    parse_failures = 0
    unmatched = []

    for key, folder_name in PHOTO_FOLDERS:
        root = Path(ROOT) / folder_name
        if not root.exists():
            log(f"[SKIP] Папка не знайдена: {root}")
            continue

        for sub in sorted(root.iterdir()):
            if not sub.is_dir():
                continue

            files = {f.name: f for f in sub.iterdir() if f.is_file()}
            license_files = [f for n, f in files.items() if "ліцензі" in n.lower() or "license" in n.lower()]
            source_files = [f for n, f in files.items() if n.lower() in {"посилання.txt", "source.txt"}]

            if not license_files and not source_files:
                continue

            sid = match_species(sub.name, photo_prefix_index)
            if sid is None:
                unmatched.append(str(sub))
                continue

            species = species_index[sid]

            if license_files:
                text = read_utf8(license_files[0])
                if text is not None:
                    parsed, ok = parse_license(text)
                    if ok:
                        species["license"] = parsed
                        license_count += 1
                    else:
                        parse_failures += 1
                        log(f"  [WARN] Не вдалося розпарсити ліцензію: {license_files[0]}")

            if source_files:
                text = read_utf8(source_files[0])
                if text is not None:
                    parsed, ok = parse_source(text)
                    if ok:
                        species["red_book_source"] = parsed
                        redbook_count += 1
                    else:
                        parse_failures += 1
                        log(f"  [WARN] Не вдалося розпарсити джерело: {source_files[0]}")

    log(f"\nСтатистика:")
    log(f"  Видів з ліцензією: {license_count}")
    log(f"  Видів з джерелом ЧК: {redbook_count}")
    log(f"  Не розпарсено файлів: {parse_failures}")
    log(f"  Папок без збігу в каталозі: {len(unmatched)}")
    for u in unmatched:
        log(f"    {u}")

    log("\nЗбереження mushroom_catalog.json...")
    write_json(CATALOG_JSON, catalog)
    log("Збереження mushroom_catalog.js...")
    write_js(CATALOG_JS, catalog)
    log("Готово.")


if __name__ == "__main__":
    main()
