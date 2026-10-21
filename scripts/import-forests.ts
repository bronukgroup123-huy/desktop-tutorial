import 'dotenv/config';
import fs from 'node:fs';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import JSONStream from 'JSONStream';

interface GeoJSONFeature {
  type: 'Feature';
  id: string;
  properties: FeatureProperties;
  geometry: Geometry | null;
}

interface FeatureProperties {
  landuse?: string;
  natural?: string;
  place?: string;
  id?: string;
  name?: string;
  'name:uk'?: string;
  [key: string]: string | undefined;
}

interface Geometry {
  type: 'Polygon' | 'LineString' | 'MultiPolygon' | string;
  coordinates: number[][][] | number[][];
}

interface ForestZoneInsert {
  osm_id: number | null;
  polygon: object;
  forest_type: string | null;
  region_id: number;
}

interface BatchResult {
  inserted: number;
  skipped: number;
}

interface ImportStats {
  total: number;
  inserted: number;
  skipped_lineString: number;
  skipped_not_forest: number;
  skipped_no_osm_id: number;
  skipped_invalid_geometry: number;
  errors: number;
}

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const KYIV_REGION_ID = process.env.KYIV_REGION_ID ? Number(process.env.KYIV_REGION_ID) : NaN;

const BATCH_SIZE = 500;
const PROGRESS_INTERVAL = 1000;
const MAX_RETRIES = 3;
const RETRY_BASE_DELAY_MS = 1000;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || Number.isNaN(KYIV_REGION_ID)) {
  console.error('Missing required env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, KYIV_REGION_ID');
  process.exit(1);
}

const supabase: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function extractOsmId(properties: FeatureProperties): number | null {
  if (!properties.id) return null;
  const match = properties.id.match(/^[a-z]+\/(\d+)$/i);
  if (!match) return null;
  const parsed = Number.parseInt(match[1], 10);
  return Number.isNaN(parsed) ? null : parsed;
}

function isForest(properties: FeatureProperties): boolean {
  if (properties.landuse === 'forest') return true;
  if (properties.natural === 'wood') return true;
  if (properties.place === 'islet' && !properties.landuse && !properties.natural) return false;
  if (!properties.landuse && !properties.natural && !properties.place) return false;
  return false;
}

function polygonToMultiPolygon(coords: number[][][]): object {
  return {
    type: 'MultiPolygon',
    coordinates: [coords],
  };
}

function validateGeometry(geometry: Geometry | null): boolean {
  if (!geometry) return false;
  if (geometry.type !== 'Polygon') return false;
  if (!Array.isArray(geometry.coordinates) || geometry.coordinates.length === 0) return false;
  const rings = geometry.coordinates as number[][][];
  if (rings.length === 0) return false;
  const outerRing = rings[0];
  if (!Array.isArray(outerRing) || outerRing.length < 4) return false;
  return true;
}

async function callRpcWithRetry(features: ForestZoneInsert[]): Promise<BatchResult> {
  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const { data, error } = await supabase.rpc('import_forest_zones_batch', {
        p_features: features,
      });

      if (error) {
        throw new Error(error.message);
      }

      const result = data as unknown as BatchResult;
      return { inserted: result.inserted ?? 0, skipped: result.skipped ?? 0 };
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      const delay = RETRY_BASE_DELAY_MS * 2 ** (attempt - 1);
      console.warn(`RPC attempt ${attempt}/${MAX_RETRIES} failed: ${lastError.message}. Retrying in ${delay}ms...`);
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw lastError ?? new Error('Unknown RPC error after retries');
}

async function main(): Promise<void> {
  console.log('Starting forest zones import...');
  console.log(`Batch size: ${BATCH_SIZE}, Progress interval: ${PROGRESS_INTERVAL}`);

  const stats: ImportStats = {
    total: 0,
    inserted: 0,
    skipped_lineString: 0,
    skipped_not_forest: 0,
    skipped_no_osm_id: 0,
    skipped_invalid_geometry: 0,
    errors: 0,
  };

  const fileStream = fs.createReadStream('/workspaces/desktop-tutorial/kyiv_forests.geojson', { encoding: 'utf8' });
  const parser = JSONStream.parse('features.*');
  const stream = fileStream.pipe(parser);

  let batch: ForestZoneInsert[] = [];
  let featureCount = 0;

  await new Promise<void>((resolve, reject) => {
    stream.on('data', async (feature: GeoJSONFeature) => {
      stream.pause();
      try {
        stats.total++;
        featureCount++;

        if (!feature.geometry) {
          stats.skipped_invalid_geometry++;
          stream.resume();
          return;
        }

        if (feature.geometry.type !== 'Polygon') {
          stats.skipped_lineString++;
          stream.resume();
          return;
        }

        if (!validateGeometry(feature.geometry)) {
          stats.skipped_invalid_geometry++;
          stream.resume();
          return;
        }

        if (!isForest(feature.properties)) {
          stats.skipped_not_forest++;
          stream.resume();
          return;
        }

        const osmId = extractOsmId(feature.properties);
        if (osmId === null) {
          stats.skipped_no_osm_id++;
          stream.resume();
          return;
        }

        const coords = feature.geometry.coordinates as number[][][];
        const polygon = polygonToMultiPolygon(coords);

        batch.push({
          osm_id: osmId,
          polygon,
          forest_type: null,
          region_id: KYIV_REGION_ID,
        });

        if (batch.length >= BATCH_SIZE) {
          try {
            const result = await callRpcWithRetry(batch);
            stats.inserted += result.inserted;
            stats.errors += result.skipped;
          } catch (err) {
            const errorMessage = err instanceof Error ? err.message : String(err);
            console.error(`Batch failed after retries: ${errorMessage}`);
            console.error(`Problematic osm_ids: ${batch.map((f) => f.osm_id).join(', ')}`);
            stats.errors += batch.length;
            reject(err);
            return;
          }
          batch = [];
        }

        if (featureCount % PROGRESS_INTERVAL === 0) {
          const pct = ((featureCount / 20807) * 100).toFixed(1);
          console.log(`Progress: ${featureCount}/20807 (${pct}%)`);
        }

        stream.resume();
      } catch (err) {
        reject(err);
      }
    });

    stream.on('end', () => {
      resolve();
    });

    stream.on('error', (err) => {
      reject(err);
    });
  });

  // Process remaining batch after stream ends
  if (batch.length > 0) {
    try {
      const result = await callRpcWithRetry(batch);
      stats.inserted += result.inserted;
      stats.errors += result.skipped;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      console.error(`Final batch failed after retries: ${errorMessage}`);
      console.error(`Problematic osm_ids: ${batch.map((f) => f.osm_id).join(', ')}`);
      stats.errors += batch.length;
      process.exit(1);
    }
  }

  console.log('\n=== Import Summary ===');
  console.log(`Total features:     ${stats.total}`);
  console.log(`Inserted:           ${stats.inserted}`);
  console.log(`Skipped LineString: ${stats.skipped_lineString}`);
  console.log(`Skipped not forest: ${stats.skipped_not_forest}`);
  console.log(`Skipped no OSM ID:  ${stats.skipped_no_osm_id}`);
  console.log(`Skipped invalid geom: ${stats.skipped_invalid_geometry}`);
  console.log(`Errors:             ${stats.errors}`);
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});