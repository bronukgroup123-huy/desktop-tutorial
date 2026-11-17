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
  - фото двійників (webp)/<вид>/   (лише CC0 / суспільне надбання — scripts/catalog_sync/fetch_free_photos.py)

Файли:
  - ліцензія*.txt / *license*.txt
  - посилання.txt / source.txt
"""

import json
import os
import re
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PHOTO_FOLDERS = [
    ("top20",   "фото Топ-20 грибів (webp)"),
    ("popular", "фото популярні 55 грибів (webp)"),
    ("red",     "Червона книга (webp)"),
    ("poison",  "Отруйні та смертельно отруйні (webp)"),
    ("twins",   "фото двійників (webp)"),
]

CATALOG_JSON = os.path.join(ROOT, "mushroom_catalog.json")
CATALOG_JS   = os.path.join(ROOT, "web-guardian", "public", "mushroom_catalog.js")


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
    """Файл ліцензії → кожен блок (порожній рядок між ними) — окремий автор зі своєю
    ліцензією й посиланнями: `credits`. Поля author/type/url/sources верхнього рівня — для
    сумісності (author — усі автори через «; », sources — усі посилання)."""
    raw = text.strip()
    if not raw:
        return None, False

    credits = []
    for block in re.split(r"\n\s*\n", raw):
        author = license_type = license_url = None
        sources = []
        in_sources = False
        for line in block.strip().splitlines():
            line = line.strip()
            if not line:
                in_sources = False
                continue
            if line.startswith("Фото:"):
                author = line.split(":", 1)[1].strip().rstrip(".")
                in_sources = False
            elif line.startswith("Ліцензія:"):
                payload = line.split(":", 1)[1].strip()
                if "—" in payload:
                    left, right = payload.split("—", 1)
                elif " - " in payload:
                    left, right = payload.split(" - ", 1)
                else:
                    left, right = payload, None
                license_type = left.strip() or None
                license_url = right.strip() if right else None
                in_sources = False
            elif line.startswith("Джерела:") or line.startswith("Джерело:"):
                in_sources = True
                # деякі файли мають URL одразу після мітки
                rest = line.split(":", 1)[1].strip()
                if rest.startswith(("http://", "https://")):
                    sources.append(rest)
            elif in_sources and line.startswith(("http://", "https://")):
                sources.append(line)
        if author or license_type or license_url or sources:
            credit = {"author": author, "type": license_type, "url": license_url, "sources": sources}
            credits.append({k: v for k, v in credit.items() if v})

    if not credits:
        return {"raw": raw}, False
    result = {"raw": raw, "credits": credits}
    authors = [c["author"] for c in credits if c.get("author")]
    if authors:
        result["author"] = "; ".join(dict.fromkeys(authors))
    first = credits[0]
    if first.get("type"):
        result["type"] = first["type"]
    if first.get("url"):
        result["url"] = first["url"]
    sources = [u for c in credits for u in c.get("sources", [])]
    if sources:
        result["sources"] = sources
    return result, True


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
    trailing = Path(path).read_bytes().endswith(b"\n") if Path(path).exists() else True
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + ("\n" if trailing else ""), encoding="utf-8")


def write_js(path, data):
    """Копія для веб-довідника — у тому ж форматі, що й scripts/catalog_sync/sync.py."""
    js = Path(path).read_text(encoding="utf-8")
    head = js[: js.index("window.MUSHROOM_CATALOG")]
    body = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</script", "<\\/script")
    Path(path).write_text(f"{head}window.MUSHROOM_CATALOG = {body};\n", encoding="utf-8")


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
                # Усі файли ліцензій папки (кожен може мати кількох авторів).
                texts = [read_utf8(f) for f in sorted(license_files)]
                text = "\n\n".join(t.strip() for t in texts if t)
                if text:
                    parsed, ok = parse_license(text)
                    if ok:
                        species["license"] = parsed
                        license_count += 1
                    else:
                        parse_failures += 1
                        log(f"  [WARN] Не вдалося розпарсити ліцензію: {sub}")

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
