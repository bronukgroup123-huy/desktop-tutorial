import fetch from 'node-fetch';
import fs from 'fs';
import osmtogeojson from 'osmtogeojson';

// Приблизні координати Київської області (Bounding Box: lat_min, lon_min, lat_max, lon_max)
const BBOX = '50.1,29.5,51.2,32.2'; 

async function downloadKyivForests() {
  console.log('🌲 Завантаження даних з Overpass API для Київської області...');
  console.log(`📍 Bounding Box: ${BBOX}`);

  // Запит: шукаємо ліси (landuse=forest, natural=wood)
  const query = `
    [out:json][timeout:300];
    (
      way["landuse"="forest"](${BBOX});
      way["natural"="wood"](${BBOX});
    );
    out geom;
  `;

  const url = 'https://overpass-api.de/api/interpreter';
  
  try {
    console.log('⏳ Надсилання запиту до Overpass API (це може зайняти 10-30 секунд)...');
    
    const response = await fetch(url, {
      method: 'POST',
      body: query,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status} - ${response.statusText}`);
    }
    
    const osmData = await response.json();
    console.log(`✅ Отримано ${osmData.elements.length} елементів OSM.`);

    if (osmData.elements.length === 0) {
      console.warn('⚠️ Увага: Overpass API не знайшов жодного лісу за цими координатами. Можливо, потрібно змінити BBOX.');
      return;
    }

    console.log('🔄 Конвертація OSM-даних у GeoJSON...');
    const geojson = osmtogeojson(osmData);
    
    // Зберігаємо у файл
    const outputFile = 'kyiv_forests.geojson';
    fs.writeFileSync(outputFile, JSON.stringify(geojson, null, 2));
    
    console.log(`✅ Дані успішно збережено у файл: ${outputFile}`);
    console.log(`📊 Кількість полігонів (features): ${geojson.features.length}`);
    
  } catch (error) {
    console.error('❌ Помилка завантаження:', error.message);
  }
}

downloadKyivForests();