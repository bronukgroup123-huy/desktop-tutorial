const path = require('path');
require('dotenv').config({ path: path.resolve(process.cwd(), '.env') });
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function main() {
  console.log('Починаємо порційне завантаження...');
  
  let allFeatures = [];
  let pageSize = 2000;
  let offset = 0;
  let hasMore = true;

  while (hasMore) {
    console.log(`Завантаження порції: ${offset} - ${offset + pageSize}...`);
    
    const { data: pageData, error } = await supabase
      .rpc('get_forests_page', { page_offset: offset, page_limit: pageSize });

    if (error) {
      console.error('Помилка отримання даних:', error);
      process.exit(1);
    }

    if (pageData && pageData.length > 0) {
      allFeatures = allFeatures.concat(pageData);
      offset += pageSize;
    } else {
      hasMore = false;
    }
  }

  console.log(`Всього завантажено полігонів: ${allFeatures.length}`);

  const geojson = {
    type: 'FeatureCollection',
    features: allFeatures
  };

  console.log('Завантажуємо в Supabase Storage...');
  const body = Buffer.from(JSON.stringify(geojson), 'utf8');

  const { error: uploadError } = await supabase.storage
    .from('forest-data')
    .upload('forests.geojson', body, {
      contentType: 'application/geo+json',
      upsert: true,
    });

  if (uploadError) {
    console.error('Помилка завантаження в Storage:', uploadError);
    process.exit(1);
  }

  const { data: urlData } = supabase.storage
    .from('forest-data')
    .getPublicUrl('forests.geojson');

  console.log('\n✅ ГОТОВО! Файл успішно оновлено:');
  console.log(urlData.publicUrl);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
