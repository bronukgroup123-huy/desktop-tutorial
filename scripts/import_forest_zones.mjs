import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import fs from 'fs';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const CHUNK_SIZE = 500;

function toMultiPolygon(geometry) {
  if (geometry.type === 'Polygon') {
    return {
      type: 'MultiPolygon',
      coordinates: [geometry.coordinates]
    };
  }
  return geometry;
}

function determineForestType(properties) {
  const wood = properties.wood;
  const species = properties.species?.toLowerCase() || '';
  const leafType = properties.leaf_type;

  if (wood === 'coniferous' || leafType === 'needleleaved' || 
      species.includes('pine') || species.includes('spruce') || 
      species.includes('fir') || species.includes('cedar') || 
      species.includes('larch')) {
    return 'pine';
  }
  if (wood === 'deciduous' || leafType === 'broadleaved' || 
      species.includes('oak') || species.includes('quercus')) {
    return 'oak';
  }
  if (species.includes('birch') || species.includes('betula')) {
    return 'birch';
  }
  return 'mixed';
}

async function importForestZones() {
  console.log('📖 Читання файлу kyiv_forests.geojson...');
  const geojson = JSON.parse(fs.readFileSync('kyiv_forests.geojson', 'utf-8'));
  
  const polygons = geojson.features
    .filter(f => f.geometry && ['Polygon', 'MultiPolygon'].includes(f.geometry.type))
    .map(f => ({
      polygon: toMultiPolygon(f.geometry),
      forest_type: determineForestType(f.properties || {}),
      stand_age_years: null,
      stand_age_source: null,
      stand_age_confidence: null,
      relief_type: null,
      light_type: null,
      region_id: null
    }));

  console.log(`🔍 Знайдено ${polygons.length} полігонів для імпорту`);

  for (let i = 0; i < polygons.length; i += CHUNK_SIZE) {
    const chunk = polygons.slice(i, i + CHUNK_SIZE);
    const { error } = await supabase.from('forest_zones').insert(chunk);
    
    if (error) {
      console.error(`❌ Помилка вставки чанку ${Math.floor(i / CHUNK_SIZE) + 1}:`, error.message);
      throw error;
    }
    console.log(`✅ Вставлено чанк ${Math.floor(i / CHUNK_SIZE) + 1}/${Math.ceil(polygons.length / CHUNK_SIZE)} (${chunk.length} записів)`);
  }
  
  console.log('🎉 Імпорт завершено успішно!');
}

importForestZones().catch(err => {
  console.error('💥 Критична помилка:', err.message);
  process.exit(1);
});