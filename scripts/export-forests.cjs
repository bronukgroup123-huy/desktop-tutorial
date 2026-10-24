const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: require('path').resolve(process.cwd(), '.env') });

const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function main() {
  console.log('Connecting to Supabase...');
  
  console.log('Querying forest_zones with server-side simplification...');
  
  // Single query with server-side simplification using PostGIS
  // tolerance 0.001 (~110m), precision 3 (~110m) - reduces file to 5-8 MB
  const result = await supabase
    .from('forest_zones')
    .select('id, forest_type, region_id, stand_age_years, ST_AsGeoJSON(ST_SimplifyPreserveTopology(polygon, 0.001), 3) as geometry');
  
  const data = result.data;
  const error = result.error;
  
  if (error) {
    console.error('Query error:', error.message);
    process.exit(1);
  }
  
  if (!data || data.length === 0) {
    console.log('No data found in forest_zones');
    process.exit(1);
  }
  
  console.log('Total records fetched: ' + data.length);
  
  // Convert to GeoJSON FeatureCollection
  const features = data.map(function(row) {
    return {
      type: 'Feature',
      id: row.id,
      geometry: typeof row.geometry === 'string' ? JSON.parse(row.geometry) : row.geometry,
      properties: {
        id: row.id,
        forest_type: row.forest_type,
        region_id: row.region_id,
        stand_age_years: row.stand_age_years
      }
    });
  };
  
  const geojson = {
    type: 'FeatureCollection',
    features: features
  };
  
  // Write to public/data/forests.geojson for static serving
  const publicDataPath = path.resolve(process.cwd(), 'web-guardian/public/data/forests.geojson');
  const publicDataDir = path.dirname(publicDataPath);
  if (!fs.existsSync(publicDataDir)) {
    fs.mkdirSync(publicDataDir, { recursive: true });
  }
  fs.writeFileSync(publicDataPath, JSON.stringify(geojson));
  console.log('GeoJSON written to web-guardian/public/data/forests.geojson');
  console.log('Features count: ' + geojson.features.length);
  
  // Check file size
  const stats = fs.statSync(publicDataPath);
  console.log('File size: ' + (stats.size / 1024 / 1024).toFixed(2) + ' MB');
}

const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: require('path').resolve(process.cwd(), '.env') });

const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function main() {
  console.log('Connecting to Supabase...');
  
  console.log('Querying forest_zones with server-side simplification...');
  
  // Single query with server-side simplification using PostGIS
  // tolerance 0.001 (~110m), precision 3 (~110m) - reduces file to 5-8 MB
  const result = await supabase
    .from('forest_zones')
    .select('id, forest_type, region_id, stand_age_years, ST_AsGeoJSON(ST_SimplifyPreserveTopology(polygon, 0.001), 3) as geometry');
  
  const data = result.data;
  const error = result.error;
  
  if (error) {
    console.error('Query error:', error.message);
    process.exit(1);
  }
  
  if (!data || data.length === 0) {
    console.log('No data found in forest_zones');
    process.exit(1);
  }
  
  console.log('Total records fetched: ' + data.length);
  
  // Convert to GeoJSON FeatureCollection
  const features = data.map(function(row) {
    return {
      type: 'Feature',
      id: row.id,
      geometry: typeof row.geometry === 'string' ? JSON.parse(row.geometry) : row.geometry,
      properties: {
        id: row.id,
        forest_type: row.forest_type,
        region_id: row.region_id,
        stand_age_years: row.stand_age_years
      }
    });
  };
  
  const geojson = {
    type: 'FeatureCollection',
    features: features
  };
  
  // Write to public/data/forests.geojson for static serving
  const publicDataPath = path.resolve(process.cwd(), 'web-guardian/public/data/forests.geojson');
  const publicDataDir = path.dirname(publicDataPath);
  if (!fs.existsSync(publicDataDir)) {
    fs.mkdirSync(publicDataDir, { recursive: true });
  }
  fs.writeFileSync(publicDataPath, JSON.stringify(geojson));
  console.log('GeoJSON written to web-guardian/public/data/forests.geojson');
  console.log('Features count: ' + geojson.features.length);
  
  // Check file size
  const stats = fs.statSync(publicDataPath);
  console.log('File size: ' + (stats.size / 1024 / 1024).toFixed(2) + ' MB');
}

main().catch(console.error);
