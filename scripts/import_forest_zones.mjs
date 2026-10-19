import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { Pool } from 'pg';
import fs from 'fs';
import path from 'path';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const DB_HOST = process.env.DB_HOST;
const DB_USER = process.env.DB_USER;
const DB_PASS = process.env.DB_PASS;
const DB_NAME = process.env.DB_NAME || 'postgres';

const CHUNK_SIZE = 500;
const GEOJSON_PATH = path.resolve(process.cwd(), 'kyiv_forests.geojson');

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set');
}
if (!DB_HOST || !DB_USER || !DB_PASS) {
  throw new Error('DB_HOST, DB_USER and DB_PASS must be set for PostGIS inserts');
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function classifyForestType(props = {}) {
  const wood = String(props.wood || '').toLowerCase();
  const species = String(props.species || '').toLowerCase();

  if (wood === 'coniferous' || species === 'pine') {
    return 'pine';
  }
  if (wood === 'deciduous') {
    return 'oak';
  }
  return 'mixed';
}

async function main() {
  console.log(`\u0417\u0447\u0438\u0442\u0430\u043d\u043d\u044f \u0424\u0430\u0439\u043b\u043e ${GEOJSON_PATH}...`);
  const raw = fs.readFileSync(GEOJSON_PATH, 'utf-8');
  const geojson = JSON.parse(raw);
  const originalCount = geojson.features?.length || 0;
  const features = (geojson.features || []).filter(
    f => f.geometry && (f.geometry.type === 'Polygon' || f.geometry.type === 'MultiPolygon')
  );
  const total = features.length;
  const skipped = originalCount - total;

  console.log(`\u0417\u043d\u0430\u0439\u0434\u043e ${total} \u043e\u0431'\u0454\u043a\u0442\u0456\u0432 \u0443 GeoJSON`);

  const pool = new Pool({
    host: DB_HOST,
    port: 6543,
    user: DB_USER,
    password: DB_PASS,
    database: DB_NAME,
    ssl: { rejectUnauthorized: false },
  });

  let processed = 0;

  try {
    for (let i = 0; i < features.length; i += CHUNK_SIZE) {
      const chunk = features.slice(i, i + CHUNK_SIZE);

      const valuesClauses = [];
      const params = [];

      chunk.forEach((f, ci) => {
        const base = ci * 5;
        const props = f.properties || {};
        const forestType = classifyForestType(props);
        const geomJson = JSON.stringify(f.geometry);

        valuesClauses.push(
          `(ST_Multi(ST_GeomFromGeoJSON($${base + 1})), $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5})`
        );
        params.push(geomJson, forestType, 'ndvi', 0.5, new Date().toISOString());
      });

      const sql = `
        INSERT INTO forest_zones (polygon, forest_type, stand_age_source, stand_age_confidence, created_at)
        VALUES ${valuesClauses.join(', ')}
      `;

      await pool.query(sql, params);

      processed += chunk.length;
      console.log(`\u041e\u0431\u0440\u043e\u0431\u043b\u0435\u043d\u043e ${processed} \u0437 ${total}`);
    }

    console.log(`\u0406\u043c\u043f\u043e\u0440\u0442 \u0437\u0430\u0432\u0435\u0440\u0448\u0435\u043d\u043e: ${processed} \u0437\u0430\u043f\u0438\u0441\u0456\u0432`);
    console.log(`\u041f\u0440\u043e\u043f\u0443\u0441\u043a\u043e \u043d\u0435\u043a\u043e\u0440\u0435\u043a\u0442\u043d\u0438\u0445 \u0433\u0435\u043e\u043c\u0435\u0442\u0440\u0456\u0439: ${skipped}`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error('\u041f\u043e\u043c\u0438\u043b\u043a\u0430 \u0456\u043c\u043f\u043e\u0440\u0442\u0443:', err);
  process.exit(1);
});
