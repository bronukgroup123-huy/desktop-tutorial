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
  
  console.log('Querying forest_zones (fetching ALL records)...');
  
  const PAGE_SIZE = 1000;
  let allData: any[] = [];
  let from = 0;
  let hasMore = true;

  while (hasMore) {
    console.log(`Fetching records ${from} to ${from + PAGE_SIZE - 1}...`);
    
    const { data, error } = await supabase
      .from('forest_zones')
      .select('id, polygon, forest_type, region_id, stand_age_years')
      .range(from, from + PAGE_SIZE - 1);
    
    if (error) {
      console.error('Query error:', error.message);
      process.exit(1);
    }
    
    if (!data || data.length === 0) {
      hasMore = false;
      break;
    }
    
    allData = allData.concat(data);
    console.log(`Fetched ${data.length} records (total: ${allData.length})`);
    
    if (data.length < PAGE_SIZE) {
      hasMore = false;
    } else {
      from += PAGE_SIZE;
    }
  }
  
  if (allData.length === 0) {
    console.log('No data found in forest_zones');
    process.exit(1);
  }
  
  console.log(`Total records fetched: ${allData.length}`);
  
  // Convert to GeoJSON FeatureCollection
  const features = allData.map(row => {
    let geometry = row.polygon;
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
  
  // Write to public/data/forests.geojson for static serving
  const publicDataPath = path.resolve(process.cwd(), 'web-guardian/public/data/forests.geojson');
  const publicDataDir = path.dirname(publicDataPath);
  if (!fs.existsSync(publicDataDir)) {
    fs.mkdirSync(publicDataDir, { recursive: true });
  }
  fs.writeFileSync(publicDataPath, JSON.stringify(geojson));
  console.log(`GeoJSON written to web-guardian/public/data/forests.geojson`);
  console.log(`Features count: ${geojson.features.length}`);
  
  // Check file size
  const stats = fs.statSync(publicDataPath);
  console.log(`File size: ${(stats.size / 1024 / 1024).toFixed(2)} MB`);
}

exportForests().catch(console.error);