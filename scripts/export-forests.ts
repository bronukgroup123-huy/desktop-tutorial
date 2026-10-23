import { createClient } from '@supabase/supabase-js';
import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

async function exportForests() {
  console.log('Connecting to Supabase...');
  
  // Try direct query first (more reliable than RPC)
  console.log('Querying forest_zones...');
  const { data, error } = await supabase
    .from('forest_zones')
    .select('id, polygon, forest_type, region_id, stand_age_years');
  
  if (error) {
    console.error('Query error:', error.message);
    process.exit(1);
  }
  
  if (!data || data.length === 0) {
    console.log('No data found in forest_zones');
    process.exit(1);
  }
  
  console.log(`Found ${data.length} forest zones`);
  
  // Convert to GeoJSON FeatureCollection
  const features = data.map(row => {
    // polygon might be a PostGIS geometry - need to convert to GeoJSON
    let geometry = row.polygon;
    
    // If polygon is a PostGIS geometry object, it might need ST_AsGeoJSON
    // But if it's already stored as GeoJSON, use as-is
    let geometryData = geometry;
    if (typeof geometry === 'string') {
      try {
        geometryData = JSON.parse(geometry);
      } catch {
        // Keep as-is if not valid JSON
      }
    }
    
    return {
      type: 'Feature',
      id: row.id,
      geometry: geometryData,
      properties: {
        id: row.id,
        forest_type: row.forest_type,
        region_id: row.region_id,
        stand_age_years: row.stand_age_years
      }
    };
  });
  
  const geojson = {
    type: 'FeatureCollection',
    features
  };
  
  writeGeoJSON(geojson);
}

function writeGeoJSON(geojson: any) {
  const outputPath = path.resolve(process.cwd(), 'web-guardian/public/data/forests.geojson');
  
  // Ensure directory exists
  const dir = path.dirname(outputPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  
  fs.writeFileSync(path.join(process.cwd(), 'web-guardian/public/data/forests.geojson'), JSON.stringify(geojson, null, 2));
  console.log(`GeoJSON written to web-guardian/public/data/forests.geojson`);
  console.log(`Features count: ${geojson.features?.length || 0}`);
}

exportForests().catch(console.error);