#!/usr/bin/env python3
"""Модуль тестів знань (ADR-023): data/quiz/<module>.json → міграція + документ для читання власником.

    python3 scripts/quiz/build_module.py app 20261127110000
      → supabase/migrations/20261127110000_quiz_module_app.sql  (питання + publish модуля)
      → docs/quiz/app.md                                        (усі питання з відповідями й джерелами)

Перевіряє зміст: id, типи, правильні відповіді — серед варіантів, у «order» — усі варіанти,
у кожного питання є пояснення й джерело. У модулях myths/twins правильна відповідь не може бути
«можна їсти» (ADR-023 §23.2) — такі питання скрипт не пропустить.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ID_RE = re.compile(r"^[a-z0-9_]{1,60}$")
KINDS = {"single", "multi", "order"}
DANGEROUS = {"myths", "twins"}
EAT_OK = re.compile(r"(можна|варто|безпечно)\s+(їсти|куштувати|збирати\s+й\s+їсти)", re.I)


def fail(msg: str) -> None:
    sys.exit(f"✗ {msg}")


def validate(data: dict) -> None:
    module = data["module"]
    seen = set()
    for q in data["questions"]:
        qid = q["id"]
        if not ID_RE.match(qid) or not qid.startswith(module + "_"):
            fail(f"{qid}: id — [a-z0-9_], з префіксом «{module}_»")
        if qid in seen:
            fail(f"{qid}: повтор id")
        seen.add(qid)
        if q["kind"] not in KINDS:
            fail(f"{qid}: kind — {KINDS}")
        opts = [o["id"] for o in q["options"]]
        if len(opts) != len(set(opts)) or not 2 <= len(opts) <= 8:
            fail(f"{qid}: варіанти — 2–8 різних")
        correct = q["correct"]
        if not correct or any(c not in opts for c in correct):
            fail(f"{qid}: правильні відповіді мають бути серед варіантів")
        if q["kind"] == "single" and len(correct) != 1:
            fail(f"{qid}: single — рівно одна правильна")
        if q["kind"] == "order" and sorted(correct) != sorted(opts):
            fail(f"{qid}: order — правильна відповідь містить усі варіанти")
        for field in ("prompt", "explanation", "source"):
            if not str(q.get(field, "")).strip():
                fail(f"{qid}: порожнє «{field}»")
        if module in DANGEROUS:
            for c in correct:
                text = next(o["text"] for o in q["options"] if o["id"] == c)
                if EAT_OK.search(text):
                    fail(f"{qid}: у модулі «{module}» правильна відповідь не може дозволяти їсти: «{text}»")


def sql_str(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def migration(data: dict) -> str:
    module = data["module"]
    rows = []
    for q in data["questions"]:
        rows.append("  (" + ", ".join([
            sql_str(q["id"]), sql_str(module), sql_str(q["kind"]), sql_str(q["prompt"]),
            sql_str(json.dumps(q["options"], ensure_ascii=False)) + "::jsonb",
            sql_str(json.dumps(q["correct"], ensure_ascii=False)) + "::jsonb",
            sql_str(q["explanation"]), sql_str(q["source"]), "true" if q.get("critical") else "false",
        ]) + ")")
    ids = ", ".join(sql_str(q["id"]) for q in data["questions"])
    return f"""-- ============================================================================
-- Тести знань: модуль «{data['title']}» ({module}) — ADR-023
-- ============================================================================
-- Згенеровано scripts/quiz/build_module.py з data/quiz/{module}.json; читабельна версія — docs/quiz/{module}.md.
-- Питання оновлюються (за id), прибрані з JSON — знімаються з публікації; модуль публікується.

INSERT INTO public.quiz_questions (id, module_id, kind, prompt, options, correct, explanation, source, critical) VALUES
{',\n'.join(rows)}
ON CONFLICT (id) DO UPDATE SET
  kind = EXCLUDED.kind, prompt = EXCLUDED.prompt, options = EXCLUDED.options, correct = EXCLUDED.correct,
  explanation = EXCLUDED.explanation, source = EXCLUDED.source, critical = EXCLUDED.critical,
  published = true, hidden_by_reports = false, updated_at = now();

UPDATE public.quiz_questions SET published = false, updated_at = now()
WHERE module_id = {sql_str(module)} AND id NOT IN ({ids});

UPDATE public.quiz_modules SET published = true WHERE id = {sql_str(module)};
"""


def document(data: dict) -> str:
    kind_label = {"single": "одна відповідь", "multi": "оберіть усі правильні", "order": "розставте по порядку"}
    out = [f"# Модуль «{data['title']}»", "",
           f"Для читання власником перед публікацією (ADR-023 §23.3). Джерело змісту — `data/quiz/{data['module']}.json`; "
           f"у спробі — 10 випадкових питань із {len(data['questions'])}, варіанти перемішуються.", ""]
    for n, q in enumerate(data["questions"], 1):
        crit = " · **критичне**" if q.get("critical") else ""
        out.append(f"## {n}. {q['prompt']}")
        out.append(f"_{kind_label[q['kind']]}{crit} · `{q['id']}`_")
        out.append("")
        if q["kind"] == "order":
            text = {o["id"]: o["text"] for o in q["options"]}
            for i, c in enumerate(q["correct"], 1):
                out.append(f"{i}. {text[c]}")
        else:
            for o in q["options"]:
                mark = "✅" if o["id"] in q["correct"] else "▫️"
                out.append(f"- {mark} {o['text']}")
        out += ["", f"**Пояснення.** {q['explanation']}", "", f"**Джерело:** {q['source']}", ""]
    return "\n".join(out)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    module, stamp = sys.argv[1], sys.argv[2]
    data = json.loads((ROOT / "data/quiz" / f"{module}.json").read_text(encoding="utf-8"))
    if data["module"] != module:
        fail("module у файлі не збігається з назвою")
    validate(data)
    (ROOT / "supabase/migrations" / f"{stamp}_quiz_module_{module}.sql").write_text(migration(data), encoding="utf-8")
    (ROOT / "docs/quiz" / f"{module}.md").write_text(document(data), encoding="utf-8")
    print(f"✓ {module}: {len(data['questions'])} питань → міграція {stamp} і docs/quiz/{module}.md")


if __name__ == "__main__":
    main()
