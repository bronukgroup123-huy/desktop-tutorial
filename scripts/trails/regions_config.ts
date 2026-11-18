// Конфіг `osmium extract` — рамка кожної області з запасом ~5 км (щоб дорога за межею
// області теж вела додому). Env: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY.
//   deno run -A scripts/trails/regions_config.ts [--only <slug>] > extract.json

import { parseArgs } from "jsr:@std/cli@1/parse-args";

const args = parseArgs(Deno.args, { string: ["only", "dir"], default: { dir: "osm/regions" } });
const env = (n: string) => Deno.env.get(n) ?? (() => { throw new Error(`Missing env ${n}`); })();
async function api(path: string): Promise<unknown> {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(`${env("SUPABASE_URL")}/functions/v1/${path}`, { headers: { apikey: env("SUPABASE_PUBLISHABLE_KEY") } });
    if (res.ok) return await res.json();
    if (attempt >= 4 || (res.status < 500 && res.status !== 429)) throw new Error(`${path} → ${res.status}`);
    await new Promise((r) => setTimeout(r, 5_000 * attempt));
  }
}

const slugs = args.only ? [args.only] : ((await api("regions")) as { data: Array<{ slug: string }> }).data.map((r) => r.slug).sort();
const extracts = [];
for (const slug of slugs) {
  if (!/^[a-z0-9][a-z0-9_-]{1,39}$/.test(slug)) continue;
  const { data } = (await api(`v1-regions/${slug}/geometry?detail=low`)) as { data: { bbox?: number[] } };
  const b = data?.bbox;
  if (!b || b.length !== 4) continue;
  const m = 0.07;
  extracts.push({ output: `${slug}.osm.pbf`, bbox: [b[0] - m, b[1] - m * 0.65, b[2] + m, b[3] + m * 0.65] });
}
console.log(JSON.stringify({ directory: args.dir, extracts }, null, 2));
