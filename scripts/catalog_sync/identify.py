"""«Як відрізнити» з книжкових описів (рішення PO 2026-11-15).

Розбирає «🔍 Швидка картка (як визначити)» і «⚠️ Обережно, двійники!» для 20 видів рушія
й генерує supabase/functions/_shared/v1/identify-data.ts: короткі (один рядок) ознаки шапки,
низу шапки, ніжки, кольори шапки, кільце, найнебезпечніший двійник з 2–3 відмінностями і
головне правило. Тексти — з книги, лише скорочені до першого речення / до коми.

Запуск: python3 scripts/catalog_sync/identify.py [--write]
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import books  # noqa: E402
from sync import FORESTS  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "supabase/functions/_shared/v1/identify-data.ts"
MAX = 72

COLORS = [
    (r"темно-коричн|темно-каштан|чорно-коричн|каштанов", "#5d3a1a"),
    (r"світло-коричн|горіх", "#b07d4b"),
    (r"медов", "#d9a441"),
    (r"яєчно-жовт|жовт", "#e6c03a"),
    (r"оранж|руд", "#e0802c"),
    (r"цегля", "#c0583a"),
    (r"червон", "#c0392b"),
    (r"рожев", "#e3a0a8"),
    (r"вохр", "#c9a15b"),
    (r"олив", "#8a8f3c"),
    (r"зелен", "#6b8e23"),
    (r"коричн|бур|каштан", "#8b5a2b"),
    (r"сір", "#9e9e9e"),
    (r"кремов", "#efe2c4"),
    (r"біл", "#f3efe6"),
    (r"чорн", "#333333"),
]

COLOR_NAME = {
    "#5d3a1a": "темно-коричневий", "#b07d4b": "світло-коричневий", "#d9a441": "медовий",
    "#e6c03a": "жовтий", "#e0802c": "оранжевий", "#c0583a": "цегляний", "#c0392b": "червоний",
    "#e3a0a8": "рожевий", "#c9a15b": "вохристий", "#8a8f3c": "оливковий", "#6b8e23": "зеленуватий",
    "#8b5a2b": "коричневий", "#9e9e9e": "сірий", "#efe2c4": "кремовий", "#f3efe6": "білий", "#333333": "чорний",
}

UNDERSIDE = {"трубочки": "tubes", "трубчаст": "tubes", "пластинки": "gills", "складки": "folds", "шипи": "spines"}


def short(text: str, limit: int = MAX) -> str:
    """Перше речення; задовге — до останньої коми в межах [limit]."""
    t = re.sub(r"\s+", " ", text).strip()
    t = re.split(r"(?<=[.!?])\s", t)[0].rstrip(".")
    if len(t) <= limit:
        return t
    cut = t[:limit]
    i = max(cut.rfind(","), cut.rfind(";"), cut.rfind(" —"))
    return (cut[:i] if i > 25 else cut[: cut.rfind(" ")]).rstrip(",; —") + "…"


def sentence_with(text: str, pattern: str) -> str | None:
    for s in re.split(r"(?<=[.!?])\s", re.sub(r"\s+", " ", text)):
        if re.search(pattern, s, re.IGNORECASE):
            return s.strip().rstrip(".")
    return None


def section(desc: str, start: str, end_marks: list[str]) -> str:
    i = desc.find(start)
    if i < 0:
        return ""
    j = min([k for k in (desc.find(m, i + len(start)) for m in end_marks) if k > 0] or [len(desc)])
    return desc[i + len(start): j]


def quick_card(desc: str) -> dict[str, str]:
    sec = section(desc, "Швидка картка", ["⚠️ Обережно, двійники", "🗺️"])
    out: dict[str, str] = {}
    for line in sec.split("\n"):
        m = re.match(r"\s*([^:\n]{3,40}):\s*(.+)", line)
        if m:
            out[m.group(1).strip()] = m.group(2).strip()
    return out


def cap_colors(text: str) -> list[dict[str, str]]:
    s = sentence_with(text, r"^Колір") or text
    s = s.split("—", 1)[-1] if "—" in s else s
    found: list[tuple[int, str, str]] = []
    for pat, hexv in COLORS:
        for m in re.finditer(pat, s, re.IGNORECASE):
            if any(abs(m.start() - p) < 3 for p, _, _ in found):
                continue
            word = re.match(r"[\w'’-]+", s[m.start():]).group(0)
            found.append((m.start(), hexv, word))
            break
    found.sort()
    seen, out = set(), []
    for _, hexv, word in found:
        if hexv in seen:
            continue
        seen.add(hexv)
        out.append({"hex": hexv, "label": COLOR_NAME[hexv]})
    return out[:3]


def twin_table(desc: str) -> tuple[list[str], list[list[str]]]:
    sec = section(desc, "Обережно, двійники", ["🗺️"])
    lines = sec.split("\n")
    head_i = next((i for i, l in enumerate(lines) if l.startswith("Ознака\t")), None)
    if head_i is None:
        return [], []
    head = lines[head_i].split("\t")
    rows = []
    for l in lines[head_i + 1:]:
        if "\t" not in l:
            break
        rows.append(l.split("\t"))
    return head, rows


def clean_name(n: str) -> str:
    return re.sub(r"\s*\([^)]*\)", "", n).strip()


def danger(cell: str) -> int:
    c = cell.lower()
    if "смертельно" in c:
        return 3
    if "отруйн" in c and "не отруйн" not in c:
        return 2
    if "неїстівн" in c or "зіпсує" in c or "не отруйн" in c:
        return 1
    return 0


def twin(desc: str) -> dict | None:
    head, rows = twin_table(desc)
    if len(head) < 3:
        return None
    edible = next((r for r in rows if r[0].strip().lower().startswith("їстівн")), None)
    cols = list(range(2, len(head)))
    if edible:
        cols.sort(key=lambda c: -danger(edible[c] if c < len(edible) else ""))
    c = cols[0]
    level = danger(edible[c]) if edible and c < len(edible) else 0
    diffs = []
    prio = ["кільце", "низ", "пластинки", "складки", "трубчаст", "сітка", "шапка", "м'якоть", "м’якоть", "ніжка", "сік", "смак", "колір"]
    useful = [r for r in rows if len(r) > c and r[0].strip().lower() not in ("їстівність", "спори", "розмір")
              and r[1].strip() not in ("—", "") and r[c].strip() not in ("—", "")]
    useful.sort(key=lambda r: next((i for i, p in enumerate(prio) if p in r[0].lower()), 99))
    for r in useful[:3]:
        diffs.append({"feature": r[0].strip(), "ours": short(r[1], 40), "twin": short(r[c], 40)})
    if not diffs:
        return None
    return {
        "name": clean_name(head[c]),
        "danger": ["similar", "inedible", "poisonous", "deadly"][level],
        "danger_label": ["Схожий вид", "Неїстівний", "Отруйний!", "Смертельно отруйний!"][level],
        "diffs": diffs,
    }


def rule(desc: str) -> str | None:
    sec = section(desc, "Обережно, двійники", ["🗺️"])
    for key in ("Головне правило:", "Головна відмінність:", "Важливо:"):
        i = sec.find(key)
        if i >= 0:
            t = short(sec[i + len(key):], 110)
            return t[0].upper() + t[1:] if t else None
    return None


def build(mt: str, desc: str) -> dict | None:
    q = quick_card(desc)
    if not q:
        return None
    feats = []
    cap = q.get("Шапка")
    if cap:
        # Колір показують кружечки — у тексті форма й розмір (перше речення книги).
        feats.append({"part": "cap", "title": "Шапка", "text": short(cap)})
    under_key = next((k for k in q if k.lower().startswith(("низ шапки", "пластинки", "трубочки", "складки"))), None)
    kind = None
    if under_key:
        low = under_key.lower()
        kind = next((v for k, v in UNDERSIDE.items() if k in low), None)
        title = {"tubes": "Трубочки", "gills": "Пластинки", "folds": "Складки", "spines": "Шипи"}.get(kind, "Низ шапки")
        # «Головна відмінність!» — заголовок, а не опис: беремо наступне речення.
        text = re.sub(r"^\s*Головна відмінність!\s*", "", q[under_key])
        feats.append({"part": "underside", "kind": kind, "title": title, "text": short(text)})
    stem = q.get("Ніжка")
    if stem:
        key = sentence_with(stem, r"Головна ознака")
        text = key.split(":", 1)[1].strip() if key and ":" in key else (key or stem)
        feats.append({"part": "stem", "title": "Ніжка", "text": short(text[0].upper() + text[1:])})
    flesh = q.get("М'якоть") or q.get("М’якоть")
    if flesh:
        key = sentence_with(flesh, r"зріз|злам|Головна ознака")
        feats.append({"part": "flesh", "title": "М'якоть", "text": short(key or flesh)})
    # Кільце: таблиця двійників (✅/❌ у нашій колонці) або опис ніжки.
    ring = None
    head, rows = twin_table(desc)
    for r in rows:
        if "кільце" in r[0].lower() and len(r) > 1:
            cell = r[1].lower()
            ring = False if ("❌" in r[1] or "відсутн" in cell or "немає" in cell) else True
    if ring is None and stem:
        if re.search(r"без кільця|кільця немає", stem, re.IGNORECASE):
            ring = False
        elif re.search(r"кільц", stem, re.IGNORECASE):
            ring = True
    return {
        "features": feats,
        "cap_colors": cap_colors(cap or ""),
        "underside": kind,
        "ring": ring,
        "twin": twin(desc),
        "rule": rule(desc),
    }


def main(write: bool) -> None:
    descs = books.load()
    data = {}
    for mt in FORESTS:
        card = build(mt, descs.get(mt, ""))
        if card:
            data[mt] = card
        print(f"== {mt}")
        print(json.dumps(card, ensure_ascii=False, indent=1)[:1500] if card else "  (немає швидкої картки)")
    if write:
        body = json.dumps(data, ensure_ascii=False, indent=2)
        OUT.write_text(
            "// Автогенеровано scripts/catalog_sync/identify.py з книжкових описів — не редагувати вручну.\n"
            "// «Як відрізнити» (рішення PO 2026-11-15): ознаки, кольори шапки, кільце, двійник, правило.\n\n"
            "export interface IdentifyCard {\n"
            "  features: Array<{ part: string; title: string; text: string; kind?: string | null }>;\n"
            "  cap_colors: Array<{ hex: string; label: string }>;\n"
            "  underside: string | null;\n"
            "  ring: boolean | null;\n"
            "  twin: {\n"
            "    name: string;\n"
            "    danger: string;\n"
            "    danger_label: string;\n"
            "    diffs: Array<{ feature: string; ours: string; twin: string }>;\n"
            "  } | null;\n"
            "  rule: string | null;\n"
            "}\n\n"
            f"export const IDENTIFY: Record<string, IdentifyCard> = {body};\n",
            encoding="utf-8",
        )
        print(f"→ {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main("--write" in sys.argv)
