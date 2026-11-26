"""Markdown-опис таблиць public зі свіжої локальної БД (DOC-001).

  scripts/dev/local-db/run.sh --no-tests        # БД з усіх міграцій на порту 5498
  python3 scripts/dev/local-db/describe_tables.py <таблиця> [<таблиця> ...] > out.md

Колонки, типи, ключі, RLS і політики — з pg_catalog, тобто так, як їх створюють міграції.
"""
import json
import subprocess
import sys

tables = sys.argv[1:]
def q(sql):
    out = subprocess.run(['psql','-h','/tmp','-p','5498','-U','postgres','-d','postgres','-Atc',sql],capture_output=True,text=True,check=True).stdout
    return out.strip()
groups = [
 ('Користувачі й згоди', ['user_consents','user_trophies','rating_events']),
 ('Аналіз ділянки', ['analysis_forest_edits','analysis_history','gdd_state','weather_cache']),
 ('Сповіщення', ['push_devices','wave_alerts','air_alerts_cache']),
 ('Друзі', ['friendships','friend_request_log','user_reports']),
 ('Наглядач (ADR-022)', ['guardian_links','hikes','hike_guardians','hike_points','guardian_telegram','telegram_link_codes']),
 ('Ліміти запитів', ['ip_rate_limit','notification_rate_limit']),
]
known = {t for _, g in groups for t in g}
groups = [(title, [t for t in g if t in tables]) for title, g in groups]
groups.append(('Інше', [t for t in tables if t not in known]))
groups = [(title, g) for title, g in groups if g]
out = []
for title, ts in groups:
    out.append(f'### {title}\n')
    for t in ts:
        cols = json.loads(q(f"""select coalesce(json_agg(json_build_object('n',a.attname,'t',format_type(a.atttypid,a.atttypmod),'nn',a.attnotnull,
            'd',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum),'[]') from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
            where a.attrelid='public.{t}'::regclass and a.attnum>0 and not a.attisdropped"""))
        cons = q(f"select string_agg(pg_get_constraintdef(oid), ' | ' order by contype) from pg_constraint where conrelid='public.{t}'::regclass and contype in ('p','f','u')")
        rls = q(f"select relrowsecurity from pg_class where oid='public.{t}'::regclass")
        pol = q(f"select coalesce(string_agg(cmd||' '||array_to_string(roles,','), '; ' order by policyname),'') from pg_policies where schemaname='public' and tablename='{t}'")
        out.append(f'#### `{t}`\n')
        out.append('| Колонка | Тип | Обов\'язкова | За замовчуванням |')
        out.append('|---|---|---|---|')
        for c in cols:
            d = (c['d'] or '').replace('|','\\|')
            if len(d) > 40: d = d[:37] + '…'
            out.append(f"| `{c['n']}` | {c['t']} | {'так' if c['nn'] else ''} | {('`'+d+'`') if d else ''} |")
        keys = []
        for k in (cons or '').split(' | '):
            if not k: continue
            k = k.replace('|','\\|')
            keys.append(f'`{k}`')
        out.append('')
        if keys: out.append('Ключі: ' + '; '.join(keys) + '.')
        out.append('RLS: ' + ('увімкнено' if rls=='t' else '**вимкнено**') + ('; політики: ' + pol.replace('{','').replace('}','') if pol else '; політик немає — доступ лише service_role / SECURITY DEFINER-функцій') + '.\n')
print('\n'.join(out))
