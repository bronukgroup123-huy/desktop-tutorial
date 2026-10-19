import fetch from 'node-fetch';
import fs from 'fs';
import { createClient } from '@supabase/supabase-js';
import { OSMParser } from 'osm-pbf-parser';
import osmtogeojson from 'osmtogeojson';

const PBF_URL = 'https://download.geofabrik.de/europe/ukraine-latest.osm.pbf';
const PBF_FILE = 'ukraine-latest.osm.pbf';
const CHUNK_SIZE = 500;

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

function determineForestType(tags) {
  const wood = tags.wood;
  const species = tags.species?.toLowerCase() || '';
  const leafType = tags.leaf_type;

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

function toMultiPolygon(geometry) {
  if (geometry.type === 'Polygon') {
    return {
      type: 'MultiPolygon',
      coordinates: [geometry.coordinates]
    };
  }
  return geometry;
}

async function downloadPBF() {
  if (fs.existsSync(PBF_FILE)) {
    console.log(`✅ Файл ${PBF_FILE} вже існує, пропускаємо завантаження`);
    return;
  }

  console.log(`📥 Завантаження ${PBF_URL}...`);
  const response = await fetch(PBF_URL);
  
  if (!response.ok) {
    throw new Error(`HTTP error: ${response.status}`);
  }

  const fileStream = fs.createWriteStream(PBF_FILE);
  await new Promise((resolve, reject) => {
    response.body.pipe(fileStream);
    response.body.on('error', reject);
    fileStream.on('finish', resolve);
  });
  
  const stats = fs.statSync(PBF_FILE);
  console.log(`✅ Завантажено ${(stats.size / 1024 / 1024).toFixed(1)} MB`);
}

async function processPBF() {
  console.log('🔄 Початок обробки PBF...');
  
  let buffer = [];
  let totalProcessed = 0;
  let totalInserted = 0;

  const parser = new OSMParser();
  
  parser.on('way', (way) => {
    const tags = way.tags || {};
    
    if (tags.landuse === 'forest' || tags.natural === 'wood') {
      const geojson = osmtogeojson({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          id: way.id,
          properties: tags,
          geometry: way.geometry
        }]
      });

      if (geojson.features.length > 0) {
        const feature = geojson.features[0];
        if (feature.geometry && ['Polygon', 'MultiPolygon'].includes(feature.geometry.type)) {
          buffer.push({
            polygon: toMultiPolygon(feature.geometry),
            forest_type: determineForestType(tags),
            stand_age_years: null,
            stand_age_source: null,
            stand_age_confidence: null,
            relief_type: null,
            light_type: null,
            region_id: null
          });
        }
      }
    }

    if (buffer.length >= CHUNK_SIZE) {
      flushBuffer();
    }
  });

  parser.on('relation', (relation) => {
    const tags = relation.tags || {};
    
    if (tags.landuse === 'forest' || tags.natural === 'wood') {
      const geojson = osmtogeojson({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          id: relation.id,
          properties: tags,
          geometry: relation.geometry
        }]
      });

      if (geojson.features.length > 0) {
        const feature = geojson.features[0];
        if (feature.geometry && ['Polygon', 'MultiPolygon'].includes(feature.geometry.type)) {
          buffer.push({
            polygon: toMultiPolygon(feature.geometry),
            forest_type: determineForestType(tags),
            stand_age_years: null,
            stand_age_source: null,
            stand_age_confidence: null,
            relief_type: null,
            light_type: null,
            region_id: null
          });
        }
      }
    }

    if (buffer.length >= CHUNK_SIZE) {
      flushBuffer();
    }
  });

  async function flushBuffer() {
    if (buffer.length === 0) return;
    
    const chunk = buffer.splice(0, buffer.length);
    totalProcessed += chunk.length;
    
    const { error } = await supabase.from('forest_zones').insert(chunk);
    
    if (error) {
      console.error(`❌ Помилка вставки: ${error.message}`);
    } else {
      totalInserted += chunk.length;
      console.log(`✅ Вставлено ${totalInserted}/${totalProcessed} полігонів`);
    }
  }

  return new Promise((resolve, reject) => {
    const readStream = fs.createReadStream(PBF_FILE);
    
    readStream.on('error', reject);
    readStream.pipe(parser);
    
    parser.on('end', async () => {
      await flushBuffer();
      console.log(`🎉 Завершено! Всього оброблено: ${totalProcessed}, вставлено: ${totalInserted}`);
      resolve();
    });
    
    parser.on('error', reject);
  });
}

async function main() {
  console.log('🇺🇦 Імпорт лісів для всієї України');
  console.log('⚠️  Цей скрипт може працювати кілька годин і споживати ~500 MB трафіку');
  
  try {
    await downloadPBF();
    await processPBF();
  } catch (err) {
    console.error('💥 Критична помилка:', err.message);
    process.exit(1);
  }
}

main();