"""Розбір книжкових описів грибів (web-guardian/public/mushroom_descriptions.js):
сезон («📅 Коли збирати?»), пік («наймасовіше…»), дерева («🌲 Де росте?»).

Місяці беруться В ПОРЯДКУ ЗАПИСУ, сезон може переходити через Новий рік:
«вересень — грудень, іноді до січня» → 9,10,11,12,1 (старий parse_season.py брав
min..max і отримував цілий рік).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DESC_FILE = ROOT / "web-guardian/public/mushroom_descriptions.js"

MONTHS = {
    "січ": 1, "лют": 2, "берез": 3, "квіт": 4, "трав": 5, "черв": 6,
    "лип": 7, "серп": 8, "верес": 9, "жовт": 10, "листопад": 11, "груд": 12,
}
# Повні словоформи, щоб «червоний» / «березовий» не ставали місяцями.
MONTH_RE = re.compile(
    r"\b(січ(?:ень|ня|ні)|лют(?:ий|ого|ому)|берез(?:ень|ня|ні)|квіт(?:ень|ня|ні)|трав(?:ень|ня|ні)|"
    r"черв(?:ень|ня|ні)|лип(?:ень|ня|ні)|серп(?:ень|ня|ні)|верес(?:ень|ня|ні)|жовт(?:ень|ня|ні)|"
    r"листопад(?:а|і)?|груд(?:ень|ня|ні))\b",
    re.IGNORECASE,
)
PEAK_RE = re.compile(r"(наймасовіш\w*|найбільше|пік)\b[^.]*", re.IGNORECASE)

TREES = [
    (r"сосн", "pine"), (r"ялин", "spruce"), (r"дуб(?!ов)|дубів|дубами|дібров", "oak"),
    (r"берез|беріз", "birch"), (r"осик|осич", "aspen"), (r"вільх", "alder"),
    (r"\bбук|буків|буками", "beech"), (r"граб", "hornbeam"),
    (r"хвойн", "coniferous"), (r"листян", "deciduous"), (r"мішан|змішан", "mixed"),
]


def month_num(word: str) -> int:
    w = word.lower()
    for k, v in MONTHS.items():
        if w.startswith(k):
            return v
    raise ValueError(word)


def ordered_range(text: str) -> list[int] | None:
    found = [month_num(m.group(1)) for m in MONTH_RE.finditer(text)]
    if not found:
        return None
    start, end = found[0], found[-1]
    if len(found) == 1:
        return [start]
    if end >= start:
        return list(range(start, end + 1))
    return list(range(start, 13)) + list(range(1, end + 1))  # через Новий рік


def field(desc: str, key: str) -> str | None:
    """Значення поля з табличного розділу «Де, коли…»: рядок «🌲 Де росте?\t…»
    або таблиця з заголовком «Де росте\tКоли збирати\t…» і рядком значень під ним."""
    lines = desc.split("\n")
    for line in lines:
        if key.lower() in line.lower() and "\t" in line:
            head, _, value = line.partition("\t")
            if key.lower() in head.lower() and value.strip() and key.lower() not in value.lower():
                return value.strip()
    for i, line in enumerate(lines):
        cols = line.split("\t")
        idx = next((j for j, c in enumerate(cols) if key.lower() in c.lower()), None)
        if idx is not None and len(cols) > 1 and i + 1 < len(lines):
            vals = lines[i + 1].split("\t")
            if idx < len(vals) and vals[idx].strip():
                return vals[idx].strip()
    return None


def season_days(text: str) -> tuple[int, int | None]:
    """День початку і кінця сезону з уточнень: «з середини квітня» → 15, «з кінця червня» → 20,
    «до середини жовтня» → 15, «до початку листопада» → 10. None — до кінця місяця."""
    found = list(MONTH_RE.finditer(text))
    if not found:
        return 1, None
    def qualifier(m: re.Match) -> str:
        return text[max(0, m.start() - 14): m.start()].lower()
    q0 = qualifier(found[0])
    start = 15 if "середин" in q0 else 20 if "кінц" in q0 else 10 if "початк" in q0 and "з початк" not in q0 else 1
    q1 = qualifier(found[-1]) if len(found) > 1 else ""
    end = 15 if "середин" in q1 else 10 if "початк" in q1 else None
    return start, end


def season(desc: str) -> tuple[list[int] | None, list[int] | None, str | None]:
    text = field(desc, "Коли збирати")
    if not text:
        return None, None, None
    peak = PEAK_RE.search(text)
    main = text[: peak.start()] if peak else text
    # Сезон — у першому реченні з місяцями («З початку червня до кінця вересня. Один з
    # найраніших — може з'являтися вже у травні» → червень–вересень, без «травня» з пояснення).
    first = next((s for s in re.split(r"(?<=[.!?])\s+", main) if MONTH_RE.search(s)), main)
    return ordered_range(first), (ordered_range(peak.group(0)) if peak else None), first


def trees(desc: str) -> tuple[list[str], str | None]:
    text = field(desc, "Де росте")
    if not text:
        return [], None
    low = text.lower()
    return sorted({code for pat, code in TREES if re.search(pat, low)}), text


def load() -> dict[str, str]:
    txt = DESC_FILE.read_text(encoding="utf-8")
    m = re.search(r"window\.MUSHROOM_DESCRIPTIONS\s*=\s*(\{.*?\});\s*$", txt, re.S)
    if not m:
        raise SystemExit(f"не вдалося прочитати {DESC_FILE}")
    # Ключі в описах — через дефіс, у довіднику й БД — через підкреслення.
    return {k.replace("-", "_"): v for k, v in json.loads(m.group(1)).items()}
