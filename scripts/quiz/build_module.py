#!/usr/bin/env python3
"""Модуль тестів знань (ADR-023): data/quiz/<module>.json → міграція + документ для читання власником.

    python3 scripts/quiz/build_module.py app 20261127110000
      → supabase/migrations/20261127110000_quiz_module_app.sql  (питання + publish модуля)
      → docs/quiz/app.md                                        (усі питання з відповідями й джерелами)

Перевіряє зміст: id, типи, правильні відповіді — серед варіантів, у «order» — усі варіанти,
у кожного питання є пояснення й джерело. Відповіді не підказують самі себе: варіант — до 40 символів,
правильна відповідь не найдовша (single), правильні не довші за всі хибні (multi), а в питаннях
«правда чи міф» трапляються обидві відповіді. Якщо в модулі є теми («topics»), кожне питання
належить одній із них, і в кожній темі вистачає питань на свою частку спроби («per_attempt»).
У модулях myths/twins правильна відповідь не може бути
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
MAX_OPTION_LEN = 40
EAT_OK = re.compile(r"(можна|варто|безпечно)\s+(їсти|куштувати|збирати\s+й\s+їсти)", re.I)


def fail(msg: str) -> None:
    sys.exit(f"✗ {msg}")


def topic_share(data: dict) -> int:
    """Скільки питань однієї теми потрапляє в спробу: per_attempt / кількість тем, з округленням угору."""
    topics = data.get("topics") or {}
    return -(-data["per_attempt"] // len(topics)) if topics else 0


def validate(data: dict) -> None:
    module = data["module"]
    per = data.get("per_attempt")
    if not isinstance(per, int) or not 1 <= per <= 30:
        fail("per_attempt — скільки питань у спробі, 1–30")
    topics = data.get("topics") or {}
    for t in topics:
        if not ID_RE.match(t) or len(t) > 40:
            fail(f"тема «{t}»: id — [a-z0-9_], до 40 символів")
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
        if topics and q.get("topic") not in topics:
            fail(f"{qid}: topic — одна з тем модуля {list(topics)}")
        if not topics and q.get("topic"):
            fail(f"{qid}: у модулі немає тем, а в питання є topic")
        for field in ("prompt", "explanation", "source"):
            if not str(q.get(field, "")).strip():
                fail(f"{qid}: порожнє «{field}»")
        texts = {o["id"]: o["text"].strip() for o in q["options"]}
        for t in texts.values():
            if not t or len(t) > MAX_OPTION_LEN:
                fail(f"{qid}: варіант — 1–{MAX_OPTION_LEN} символів, коротко й просто: «{t}»")
        wrong = [len(t) for o, t in texts.items() if o not in correct]
        if q["kind"] == "single" and len(opts) > 2 and len(texts[correct[0]]) > max(wrong):
            fail(f"{qid}: правильна відповідь найдовша — це підказка; вирівняйте варіанти")
        if q["kind"] == "multi" and wrong and min(len(texts[c]) for c in correct) > max(wrong):
            fail(f"{qid}: усі правильні довші за хибні — це підказка; вирівняйте варіанти")
        if module in DANGEROUS:
            for c in correct:
                text = next(o["text"] for o in q["options"] if o["id"] == c)
                if EAT_OK.search(text):
                    fail(f"{qid}: у модулі «{module}» правильна відповідь не може дозволяти їсти: «{text}»")
    published = len(data["questions"])
    if published < per:
        fail(f"питань {published}, а в спробі — {per}")
    for t, title in topics.items():
        n = sum(1 for q in data["questions"] if q.get("topic") == t)
        if n < topic_share(data):
            fail(f"тема «{title}»: {n} питань, а в спробу йде {topic_share(data)} — допишіть")
    # «правда чи міф»: якщо таких питань кілька, відповідь не має бути завжди однаковою
    tf = [q for q in data["questions"] if len(q["options"]) == 2 and q["kind"] == "single"]
    if len(tf) >= 3:
        answers = {next(o["text"] for o in q["options"] if o["id"] == q["correct"][0]) for q in tf}
        if len(answers) < 2:
            fail(f"питання з двома варіантами завжди мають відповідь «{answers.pop()}» — це підказка")


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
            sql_str(q["topic"]) if q.get("topic") else "NULL",
        ]) + ")")
    ids = ", ".join(sql_str(q["id"]) for q in data["questions"])
    return f"""-- ============================================================================
-- Тести знань: модуль «{data['title']}» ({module}) — ADR-023
-- ============================================================================
-- Згенеровано scripts/quiz/build_module.py з data/quiz/{module}.json; читабельна версія — docs/quiz/{module}.md.
-- Питання оновлюються (за id), прибрані з JSON — знімаються з публікації; модуль публікується.

INSERT INTO public.quiz_questions (id, module_id, kind, prompt, options, correct, explanation, source, critical, topic) VALUES
{',\n'.join(rows)}
ON CONFLICT (id) DO UPDATE SET
  kind = EXCLUDED.kind, prompt = EXCLUDED.prompt, options = EXCLUDED.options, correct = EXCLUDED.correct,
  explanation = EXCLUDED.explanation, source = EXCLUDED.source, critical = EXCLUDED.critical,
  topic = EXCLUDED.topic, published = true, hidden_by_reports = false, updated_at = now();

UPDATE public.quiz_questions SET published = false, updated_at = now()
WHERE module_id = {sql_str(module)} AND id NOT IN ({ids});

UPDATE public.quiz_modules SET published = true, questions_per_attempt = {data['per_attempt']} WHERE id = {sql_str(module)};
"""


def document(data: dict) -> str:
    kind_label = {"single": "одна відповідь", "multi": "оберіть усі правильні", "order": "розставте по порядку"}
    topics = data.get("topics") or {}
    total = len(data["questions"])
    if topics:
        how = (f"у спробі — {data['per_attempt']} питань із {total}: по {topic_share(data)} випадкових з кожної теми "
               f"({', '.join(topics.values())}); порядок питань і варіантів перемішується.")
    else:
        how = f"у спробі — {data['per_attempt']} випадкових питань із {total}, варіанти перемішуються."
    out = [f"# Модуль «{data['title']}»", "",
           f"Для читання власником перед публікацією (ADR-023 §23.3). Джерело змісту — `data/quiz/{data['module']}.json`; "
           + how, ""]
    groups = [(title, [q for q in data["questions"] if q.get("topic") == t]) for t, title in topics.items()] \
        if topics else [(None, data["questions"])]
    n = 0
    for title, qs in groups:
        if title:
            out += [f"# Тема: {title} ({len(qs)})", ""]
        for q in qs:
            n += 1
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
